import { strict as assert } from "node:assert";
import { existsSync } from "node:fs";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { computeRoutedTools, executePatchInDirectory, usesPatchModel } from "../.pi/agent/extensions/harness-tuning/apply-patch.ts";
import { AUTO_FORMAT_DISABLE_ENV, createProjectFormatter } from "../.pi/agent/extensions/harness-tuning/auto-format.ts";
import { buildExploreArgs, parseExploreJsonLine, selectExploreModel } from "../.pi/agent/extensions/harness-tuning/explore.ts";
import { countTrailingLengthTruncations, LENGTH_CONTINUATION_TYPE } from "../.pi/agent/extensions/harness-tuning/output-continuation.ts";
import { applyUpdateChunks, formatMissHint, parsePatch } from "../.pi/agent/extensions/harness-tuning/patch-parser.ts";
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
