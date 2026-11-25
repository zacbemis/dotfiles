import { strict as assert } from "node:assert";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DOTFILES_ROOT = resolve(HERE, "..");
const EXT_DIR = join(DOTFILES_ROOT, ".pi/agent/extensions");

const HARNESS_EXT = join(EXT_DIR, "harness-tuning/index.ts");
const LSP_EXT = join(EXT_DIR, "lsp-diagnostics/index.ts");
const EXPLORE_EXT = join(EXT_DIR, "explore/index.ts");

function resolvePiInstallDir(): string | undefined {
	const installRoot = join(homedir(), ".pi/agent/install");
	const versionFile = join(installRoot, "current-version");
	if (existsSync(versionFile)) {
		const ver = readFileSync(versionFile, "utf8").trim();
		const candidate = join(installRoot, "releases", ver, "node_modules/@earendil-works");
		if (existsSync(candidate)) return candidate;
	}
	const releasesDir = join(installRoot, "releases");
	if (!existsSync(releasesDir)) return undefined;
	const versions = readdirSync(releasesDir).sort().reverse();
	for (const ver of versions) {
		const candidate = join(releasesDir, ver, "node_modules/@earendil-works");
		if (existsSync(candidate)) return candidate;
	}
	return undefined;
}

const PI_SCOPE_DIR = resolvePiInstallDir();

async function loadPiModules() {
	assert.ok(PI_SCOPE_DIR, "Pi installation not found under ~/.pi/agent/install");
	const [piCoding, piAi] = await Promise.all([
		import(join(PI_SCOPE_DIR, "pi-coding-agent/dist/index.js")),
		import(join(PI_SCOPE_DIR, "pi-ai/dist/index.js")),
	]);
	return { piCoding, piAi };
}

interface CapturedToolResult {
	readonly toolName: string;
	readonly isError: boolean;
	readonly text: string;
}

interface ScriptedSessionOptions {
	readonly cwd: string;
	readonly extensions: readonly string[];
	readonly modelId?: string;
}

async function createScriptedSession(options: ScriptedSessionOptions) {
	const { piCoding, piAi } = await loadPiModules();
	const agentDir = await mkdtemp(join(tmpdir(), "pi-int-agent-"));
	const modelId = options.modelId ?? "gpt-6-faux";

	const faux = piAi.fauxProvider({
		provider: "faux-codex",
		models: [
			{
				id: modelId,
				name: modelId,
				reasoning: true,
				contextWindow: 200_000,
				maxTokens: 16_384,
			},
		],
	});

	const modelRuntime = await piCoding.ModelRuntime.create({
		authPath: join(agentDir, "auth.json"),
		modelsPath: null,
		refreshOnCreate: false,
	});
	modelRuntime.registerNativeProvider(faux.provider);

	const settingsManager = piCoding.SettingsManager.inMemory({
		compaction: { enabled: true, keepRecentTokens: 100, reserveTokens: 1024 },
	});
	const resourceLoader = new piCoding.DefaultResourceLoader({
		cwd: options.cwd,
		agentDir,
		settingsManager,
		noExtensions: true,
		noSkills: true,
		noPromptTemplates: true,
		noThemes: true,
		noContextFiles: true,
		additionalExtensionPaths: [...options.extensions],
	});
	await resourceLoader.reload();

	const model = faux.getModel(modelId);
	assert.ok(model, `missing faux model ${modelId}`);
	(model as { compat?: Record<string, unknown> }).compat = { supportsOpenAIGrammarTools: true };

	const { session, extensionsResult } = await piCoding.createAgentSession({
		cwd: options.cwd,
		agentDir,
		modelRuntime,
		model,
		thinkingLevel: "low",
		sessionManager: piCoding.SessionManager.inMemory(options.cwd),
		settingsManager,
		resourceLoader,
	});

	const errors: unknown[] = [...extensionsResult.errors];
	await session.bindExtensions({ mode: "rpc", onError: (e: unknown) => errors.push(e) });
	assert.equal(errors.length, 0, `extension load errors: ${JSON.stringify(errors)}`);

	const toolResults: CapturedToolResult[] = [];
	const unsub = session.subscribe((ev: Record<string, unknown>) => {
		if (ev.type === "tool_execution_end") {
			const content = (ev.result as { content?: Array<{ type?: string; text?: string }> } | undefined)?.content;
			const text = Array.isArray(content)
				? content.filter((b) => b.type === "text" && typeof b.text === "string").map((b) => b.text).join("\n")
				: "";
			toolResults.push({
				toolName: String(ev.toolName ?? ""),
				isError: Boolean(ev.isError),
				text,
			});
		}
	});

	async function cleanup() {
		unsub();
		const runner = (session as { _extensionRunner?: { emit?: (e: { type: string }) => Promise<void> } })._extensionRunner;
		await runner?.emit?.({ type: "session_shutdown" });
		await session.dispose();
		await rm(agentDir, { recursive: true, force: true });
	}

	return { session, faux, piAi, toolResults, cleanup };
}

test("integration 1: scripted multi-turn patch routing, read-dedup stubbing, and edit invalidation", async (t) => {
	if (!PI_SCOPE_DIR) return t.skip("Pi installation not found");
	const dir = await mkdtemp(join(tmpdir(), "pi-int-dedup-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	const lines = Array.from(
		{ length: 60 },
		(_, i) => `export const configValue_${i + 1} = "deterministic_payload_segment_${i + 1}";`,
	);
	lines[59] = 'export const MARKER = "BEFORE";';
	await writeFile(join(dir, "app.ts"), `${lines.join("\n")}\n`, "utf8");

	const { session, faux, piAi, toolResults, cleanup } = await createScriptedSession({
		cwd: dir,
		extensions: [HARNESS_EXT],
	});
	t.after(cleanup);

	// GPT-6 model should route to patch instead of edit/write.
	const activeTools = session.getActiveToolNames();
	assert.ok(activeTools.includes("patch"), `expected patch active, got ${activeTools.join(",")}`);
	assert.equal(activeTools.includes("edit"), false);
	assert.equal(activeTools.includes("write"), false);

	faux.setResponses([
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "app.ts" })),
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "app.ts" })),
		piAi.fauxAssistantMessage(
			piAi.fauxToolCall("patch", {
				patch: [
					"*** Begin Patch",
					"*** Update File: app.ts",
					"@@",
					'-export const MARKER = "BEFORE";',
					'+export const MARKER = "AFTER";',
					"*** End Patch",
				].join("\n"),
			}),
		),
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "app.ts" })),
		piAi.fauxAssistantMessage("Updated MARKER to AFTER."),
	]);

	await session.prompt("Read app.ts, verify dedup, patch MARKER, and re-read.");

	const reads = toolResults.filter((r) => r.toolName === "read");
	assert.equal(reads.length, 3);
	assert.match(reads[0]!.text, /BEFORE/);
	assert.match(reads[1]!.text, /Unchanged since earlier read/);
	assert.doesNotMatch(reads[2]!.text, /Unchanged since earlier read/);
	assert.match(reads[2]!.text, /AFTER/);
});

test("integration 2: file-freshness blocks stale patch after external disk change and succeeds after re-read", async (t) => {
	if (!PI_SCOPE_DIR) return t.skip("Pi installation not found");
	const dir = await mkdtemp(join(tmpdir(), "pi-int-fresh-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	const filePath = join(dir, "config.txt");
	await writeFile(filePath, "alpha=1\nbeta=2\n", "utf8");

	const { session, faux, piAi, toolResults, cleanup } = await createScriptedSession({
		cwd: dir,
		extensions: [HARNESS_EXT],
	});
	t.after(cleanup);

	faux.setResponses([
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "config.txt" })),
		async () => {
			// Simulate external modification between model turns.
			await new Promise((r) => setTimeout(r, 25));
			await writeFile(filePath, "alpha=1\nbeta=EXTERNAL\n", "utf8");
			return piAi.fauxAssistantMessage(
				piAi.fauxToolCall("patch", {
					patch: [
						"*** Begin Patch",
						"*** Update File: config.txt",
						"@@",
						"-alpha=1",
						"+alpha=2",
						"*** End Patch",
					].join("\n"),
				}),
			);
		},
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "config.txt" })),
		piAi.fauxAssistantMessage(
			piAi.fauxToolCall("patch", {
				patch: [
					"*** Begin Patch",
					"*** Update File: config.txt",
					"@@",
					"-alpha=1",
					"+alpha=2",
					"*** End Patch",
				].join("\n"),
			}),
		),
		piAi.fauxAssistantMessage("Done after re-read."),
	]);

	await session.prompt("Update alpha in config.txt");

	const patches = toolResults.filter((r) => r.toolName === "patch");
	assert.equal(patches.length, 2);
	assert.equal(patches[0]!.isError, true);
	assert.match(patches[0]!.text, /modified externally|re-read/i);
	assert.equal(patches[1]!.isError, false);
	assert.equal(await readFile(filePath, "utf8"), "alpha=2\nbeta=EXTERNAL\n");
});

test("integration 3: commit attribution guard, sub-50KB bash-hygiene slicing, and doom-loop nudge", async (t) => {
	if (!PI_SCOPE_DIR) return t.skip("Pi installation not found");
	const dir = await mkdtemp(join(tmpdir(), "pi-int-bash-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(
		join(dir, "sub50k.mjs"),
		`
console.log("\\x1b[31mTOP_SUB50K_ERR\\x1b[0m");
for (let i = 0; i < 30; i++) console.log("WARN: spam");
for (let i = 0; i < 320; i++) console.log("PASS case #" + i + " " + "ok_".repeat(25));
console.log("\\x1b[33mBOT_SUB50K_ERR\\x1b[0m");
process.exitCode = 1;
`,
		"utf8",
	);

	const { session, faux, piAi, toolResults, cleanup } = await createScriptedSession({
		cwd: dir,
		extensions: [HARNESS_EXT],
	});
	t.after(cleanup);

	faux.setResponses([
		// 1. Blocked commit attribution trailer
		piAi.fauxAssistantMessage(
			piAi.fauxToolCall("bash", {
				command: 'git commit -m "chore: test\n\nCo-Authored-By: Claude <noreply@anthropic.com>"',
			}),
		),
		// 2. Sub-50KB noisy output -> cleaned + head/tail sliced
		piAi.fauxAssistantMessage(piAi.fauxToolCall("bash", { command: "node sub50k.mjs" })),
		// 3-5. Three identical failing reads -> triggers doom-loop nudge on 3rd
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "does-not-exist.ts" })),
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "does-not-exist.ts" })),
		piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "does-not-exist.ts" })),
		piAi.fauxAssistantMessage("Observed guards."),
	]);

	await session.prompt("Exercise guards.");

	const bashResults = toolResults.filter((r) => r.toolName === "bash");
	assert.equal(bashResults.length, 2);
	assert.equal(bashResults[0]!.isError, true);
	assert.match(bashResults[0]!.text, /Remove AI\/Claude attribution/);

	// Sub-50KB output (~27KB raw) should be ANSI-stripped, repeat-collapsed, and head+tail sliced.
	assert.equal(bashResults[1]!.text.includes("\x1b["), false);
	assert.match(bashResults[1]!.text, /TOP_SUB50K_ERR/);
	assert.match(bashResults[1]!.text, /repeated 29 more times/);
	assert.match(bashResults[1]!.text, /\[\.\.\. middle omitted/);
	assert.match(bashResults[1]!.text, /BOT_SUB50K_ERR/);
	const cleanPath = bashResults[1]!.text.match(/Full output: ([^\s\]]+)/)?.[1];
	if (cleanPath) await rm(cleanPath, { force: true });

	const failedReads = toolResults.filter((r) => r.toolName === "read");
	assert.equal(failedReads.length, 3);
	assert.match(failedReads[2]!.text, /\[Loop warning\]|repeating/i);
});

test("integration 4: lsp workspace gating disables lsp in plain dirs and settle-guard blocks broken TS settle", async (t) => {
	if (!PI_SCOPE_DIR) return t.skip("Pi installation not found");

	// Part A: non-LSP directory -> lsp tool should be gated off at session_start.
	const plainDir = await mkdtemp(join(tmpdir(), "pi-int-nolsp-"));
	t.after(() => rm(plainDir, { recursive: true, force: true }));
	await writeFile(join(plainDir, "readme.md"), "# Plain repo\n", "utf8");

	const plainSession = await createScriptedSession({
		cwd: plainDir,
		extensions: [HARNESS_EXT, LSP_EXT],
	});
	try {
		assert.equal(plainSession.session.getActiveToolNames().includes("lsp"), false);
	} finally {
		await plainSession.cleanup();
	}

	// Part B: TypeScript directory -> lsp active, bad patch triggers LSP diagnostics + settle-guard retry.
	const tsDir = await mkdtemp(join(tmpdir(), "pi-int-tslsp-"));
	t.after(() => rm(tsDir, { recursive: true, force: true }));
	await writeFile(
		join(tsDir, "tsconfig.json"),
		JSON.stringify({ compilerOptions: { target: "ES2022", module: "ESNext", strict: true, noEmit: true } }),
		"utf8",
	);
	await writeFile(join(tsDir, "calc.ts"), "export function add(a: number, b: number): number { return a + b; }\n", "utf8");

	const tsSession = await createScriptedSession({
		cwd: tsDir,
		extensions: [HARNESS_EXT, LSP_EXT],
	});
	t.after(tsSession.cleanup);

	// Skip Part B only if typescript-language-server isn't installed on this machine.
	if (!tsSession.session.getActiveToolNames().includes("lsp")) {
		return t.skip("typescript-language-server not installed");
	}

	let settlePromptsSeen = 0;
	tsSession.faux.setResponses([
		tsSession.piAi.fauxAssistantMessage(tsSession.piAi.fauxToolCall("read", { path: "calc.ts" })),
		// Introduce type error
		tsSession.piAi.fauxAssistantMessage(
			tsSession.piAi.fauxToolCall("patch", {
				patch: [
					"*** Begin Patch",
					"*** Update File: calc.ts",
					"@@",
					"-export function add(a: number, b: number): number { return a + b; }",
					'+export function add(a: number, b: number): number { return "wrong"; }',
					"*** End Patch",
				].join("\n"),
			}),
		),
		// Try to settle while TS error is unresolved -> settle-guard should force another turn!
		tsSession.piAi.fauxAssistantMessage("All done."),
		// Next turn receives settle-guard nudge; fix the type error.
		(context: { messages: Array<{ role?: string; content?: unknown }> }) => {
			const serialized = JSON.stringify(context.messages);
			if (/LSP error|unresolved/i.test(serialized)) settlePromptsSeen++;
			return tsSession.piAi.fauxAssistantMessage(
				tsSession.piAi.fauxToolCall("patch", {
					patch: [
						"*** Begin Patch",
						"*** Update File: calc.ts",
						"@@",
						'-export function add(a: number, b: number): number { return "wrong"; }',
						"+export function add(a: number, b: number): number { return a + b; }",
						"*** End Patch",
					].join("\n"),
				}),
			);
		},
		tsSession.piAi.fauxAssistantMessage("Fixed and verified."),
	]);

	await tsSession.session.prompt("Edit calc.ts");

	const patches = tsSession.toolResults.filter((r) => r.toolName === "patch");
	assert.equal(patches.length, 2);
	assert.match(patches[0]!.text, /\[LSP Diagnostics\]/i);
	assert.equal(settlePromptsSeen, 1, "expected lsp settle-guard to intercept premature completion");
	assert.equal(tsSession.faux.state.callCount, 5);
});

test("integration 5: prompt-cache prefix stays byte-for-byte immutable across multi-turn warm session", async (t) => {
	if (!PI_SCOPE_DIR) return t.skip("Pi installation not found");
	const dir = await mkdtemp(join(tmpdir(), "pi-int-cache-"));
	t.after(() => rm(dir, { recursive: true, force: true }));
	await writeFile(join(dir, "a.txt"), "hello world\n", "utf8");
	await writeFile(join(dir, "b.txt"), "second file\n", "utf8");

	const { session, faux, piAi, cleanup } = await createScriptedSession({
		cwd: dir,
		extensions: [HARNESS_EXT, LSP_EXT, EXPLORE_EXT],
	});
	t.after(cleanup);

	const snapshots: string[][] = [];
	const recordAndReply = (reply: unknown) => (context: { messages: unknown[] }) => {
		snapshots.push(context.messages.map((m) => JSON.stringify(m)));
		return reply;
	};

	faux.setResponses([
		recordAndReply(piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "a.txt" }))),
		recordAndReply(piAi.fauxAssistantMessage(piAi.fauxToolCall("read", { path: "b.txt" }))),
		recordAndReply(piAi.fauxAssistantMessage(piAi.fauxToolCall("bash", { command: "echo ok" }))),
		recordAndReply(piAi.fauxAssistantMessage("All steps complete.")),
	]);

	await session.prompt("Inspect a.txt, b.txt, and run echo ok.");

	assert.equal(snapshots.length, 4, "expected 4 LLM calls");
	for (let turn = 1; turn < snapshots.length; turn++) {
		const prev = snapshots[turn - 1]!;
		const curr = snapshots[turn]!;
		assert.ok(curr.length > prev.length, `turn ${turn} should strictly extend prior messages`);
		for (let i = 0; i < prev.length; i++) {
			assert.equal(
				curr[i],
				prev[i],
				`prompt-cache prefix mutated at turn ${turn}, message index ${i}`,
			);
		}
	}
});
