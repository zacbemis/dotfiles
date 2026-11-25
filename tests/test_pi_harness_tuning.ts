import { strict as assert } from "node:assert";
import { existsSync } from "node:fs";
import { chmod, mkdir, mkdtemp, readFile, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { computeRoutedTools, executePatchInDirectory, usesPatchModel } from "../.pi/agent/extensions/harness-tuning/apply-patch.ts";
import { AUTO_FORMAT_DISABLE_ENV, createProjectFormatter } from "../.pi/agent/extensions/harness-tuning/auto-format.ts";
import {
	BASH_HYGIENE_DISABLE_ENV,
	cleanTerminalOutput,
	sanitizeBashToolResult,
} from "../.pi/agent/extensions/harness-tuning/bash-hygiene.ts";
import {
	COMPACTION_DISABLE_ENV,
	createWarmPrefixTracker,
	enrichFileOpsWithPatch,
	runWarmCompaction,
} from "../.pi/agent/extensions/harness-tuning/compaction.ts";
import {
	canonicalToolCallKey,
	createDoomLoopTracker,
	normalizeBashErrorSignature,
} from "../.pi/agent/extensions/harness-tuning/doom-loop.ts";
import { createFileFreshnessTracker } from "../.pi/agent/extensions/harness-tuning/file-freshness.ts";
import {
	createMicrocompactor,
	getProviderCacheTtlMs,
	MICROCOMPACT_DISABLE_ENV,
} from "../.pi/agent/extensions/harness-tuning/microcompact.ts";
import { countTrailingLengthTruncations, LENGTH_CONTINUATION_TYPE } from "../.pi/agent/extensions/harness-tuning/output-continuation.ts";
import { applyUpdateChunks, formatMissHint, parsePatch } from "../.pi/agent/extensions/harness-tuning/patch-parser.ts";
import {
	createPostEditDiagnostics,
	DIAGNOSTICS_DISABLE_ENV,
} from "../.pi/agent/extensions/harness-tuning/post-edit-diagnostics.ts";
import {
	buildEnvSection,
	buildPromptGuidelines,
	classifyModelFamily,
	createEnvCache,
} from "../.pi/agent/extensions/harness-tuning/prompt-tuning.ts";
import { applyProviderHeaders, tuneOpenAIResponsesPayload } from "../.pi/agent/extensions/harness-tuning/provider-tuning.ts";
import { createReadDedupTracker, READ_DEDUP_DISABLE_ENV } from "../.pi/agent/extensions/harness-tuning/read-dedup.ts";
import {
	buildReadMissingPathHint,
	clampLongLines,
	detectBinaryFile,
	MAX_READ_LINE_CHARS,
	parsePastEofError,
	rankSimilarNames,
	recoverDirectoryRead,
	recoverPastEofRead,
	resolveCanonicalSibling,
	resolveNegativeOffset,
} from "../.pi/agent/extensions/harness-tuning/tool-ergonomics.ts";

test("parsePatch and executePatchInDirectory handle add, update, move, and delete atomically", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-patch-test-"));
	try {
		await writeFile(join(dir, "keep.txt"), "\uFEFFline1\r\nline2\r\nline3\r\n", "utf-8");
		await writeFile(join(dir, "old.txt"), "alpha\nbeta\n", "utf-8");
		await writeFile(join(dir, "remove.txt"), "obsolete\n", "utf-8");

		const patch = `*** Begin Patch
*** Add File: nested/new.txt
+hello
+world
*** Update File: keep.txt
@@
 line1
-line2
+LINE_TWO
 line3
*** Update File: old.txt
*** Move to: moved.txt
@@
 alpha
-beta
+gamma
*** Delete File: remove.txt
*** End Patch`;

		const result = await executePatchInDirectory(dir, patch);
		assert.match(result.text, /A nested\/new\.txt/);
		assert.match(result.text, /M keep\.txt/);
		assert.match(result.text, /M moved\.txt \(moved from old\.txt\)/);
		assert.match(result.text, /D remove\.txt/);

		assert.equal(await readFile(join(dir, "nested/new.txt"), "utf-8"), "hello\nworld\n");
		// Preserves UTF-8 BOM and CRLF line endings.
		assert.equal(await readFile(join(dir, "keep.txt"), "utf-8"), "\uFEFFline1\r\nLINE_TWO\r\nline3\r\n");
		assert.equal(existsSync(join(dir, "old.txt")), false);
		assert.equal(await readFile(join(dir, "moved.txt"), "utf-8"), "alpha\ngamma\n");
		assert.equal(existsSync(join(dir, "remove.txt")), false);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("executePatchInDirectory leaves disk untouched when a later hunk fails", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-patch-atomic-"));
	try {
		await writeFile(join(dir, "a.txt"), "one\ntwo\n", "utf-8");
		await writeFile(join(dir, "b.txt"), "foo\nbar\n", "utf-8");

		const badPatch = `*** Begin Patch
*** Update File: a.txt
@@
-one
+ONE
*** Update File: b.txt
@@
-nonexistent_line
+replacement
*** End Patch`;

		await assert.rejects(() => executePatchInDirectory(dir, badPatch), /Failed to find expected lines in b\.txt/);
		assert.equal(await readFile(join(dir, "a.txt"), "utf-8"), "one\ntwo\n");
		assert.equal(await readFile(join(dir, "b.txt"), "utf-8"), "foo\nbar\n");
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("applyUpdateChunks supports fuzzy typographic matching and EOF anchoring", () => {
	const source = 'function greet() {\n  return “hello — world”;\n}\n';
	const hunks = parsePatch(`*** Begin Patch
*** Update File: demo.ts
@@ function greet()
-  return "hello - world";
+  return "hi";
 }
*** End of File
*** End Patch`);
	assert.equal(hunks.length, 1);
	assert.equal(hunks[0]!.type, "update");
	const updated = applyUpdateChunks(source, "demo.ts", hunks[0]!.chunks);
	assert.equal(updated, 'function greet() {\n  return "hi";\n}\n');
});

test("formatMissHint detects already-applied replacements and closest matching lines", () => {
	const lines = [
		"export function alpha() {",
		"  const count = 42;",
		"  return count + 1;",
		"}",
	];
	assert.match(
		formatMissHint(lines, ["  const count = 10;"], ["  const count = 42;"]),
		/already present in the file/,
	);
	const closest = formatMissHint(lines, [
		"export function alpha() {",
		"  const count = 99;",
		"  return count + 1;",
	]);
	assert.match(closest, /Closest matching lines in file:/);
	assert.match(closest, /2:   const count = 42;/);
});

test("usesPatchModel and computeRoutedTools route GPT-5+/6+ to patch without affecting read-only sessions", () => {
	const sol = { id: "gpt-6.2-sol", compat: { supportsOpenAIGrammarTools: true } };
	const gptOss = { id: "gpt-oss-120b", compat: { supportsOpenAIGrammarTools: true } };
	const gpt4 = { id: "gpt-4.1", compat: { supportsOpenAIGrammarTools: true } };
	const claude = { id: "claude-opus-5-5", compat: { supportsOpenAIGrammarTools: false } };
	const noGrammar = { id: "gpt-6.2-sol", compat: { supportsOpenAIGrammarTools: false } };

	assert.equal(usesPatchModel(sol), true);
	assert.equal(usesPatchModel(gptOss), false);
	assert.equal(usesPatchModel(gpt4), false);
	assert.equal(usesPatchModel(claude), false);
	assert.equal(usesPatchModel(noGrammar), false);

	const available = new Set(["read", "bash", "edit", "write", "grep", "find", "patch", "explore"]);
	assert.deepEqual(
		computeRoutedTools(["read", "bash", "edit", "write", "grep"], available, true),
		["read", "bash", "patch", "grep"],
	);
	assert.deepEqual(
		computeRoutedTools(["read", "bash", "patch", "grep"], available, false),
		["read", "bash", "edit", "write", "grep"],
	);
	// Read-only sessions stay read-only.
	assert.equal(computeRoutedTools(["read", "grep", "find"], available, true), undefined);
	// Already routed is a no-op.
	assert.equal(computeRoutedTools(["read", "bash", "patch"], available, true), undefined);
});

test("clampLongLines and resolveNegativeOffset bound minified lines and support tail reads", () => {
	const short = "line 1\nline 2";
	assert.deepEqual(clampLongLines(short), { text: short, changed: false });

	const longLine = "x".repeat(MAX_READ_LINE_CHARS + 500);
	const clamped = clampLongLines(`head\n${longLine}\ntail`);
	assert.equal(clamped.changed, true);
	const parts = clamped.text.split("\n");
	assert.equal(parts[0], "head");
	assert.match(parts[1]!, /\.\.\. \(line truncated to 2000 chars\)$/);
	assert.equal(parts[2], "tail");

	assert.equal(resolveNegativeOffset(200, -50), 151);
	assert.equal(resolveNegativeOffset(100, -500), 1);
	assert.equal(resolveNegativeOffset(100, 10), 10);
});

test("countTrailingLengthTruncations counts consecutive length stops up to continuation limit", () => {
	assert.equal(countTrailingLengthTruncations([{ role: "assistant", stopReason: "stop" }]), 0);
	assert.equal(countTrailingLengthTruncations([{ role: "assistant", stopReason: "length" }]), 1);
	assert.equal(
		countTrailingLengthTruncations([
			{ role: "user" },
			{ role: "assistant", stopReason: "length" },
			{ role: "custom", customType: LENGTH_CONTINUATION_TYPE },
			{ role: "assistant", stopReason: "length" },
		]),
		2,
	);
	assert.equal(
		countTrailingLengthTruncations([
			{ role: "assistant", stopReason: "length" },
			{ role: "custom", customType: LENGTH_CONTINUATION_TYPE },
			{ role: "assistant", stopReason: "length" },
			{ role: "custom", customType: LENGTH_CONTINUATION_TYPE },
			{ role: "assistant", stopReason: "length" },
		]),
		3,
	);
});

test("prompt-tuning classifies model families, builds targeted rules, and renders cache-safe env", async () => {
	assert.equal(classifyModelFamily({ id: "gpt-6.2-sol" }), "gpt");
	assert.equal(classifyModelFamily({ id: "gpt-5.4" }), "gpt");
	assert.equal(classifyModelFamily({ id: "gpt-4.1" }), "other");
	assert.equal(classifyModelFamily({ id: "gpt-oss-120b" }), "other");
	assert.equal(classifyModelFamily({ id: "claude-opus-5-5" }), "claude");

	const gptRules = buildPromptGuidelines({ model: { id: "gpt-6.2-sol" }, activeTools: ["read", "bash", "patch"] });
	assert.ok(gptRules.some((r) => r.includes("parallelizing independent tool calls")));
	assert.ok(gptRules.some((r) => r.includes("echo '===='")));
	assert.ok(gptRules.some((r) => r.includes("Do not narrate routine reads")));

	const claudeNoBash = buildPromptGuidelines({ model: { id: "claude-opus-5-5" }, activeTools: ["read", "grep"] });
	assert.equal(claudeNoBash.some((r) => r.includes("echo '===='")), false);
	assert.ok(claudeNoBash.some((r) => r.includes("surrounding comment density")));

	const envText = buildEnvSection({
		dateString: "Wed Nov 25 2026",
		platform: "linux",
		arch: "x64",
		shell: "bash",
		cwd: "/repo/packages/app",
		gitRoot: "/repo",
	});
	assert.match(envText, /^Date: Wed Nov 25 2026/m);
	assert.match(envText, /^Git repo: yes$/m);
	assert.match(envText, /^Workspace root: \/repo$/m);

	const dir = await mkdtemp(join(tmpdir(), "pi-env-test-"));
	try {
		await mkdir(join(dir, ".git"));
		await mkdir(join(dir, "nested"));
		const cache = createEnvCache();
		const nestedEnv = await cache.resolveEnvSection(join(dir, "nested"), new Date("2026-11-25T12:00:00Z"));
		assert.match(nestedEnv, /Git repo: yes/);
		assert.match(nestedEnv, new RegExp(`Workspace root: ${dir.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("provider-tuning sets OpenAI Responses low verbosity, omits large max_output_tokens, and adds xAI cache header", () => {
	const gptModel = { provider: "openai", api: "openai-responses", id: "gpt-6.2-sol" };
	const tuned = tuneOpenAIResponsesPayload({ model: "gpt-6.2-sol", max_output_tokens: 32000 }, gptModel) as Record<
		string,
		unknown
	>;
	assert.deepEqual(tuned.text, { verbosity: "low" });
	assert.equal("max_output_tokens" in tuned, false);

	// Preserve tiny cache-warming probes (maxTokens: 1 -> 16).
	const warm = tuneOpenAIResponsesPayload(
		{ model: "gpt-6.2-sol", max_output_tokens: 16, text: { verbosity: "low" } },
		gptModel,
	);
	assert.equal(warm, undefined);

	// Do not touch Codex or non-OpenAI providers.
	assert.equal(
		tuneOpenAIResponsesPayload(
			{ max_output_tokens: 32000 },
			{ provider: "openai-codex", api: "openai-codex-responses", id: "gpt-6.2-sol" },
		),
		undefined,
	);

	const headers: Record<string, string | null> = {};
	applyProviderHeaders(headers, { provider: "xai", id: "grok-4" }, "sess-123");
	assert.equal(headers["x-grok-conv-id"], "sess-123");
});

test("read ergonomics guard binary files, resolve canonical siblings, suggest missing paths, and recover past-EOF and directories", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-read-ergonomics-"));
	const workspace = join(root, "repo");
	try {
		await mkdir(join(workspace, "src"), { recursive: true });
		await writeFile(join(workspace, "src", "index.ts"), "one\ntwo\nthree\nfour\nfive\n", "utf-8");
		await writeFile(join(workspace, "src", "notes\u00a0final.txt"), "hello\n", "utf-8");
		await writeFile(join(workspace, "bin.dat"), Buffer.from([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01]));
		await writeFile(
			join(workspace, "tiny.png"),
			Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]),
		);

		assert.equal(await detectBinaryFile(workspace, "bin.dat"), true);
		assert.equal(await detectBinaryFile(workspace, "tiny.png"), false);
		assert.equal(await detectBinaryFile(workspace, "src/index.ts"), false);

		assert.equal(await resolveCanonicalSibling(workspace, "src/notes final.txt"), "src/notes\u00a0final.txt");

		assert.deepEqual(rankSimilarNames(["index.ts", "indexer.ts", "other.md", "INDEX.md"], "index.js"), [
			"index.ts",
			"INDEX.md",
			"indexer.ts",
		]);

		// Reroot suggestion when repo directory name was dropped.
		const rerootHint = await buildReadMissingPathHint(workspace, join(root, "src", "index.ts"));
		assert.match(rerootHint, /Did you mean one of these\?/);
		assert.match(rerootHint, /repo\/src\/index\.ts/);

		// Missing folder walk-up + typo suggestion.
		const folderHint = await buildReadMissingPathHint(workspace, "srcx/missing.ts");
		assert.match(folderHint, /does not exist\. The nearest existing folder is/);
		assert.match(folderHint, /src/);

		// Past-EOF recovery.
		const parsed = parsePastEofError("Offset 50 is beyond end of file (5 lines total)");
		assert.deepEqual(parsed, { offset: 50, totalLines: 5 });
		const tail = await recoverPastEofRead(workspace, "src/index.ts", 50, 3);
		assert.ok(tail);
		assert.match(tail, /Showing lines 3-5:/);
		assert.match(tail, /three\nfour\nfive$/);

		// Directory listing fallback.
		const listing = await recoverDirectoryRead(workspace, ".");
		assert.ok(listing);
		assert.match(listing, /^Read directory \., entries 1-3 of 3\nsrc\/\nbin\.dat\ntiny\.png$/);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("createProjectFormatter runs configured project formatters silently and skips unconfigured repos", async () => {
	const configuredRepo = await mkdtemp(join(tmpdir(), "pi-fmt-configured-"));
	const plainRepo = await mkdtemp(join(tmpdir(), "pi-fmt-plain-"));
	try {
		await mkdir(join(configuredRepo, "node_modules", ".bin"), { recursive: true });
		await writeFile(
			join(configuredRepo, "package.json"),
			JSON.stringify({ devDependencies: { prettier: "^3.0.0" } }),
			"utf-8",
		);
		const fakePrettier = join(configuredRepo, "node_modules", ".bin", "prettier");
		await writeFile(
			fakePrettier,
			`#!/usr/bin/env node
const fs = require("node:fs");
const file = process.argv[process.argv.length - 1];
fs.writeFileSync(file, fs.readFileSync(file, "utf8").trim() + "\\n// formatted\\n", "utf8");
`,
			"utf-8",
		);
		await chmod(fakePrettier, 0o755);

		const target = join(configuredRepo, "app.ts");
		await writeFile(target, "const x=1;   \n", "utf-8");

		const formatter = createProjectFormatter({ timeoutMs: 3_000 });
		assert.equal(await formatter.formatFile(configuredRepo, "app.ts"), true);
		assert.equal(await readFile(target, "utf-8"), "const x=1;\n// formatted\n");

		// Opt-out env disables formatting.
		process.env[AUTO_FORMAT_DISABLE_ENV] = "0";
		try {
			await writeFile(target, "const y=2;\n", "utf-8");
			assert.equal(await formatter.formatFile(configuredRepo, "app.ts"), false);
			assert.equal(await readFile(target, "utf-8"), "const y=2;\n");
		} finally {
			delete process.env[AUTO_FORMAT_DISABLE_ENV];
		}

		// Plain repo without formatter config is untouched.
		await writeFile(join(plainRepo, "app.ts"), "const z=3;\n", "utf-8");
		assert.equal(await formatter.formatFile(plainRepo, "app.ts"), false);
	} finally {
		await rm(configuredRepo, { recursive: true, force: true });
		await rm(plainRepo, { recursive: true, force: true });
	}
});

test("bash hygiene strips ANSI/OSC, collapses CR spinners and repeated lines, and slices truncated logs head+tail", async () => {
	const noisy = [
		"\x1b]0;Build\x07\x1b[32mPASS\x1b[0m src/a.test.ts",
		"Downloading 10%\rDownloading 50%\rDownloading 100%\rDone",
		"WARN: noisy line",
		"WARN: noisy line",
		"WARN: noisy line",
		"WARN: noisy line",
		"WARN: noisy line",
		"Final line",
	].join("\n");

	const cleaned = cleanTerminalOutput(noisy);
	assert.equal(
		cleaned,
		["PASS src/a.test.ts", "Done", "WARN: noisy line", "[... repeated 4 more times ...]", "Final line"].join("\n"),
	);

	// Truncated bash output with fullOutputPath switches to head+tail and preserves trailing exit code.
	const dir = await mkdtemp(join(tmpdir(), "pi-bash-hygiene-"));
	try {
		const logPath = join(dir, "full.log");
		const lines: string[] = ["\x1b[31mROOT CAUSE ERROR at line 1\x1b[0m"];
		for (let i = 0; i < 600; i++) {
			lines.push(`log line ${i}: ${"x".repeat(60)}`);
		}
		lines.push("FINAL SUMMARY: 1 failed");
		await writeFile(logPath, lines.join("\n"), "utf-8");

		const sanitized = await sanitizeBashToolResult(
			"tail-only text\n\nCommand exited with code 1",
			{ truncation: { truncated: true, totalLines: lines.length }, fullOutputPath: logPath },
			true,
			{ maxBytes: 8_192, maxLines: 80 },
		);
		assert.equal(sanitized.changed, true);
		assert.match(sanitized.text, /^ROOT CAUSE ERROR at line 1/);
		assert.match(sanitized.text, /\[\.\.\. middle omitted/);
		assert.match(sanitized.text, /FINAL SUMMARY: 1 failed\n\nCommand exited with code 1$/);
		assert.doesNotMatch(sanitized.text, /\x1b\[/);

		// Opt-out env skips sanitization.
		process.env[BASH_HYGIENE_DISABLE_ENV] = "0";
		try {
			const raw = "\x1b[31mred\x1b[0m";
			const untouched = await sanitizeBashToolResult(raw, undefined, false);
			assert.deepEqual(untouched, { text: raw, changed: false });
		} finally {
			delete process.env[BASH_HYGIENE_DISABLE_ENV];
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("doom-loop tracker detects consecutive repeats, repeated edit failures, and identical bash errors", () => {
	assert.equal(
		canonicalToolCallKey("grep", { b: 2, a: 1 }),
		canonicalToolCallKey("grep", { a: 1, b: 2 }),
	);
	assert.equal(
		normalizeBashErrorSignature("2026-11-25T19:00:01Z FAIL in 120ms /tmp/pi-bash-abc.log\nAssertionError: x"),
		normalizeBashErrorSignature("2026-11-25T19:01:55Z FAIL in 980ms /tmp/pi-bash-xyz.log\nAssertionError: x"),
	);

	const tracker = createDoomLoopTracker();
	const cwd = "/tmp/workspace";

	// 1. Consecutive identical calls trigger on 3rd repeat.
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "grep", input: { pattern: "foo" }, isError: false, resultText: "no match" }),
		undefined,
	);
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "grep", input: { pattern: "foo" }, isError: false, resultText: "no match" }),
		undefined,
	);
	const repeatNotice = tracker.recordToolResult({
		cwd,
		toolName: "grep",
		input: { pattern: "foo" },
		isError: false,
		resultText: "no match",
	});
	assert.match(repeatNotice ?? "", /exact grep call 3 times consecutively/);

	// 2. Repeated edit failures on same file trigger on 3rd failure, reset on fresh read.
	tracker.reset();
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "edit", input: { path: "a.ts", oldText: "1" }, isError: true, resultText: "miss" }),
		undefined,
	);
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "edit", input: { path: "a.ts", oldText: "2" }, isError: true, resultText: "miss" }),
		undefined,
	);
	const editNotice = tracker.recordToolResult({
		cwd,
		toolName: "edit",
		input: { path: "a.ts", oldText: "3" },
		isError: true,
		resultText: "miss",
	});
	assert.match(editNotice ?? "", /edit has failed 3 times/);

	// Reading the file clears its failure counter.
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "read", input: { path: "a.ts" }, isError: false, resultText: "content" }),
		undefined,
	);
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "edit", input: { path: "a.ts", oldText: "4" }, isError: true, resultText: "miss" }),
		undefined,
	);

	// 3. Repeated identical bash error across intervening edits triggers on 3rd identical failure.
	tracker.reset();
	for (let i = 1; i <= 3; i++) {
		const notice = tracker.recordToolResult({
			cwd,
			toolName: "bash",
			input: { command: "npm test" },
			isError: true,
			resultText: `2026-11-25T19:00:0${i}Z FAIL test.ts (${i}00ms)\nTypeError: boom`,
		});
		if (i < 3) {
			assert.equal(notice, undefined);
			tracker.recordToolResult({
				cwd,
				toolName: "edit",
				input: { path: "src.ts", oldText: `v${i}` },
				isError: false,
				resultText: "ok",
			});
		} else {
			assert.match(notice ?? "", /failed with the same error 3 times in a row/);
		}
	}

	// Passing run clears the streak.
	assert.equal(
		tracker.recordToolResult({ cwd, toolName: "bash", input: { command: "npm test" }, isError: false, resultText: "ok" }),
		undefined,
	);
});

test("file-freshness tracker blocks external edits until re-read and integrates with patch beforeApply", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-freshness-"));
	try {
		const target = join(dir, "app.ts");
		await writeFile(target, "export const v = 1;\n", "utf-8");
		const tracker = createFileFreshnessTracker();

		// Untracked files are allowed.
		assert.equal((await tracker.checkFreshness(dir, "app.ts")).stale, false);

		// Record read state; unchanged file stays fresh.
		await tracker.recordFromDisk(dir, "app.ts");
		assert.equal((await tracker.checkFreshness(dir, "app.ts")).stale, false);

		// Simulate external edit changing mtime and content.
		await writeFile(target, "export const v = 2; // external\n", "utf-8");
		const future = new Date(Date.now() + 5_000);
		await utimes(target, future, future);

		const staleCheck = await tracker.checkFreshness(dir, "app.ts");
		assert.equal(staleCheck.stale, true);
		assert.match(staleCheck.reason ?? "", /modified on disk since it was last read/);

		// Patch beforeApply rejects atomically without modifying disk.
		const patch = `*** Begin Patch
*** Update File: app.ts
@@
-export const v = 2; // external
+export const v = 3;
*** End Patch`;
		await assert.rejects(
			() =>
				executePatchInDirectory(dir, patch, undefined, async (hunks) => {
					const check = await tracker.checkPathsForPatch(dir, hunks);
					if (check.stale) throw new Error(check.reason);
				}),
			/modified on disk since it was last read/,
		);
		assert.equal(await readFile(target, "utf-8"), "export const v = 2; // external\n");

		// Re-reading refreshes snapshot and allows patch.
		await tracker.recordFromDisk(dir, "app.ts");
		const applied = await executePatchInDirectory(dir, patch, undefined, async (hunks) => {
			const check = await tracker.checkPathsForPatch(dir, hunks);
			if (check.stale) throw new Error(check.reason);
		});
		assert.equal(applied.files.length, 1);
		assert.equal(await readFile(target, "utf-8"), "export const v = 3;\n");
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("post-edit diagnostics catch JSON, JS, Python, shell, Go, and local oxlint errors silently when clean", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-diag-"));
	try {
		const diag = createPostEditDiagnostics({ timeoutMs: 3_000 });

		// Valid vs broken JSON (and JSONC tsconfig skipped).
		await writeFile(join(dir, "ok.json"), '{"a": 1}\n', "utf-8");
		await writeFile(join(dir, "bad.json"), '{"a": }\n', "utf-8");
		await writeFile(join(dir, "tsconfig.json"), '{\n  // comment allowed in JSONC\n  "compilerOptions": {},\n}\n', "utf-8");
		assert.equal(await diag.checkFile(dir, "ok.json"), undefined);
		assert.equal(await diag.checkFile(dir, "tsconfig.json"), undefined);
		assert.match((await diag.checkFile(dir, "bad.json")) ?? "", /Invalid JSON/);

		// Valid vs broken JS via node --check.
		await writeFile(join(dir, "ok.mjs"), "export const x = 1;\n", "utf-8");
		await writeFile(join(dir, "bad.mjs"), "export const x = ;\n", "utf-8");
		assert.equal(await diag.checkFile(dir, "ok.mjs"), undefined);
		assert.match((await diag.checkFile(dir, "bad.mjs")) ?? "", /SyntaxError/);

		// Valid vs broken Python (ruff / python3).
		await writeFile(join(dir, "ok.py"), "def add(a, b):\n    return a + b\n", "utf-8");
		await writeFile(join(dir, "bad.py"), "def broken():\n    return missing_var + 1\n", "utf-8");
		assert.equal(await diag.checkFile(dir, "ok.py"), undefined);
		assert.match((await diag.checkFile(dir, "bad.py")) ?? "", /F821|SyntaxError|missing_var/);

		// Valid vs broken shell via bash -n.
		await writeFile(join(dir, "ok.sh"), "if true; then echo hi; fi\n", "utf-8");
		await writeFile(join(dir, "bad.sh"), "if true; then echo hi\n", "utf-8");
		assert.equal(await diag.checkFile(dir, "ok.sh"), undefined);
		assert.match((await diag.checkFile(dir, "bad.sh")) ?? "", /syntax error|unexpected end of file/i);

		// Multi-file checkFiles aggregates only broken files.
		const block = await diag.checkFiles(dir, ["ok.json", "bad.json", "ok.mjs", "bad.mjs"]);
		assert.match(block ?? "", /^\[Diagnostics\]\n/);
		assert.match(block ?? "", /bad\.json/);
		assert.match(block ?? "", /bad\.mjs/);
		assert.doesNotMatch(block ?? "", /ok\.json/);

		// Project-local oxlint picked up for .ts files.
		await mkdir(join(dir, "node_modules", ".bin"), { recursive: true });
		const fakeOxlint = join(dir, "node_modules", ".bin", "oxlint");
		await writeFile(
			fakeOxlint,
			`#!/usr/bin/env node
const fs = require("node:fs");
const file = process.argv[process.argv.length - 1];
if (fs.readFileSync(file, "utf8").includes("BAD_TOKEN")) {
  console.error(file + ":1:1 error BAD_TOKEN is forbidden");
  process.exit(1);
}
`,
			"utf-8",
		);
		await chmod(fakeOxlint, 0o755);
		await writeFile(join(dir, "check.ts"), "const x = BAD_TOKEN;\n", "utf-8");
		diag.clear();
		assert.match((await diag.checkFile(dir, "check.ts")) ?? "", /check\.ts:1:1 error BAD_TOKEN/);

		// Opt-out env disables diagnostics.
		process.env[DIAGNOSTICS_DISABLE_ENV] = "0";
		try {
			assert.equal(await diag.checkFiles(dir, ["bad.json"]), undefined);
		} finally {
			delete process.env[DIAGNOSTICS_DISABLE_ENV];
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("warm-prefix compaction reuses transcript prefix, tracks patch file ops, and falls back safely on overflow/toolCall", async () => {
	const tracker = createWarmPrefixTracker();
	const patchText = `*** Begin Patch
*** Add File: src/new.ts
+export const a = 1;
*** Update File: src/old.ts
*** Move to: src/renamed.ts
@@
-const x = 1;
+const x = 2;
*** End Patch`;

	const messages = [
		{ role: "system", content: "system prompt" },
		{ role: "user", content: [{ type: "text", text: "Refactor old.ts" }] },
		{
			role: "assistant",
			content: [{ type: "toolCall", id: "call-1", name: "patch", arguments: { patch: patchText } }],
		},
		{
			role: "toolResult",
			toolCallId: "call-1",
			toolName: "patch",
			content: [{ type: "text", text: "Success." }],
			details: {
				files: [
					{ status: "A", path: "src/new.ts" },
					{ status: "M", path: "src/renamed.ts", movedFrom: "src/old.ts" },
				],
			},
		},
	];

	tracker.recordContextWithSystem(messages);
	tracker.recordAssistantMessage({
		role: "assistant",
		stopReason: "stop",
		content: [{ type: "text", text: "Done refactoring." }],
	});

	const preparation = {
		firstKeptEntryId: "entry-9",
		messagesToSummarize: messages.slice(1),
		turnPrefixMessages: [],
		isSplitTurn: false,
		tokensBefore: 185_000,
		fileOps: { read: new Set(["src/read-only.ts", "src/old.ts"]), written: new Set<string>(), edited: new Set<string>() },
	};

	let capturedMessages: readonly { role: string; content?: unknown }[] = [];
	const result = await runWarmCompaction({
		reason: "threshold",
		preparation,
		cwd: "/tmp/repo",
		sessionId: "sess-123",
		customInstructions: "Focus on migration invariants",
		tracker,
		convertToLlm: (msgs) => msgs,
		collectState: async () => "\n\n<workspace-state>\ngit status:\n M src/renamed.ts\n</workspace-state>",
		completeWarm: async (forked) => {
			capturedMessages = forked;
			return {
				role: "assistant",
				stopReason: "stop",
				content: [{ type: "text", text: "## Goal\nRefactor old.ts" }],
				usage: { input: 1000, output: 120, cacheRead: 180000, cacheWrite: 0, totalTokens: 181120 },
			};
		},
	});

	assert.ok(result);
	assert.equal(capturedMessages[0]?.role, "system");
	// Includes original history + clean trailing assistant reply + compaction user prompt.
	assert.equal(capturedMessages.length, messages.length + 2);
	assert.equal(capturedMessages[capturedMessages.length - 2]?.role, "assistant");
	assert.equal(capturedMessages[capturedMessages.length - 1]?.role, "user");
	assert.match(result.summary, /^## Goal\nRefactor old\.ts/);
	assert.match(result.summary, /<read-files>\nsrc\/read-only\.ts\n<\/read-files>/);
	assert.match(result.summary, /<modified-files>\nsrc\/new\.ts\nsrc\/old\.ts\nsrc\/renamed\.ts\n<\/modified-files>/);
	assert.match(result.summary, /<workspace-state>\ngit status:\n M src\/renamed\.ts\n<\/workspace-state>/);
	assert.equal(result.details?.warmPrefix, true);

	// Overflow falls back to Pi default while still enriching patch fileOps.
	const overflowPrep = {
		firstKeptEntryId: "entry-10",
		messagesToSummarize: messages.slice(1),
		turnPrefixMessages: [],
		isSplitTurn: false,
		tokensBefore: 250_000,
		fileOps: { read: new Set<string>(), written: new Set<string>(), edited: new Set<string>() },
	};
	const overflowRes = await runWarmCompaction({
		reason: "overflow",
		preparation: overflowPrep,
		cwd: "/tmp/repo",
		tracker,
		convertToLlm: (msgs) => msgs,
		completeWarm: async () => {
			throw new Error("should not call completeWarm on overflow");
		},
	});
	assert.equal(overflowRes, undefined);
	assert.ok(overflowPrep.fileOps.written.has("src/new.ts"));
	assert.ok(overflowPrep.fileOps.edited.has("src/old.ts"));

	// Tool-call response falls back safely.
	const toolCallFallback = await runWarmCompaction({
		reason: "manual",
		preparation,
		cwd: "/tmp/repo",
		tracker,
		convertToLlm: (msgs) => msgs,
		completeWarm: async () => ({
			role: "assistant",
			stopReason: "toolUse",
			content: [{ type: "toolCall" }],
		}),
	});
	assert.equal(toolCallFallback, undefined);

	// Opt-out env disables warm compaction while still enriching fileOps.
	process.env[COMPACTION_DISABLE_ENV] = "0";
	try {
		const disabledPrep = {
			...overflowPrep,
			fileOps: { read: new Set<string>(), written: new Set<string>(), edited: new Set<string>() },
		};
		enrichFileOpsWithPatch(disabledPrep.fileOps, []);
		const disabledRes = await runWarmCompaction({
			reason: "manual",
			preparation: disabledPrep,
			cwd: "/tmp/repo",
			tracker,
			convertToLlm: (msgs) => msgs,
			completeWarm: async () => {
				throw new Error("should not run when disabled");
			},
		});
		assert.equal(disabledRes, undefined);
		assert.ok(disabledPrep.fileOps.written.has("src/new.ts"));
	} finally {
		delete process.env[COMPACTION_DISABLE_ENV];
	}
});

test("cold-cache microcompactor prunes stale tool outputs only when cold and keeps stubs sticky on warm turns", () => {
	assert.equal(getProviderCacheTtlMs({ provider: "anthropic", id: "claude-sonnet-4" }), 5 * 60_000);
	assert.equal(getProviderCacheTtlMs({ provider: "openai-codex", id: "gpt-6.2-sol" }), 10 * 60_000);

	const mc = createMicrocompactor({
		keepRecentTurns: 2,
		keepRecentToolResults: 2,
		minPruneChars: 500,
		minContextChars: 1_000,
	});

	const bigRead = "line\n".repeat(400);
	const bigErr = `START_ERROR ${"e".repeat(700)} END_ERROR`;
	const makeHistory = () => [
		{ role: "user", content: [{ type: "text", text: "investigate" }] },
		{
			role: "assistant",
			content: [
				{ type: "toolCall", id: "c1", name: "read", arguments: { path: "src/huge.ts" } },
				{ type: "toolCall", id: "c2", name: "bash", arguments: { command: "npm test" } },
				{ type: "toolCall", id: "c3", name: "edit", arguments: { path: "src/huge.ts" } },
			],
		},
		{ role: "toolResult", toolCallId: "c1", toolName: "read", content: [{ type: "text", text: bigRead }] },
		{ role: "toolResult", toolCallId: "c2", toolName: "bash", isError: true, content: [{ type: "text", text: bigErr }] },
		{ role: "toolResult", toolCallId: "c3", toolName: "edit", content: [{ type: "text", text: bigRead }] },
		{ role: "assistant", content: [{ type: "toolCall", id: "c4", name: "read", arguments: { path: "src/recent1.ts" } }] },
		{ role: "toolResult", toolCallId: "c4", toolName: "read", content: [{ type: "text", text: bigRead }] },
		{ role: "assistant", content: [{ type: "toolCall", id: "c5", name: "read", arguments: { path: "src/recent2.ts" } }] },
		{ role: "toolResult", toolCallId: "c5", toolName: "read", content: [{ type: "text", text: bigRead }] },
	];

	const model = { provider: "openai-codex", id: "gpt-6.2-sol", contextWindow: 500_000 };
	const t0 = 1_000_000;

	// First call (resumed / cold) prunes c1 and c2, preserves edit (c3) and recent turns (c4, c5).
	const first = mc.transformContext(makeHistory(), model, t0);
	assert.ok(first);
	assert.equal(mc.prunedCount, 2);
	const c1Text = (first[2]!.content as { text: string }[])[0]!.text;
	const c2Text = (first[3]!.content as { text: string }[])[0]!.text;
	const c3Text = (first[4]!.content as { text: string }[])[0]!.text;
	const c4Text = (first[6]!.content as { text: string }[])[0]!.text;
	assert.match(c1Text, /\[Microcompacted read of src\/huge\.ts/);
	assert.match(c2Text, /\[Microcompacted bash `npm test`.*error/);
	assert.match(c2Text, /START_ERROR/);
	assert.match(c2Text, /END_ERROR/);
	assert.equal(c3Text, bigRead);
	assert.equal(c4Text, bigRead);

	// Warm follow-up 30s later with a new turn: does NOT prune c4, DOES keep c1/c2 sticky for cache hit.
	const extended = [
		...makeHistory(),
		{ role: "assistant", content: [{ type: "toolCall", id: "c6", name: "read", arguments: { path: "src/recent3.ts" } }] },
		{ role: "toolResult", toolCallId: "c6", toolName: "read", content: [{ type: "text", text: bigRead }] },
	];
	const warm = mc.transformContext(extended, model, t0 + 30_000);
	assert.ok(warm);
	assert.equal(mc.prunedCount, 2);
	assert.match((warm[2]!.content as { text: string }[])[0]!.text, /\[Microcompacted read of src\/huge\.ts/);
	assert.equal((warm[6]!.content as { text: string }[])[0]!.text, bigRead);

	// Cold again after >10 min idle: now c4 ages out and gets pruned too.
	const coldAgain = mc.transformContext(extended, model, t0 + 12 * 60_000);
	assert.ok(coldAgain);
	assert.equal(mc.prunedCount, 3);
	assert.match((coldAgain[6]!.content as { text: string }[])[0]!.text, /\[Microcompacted read of src\/recent1\.ts/);

	// Opt-out env disables microcompact.
	process.env[MICROCOMPACT_DISABLE_ENV] = "0";
	try {
		mc.reset();
		assert.equal(mc.transformContext(makeHistory(), model, t0), undefined);
	} finally {
		delete process.env[MICROCOMPACT_DISABLE_ENV];
	}
});

test("read-dedup tracker stubs unchanged duplicate reads, respects microcompact/edits/escape-hatch, and skips small/image reads", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-read-dedup-"));
	try {
		const bigPath = join(dir, "big.ts");
		const bigBody = `export const data = "${"x".repeat(1500)}";\n`;
		await writeFile(bigPath, bigBody, "utf-8");

		const tracker = createReadDedupTracker({ minDedupChars: 1_000 });
		const pruned = new Set<string>();

		// 1. First read passes through and records.
		const r1 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-1",
			text: bigBody,
			isPruned: (id) => pruned.has(id),
		});
		assert.equal(r1.deduplicated, false);

		// 2. Second identical unchanged read returns compact stub.
		const r2 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-2",
			text: bigBody,
			isPruned: (id) => pruned.has(id),
		});
		assert.equal(r2.deduplicated, true);
		assert.match(r2.stub ?? "", /\[Unchanged since earlier read of big\.ts/);

		// 3. Escape hatch: immediate third identical read passes through so model is never trapped.
		const r3 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-3",
			text: bigBody,
			isPruned: (id) => pruned.has(id),
		});
		assert.equal(r3.deduplicated, false);

		// 4. If earlier read was pruned by microcompact, do NOT stub.
		pruned.add("read-3");
		const r4 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-4",
			text: bigBody,
			isPruned: (id) => pruned.has(id),
		});
		assert.equal(r4.deduplicated, false);

		// 5. Disk modification invalidates cache.
		const updatedBody = `export const data = "${"y".repeat(1600)}";\n`;
		await writeFile(bigPath, updatedBody, "utf-8");
		const future = new Date(Date.now() + 5_000);
		await utimes(bigPath, future, future);
		const r5 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-5",
			text: updatedBody,
		});
		assert.equal(r5.deduplicated, false);

		// 6. Explicit invalidatePath (after edit/write/patch) forces full read next time.
		tracker.invalidatePath(dir, "big.ts");
		const r6 = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-6",
			text: updatedBody,
		});
		assert.equal(r6.deduplicated, false);

		// 7. Images and small reads are never stubbed.
		const imgRead = await tracker.checkAndRecord({
			cwd: dir,
			rawPath: "big.ts",
			toolCallId: "read-img",
			text: updatedBody,
			hasImage: true,
		});
		assert.equal(imgRead.deduplicated, false);

		// 8. Opt-out env disables dedup.
		process.env[READ_DEDUP_DISABLE_ENV] = "0";
		try {
			const disabled = await tracker.checkAndRecord({
				cwd: dir,
				rawPath: "big.ts",
				toolCallId: "read-disabled",
				text: updatedBody,
			});
			assert.equal(disabled.deduplicated, false);
		} finally {
			delete process.env[READ_DEDUP_DISABLE_ENV];
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});
