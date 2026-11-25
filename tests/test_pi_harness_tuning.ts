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
	canonicalToolCallKey,
	createDoomLoopTracker,
	normalizeBashErrorSignature,
} from "../.pi/agent/extensions/harness-tuning/doom-loop.ts";
import { buildExploreArgs, parseExploreJsonLine, selectExploreModel } from "../.pi/agent/extensions/harness-tuning/explore.ts";
import { createFileFreshnessTracker } from "../.pi/agent/extensions/harness-tuning/file-freshness.ts";
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

test("explore model routing, CLI flags, and JSONL parsing behave deterministically", () => {
	const available = [
		{ provider: "openai-codex", id: "gpt-6.2-sol" },
		{ provider: "openai-codex", id: "gpt-6.2-astra" },
		{ provider: "claude-bridge", id: "claude-opus-5-5" },
		{ provider: "claude-bridge", id: "claude-sonnet-5-5" },
	];

	const codexChoice = selectExploreModel({ provider: "openai-codex", id: "gpt-6.2-sol" }, available);
	assert.deepEqual(codexChoice, { provider: "openai-codex", id: "gpt-6.2-astra" });

	const codexArgs = buildExploreArgs("Find auth entrypoints", codexChoice);
	assert.ok(codexArgs.includes("--no-extensions"));
	assert.ok(codexArgs.includes("--no-session"));
	assert.ok(codexArgs.includes("read,grep,find,ls"));
	assert.equal(codexArgs[codexArgs.indexOf("--model") + 1], "openai-codex/gpt-6.2-astra");

	const bridgeChoice = selectExploreModel({ provider: "claude-bridge", id: "claude-opus-5-5" }, available);
	assert.deepEqual(bridgeChoice, { provider: "claude-bridge", id: "claude-sonnet-5-5" });
	const bridgeArgs = buildExploreArgs("Trace router", bridgeChoice);
	assert.equal(bridgeArgs.includes("--no-extensions"), false);

	assert.deepEqual(parseExploreJsonLine('{"type":"tool_execution_start","toolName":"grep"}'), {
		toolCallName: "grep",
	});
	assert.deepEqual(
		parseExploreJsonLine(
			JSON.stringify({
				type: "message_end",
				message: { role: "assistant", stopReason: "stop", content: [{ type: "text", text: "Found in src/a.ts:12" }] },
			}),
		),
		{ assistantText: "Found in src/a.ts:12", errorMessage: undefined },
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
