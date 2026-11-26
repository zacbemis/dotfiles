import { strict as assert } from "node:assert";
import { execFileSync, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { Mailbox } from "../.pi/agent/extensions/remote-thread/mailbox.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DOTFILES_ROOT = resolve(HERE, "..");
const EXT_DIR = join(DOTFILES_ROOT, ".pi/agent/extensions");
const TUNED_EXTENSIONS = [
	join(EXT_DIR, "harness-tuning/index.ts"),
	join(EXT_DIR, "lsp-diagnostics/index.ts"),
	join(EXT_DIR, "explore/index.ts"),
	join(EXT_DIR, "remote-thread/index.ts"),
];

const MODEL = process.env.PI_VERIFY_MODEL ?? "openai-codex/gpt-6-luna";
const THINKING = process.env.PI_VERIFY_THINKING ?? "low";
const BENCH_TRIALS = Math.max(1, Number.parseInt(process.env.PI_VERIFY_TRIALS ?? "3", 10) || 3);
const MASON_TSC = join(
	homedir(),
	".local/share/nvim/mason/packages/typescript-language-server/node_modules/.bin/tsc",
);

function resolvePiCodingAgentEntry(): string {
	const installRoot = join(homedir(), ".pi/agent/install");
	const versionFile = join(installRoot, "current-version");
	if (existsSync(versionFile)) {
		const ver = readFileSync(versionFile, "utf8").trim();
		const candidate = join(installRoot, "releases", ver, "node_modules/@earendil-works/pi-coding-agent/dist/index.js");
		if (existsSync(candidate)) return candidate;
	}
	const releasesDir = join(installRoot, "releases");
	if (existsSync(releasesDir)) {
		for (const ver of readdirSync(releasesDir).sort().reverse()) {
			const candidate = join(releasesDir, ver, "node_modules/@earendil-works/pi-coding-agent/dist/index.js");
			if (existsSync(candidate)) return candidate;
		}
	}
	throw new Error("Unable to locate installed @earendil-works/pi-coding-agent under ~/.pi/agent/install");
}

interface ToolRecord {
	readonly id: string;
	readonly name: string;
	readonly args: Record<string, unknown>;
	resultText: string;
	isError: boolean;
	durationMs: number;
}

interface UsageTotals {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	reasoning: number;
	totalTokens: number;
	cost: number;
}

interface PiRunResult {
	readonly mode: "base" | "tuned";
	readonly exitCode: number;
	readonly wallMs: number;
	readonly turns: number;
	readonly toolCalls: readonly ToolRecord[];
	readonly usage: UsageTotals;
	readonly finalText: string;
	readonly stderr: string;
}

interface BenchTrialResult extends PiRunResult {
	readonly passed: boolean;
	readonly note: string;
	readonly cacheHitRate: number;
}

interface BenchModeSummary {
	readonly trials: readonly BenchTrialResult[];
	readonly passedCount: number;
	readonly passAt1: number;
	readonly passAll: boolean;
	readonly medianTurns: number;
	readonly medianTools: number;
	readonly medianTokens: number;
	readonly medianCost: number;
	readonly medianWallMs: number;
	readonly medianCacheHit: number;
}

interface BenchRow {
	readonly task: string;
	readonly base: BenchModeSummary;
	readonly tuned: BenchModeSummary;
}

const benchRows: BenchRow[] = [];

function median(values: readonly number[]): number {
	if (values.length === 0) return 0;
	const sorted = [...values].sort((a, b) => a - b);
	const mid = Math.floor(sorted.length / 2);
	return sorted.length % 2 === 0 ? (sorted[mid - 1]! + sorted[mid]!) / 2 : sorted[mid]!;
}

function computeCacheHitRate(usage: UsageTotals): number {
	const totalPrompt = usage.input + usage.cacheRead;
	return totalPrompt > 0 ? usage.cacheRead / totalPrompt : 0;
}

function summarizeTrials(trials: readonly BenchTrialResult[]): BenchModeSummary {
	const passedCount = trials.filter((t) => t.passed).length;
	return {
		trials,
		passedCount,
		passAt1: trials.length > 0 ? passedCount / trials.length : 0,
		passAll: trials.length > 0 && passedCount === trials.length,
		medianTurns: median(trials.map((t) => t.turns)),
		medianTools: median(trials.map((t) => t.toolCalls.length)),
		medianTokens: median(trials.map((t) => t.usage.totalTokens)),
		medianCost: median(trials.map((t) => t.usage.cost)),
		medianWallMs: median(trials.map((t) => t.wallMs)),
		medianCacheHit: median(trials.map((t) => t.cacheHitRate)),
	};
}

async function runBenchmarkTrials(options: {
	readonly prefix: string;
	readonly prompt: string;
	readonly setupRepo: (dir: string) => Promise<void>;
	readonly verifyRepo: (dir: string) => Promise<{ passed: boolean; note: string }> | { passed: boolean; note: string };
}): Promise<{ base: BenchModeSummary; tuned: BenchModeSummary }> {
	const trialIndices = Array.from({ length: BENCH_TRIALS }, (_, i) => i);
	const pairs = await Promise.all(
		trialIndices.map(async (idx) => {
			const baseDir = await mkdtemp(join(tmpdir(), `${options.prefix}-base-${idx}-`));
			const tunedDir = await mkdtemp(join(tmpdir(), `${options.prefix}-tuned-${idx}-`));
			try {
				await Promise.all([options.setupRepo(baseDir), options.setupRepo(tunedDir)]);
				const [baseRun, tunedRun] = await Promise.all([
					runPi({ mode: "base", cwd: baseDir, prompt: options.prompt }),
					runPi({ mode: "tuned", cwd: tunedDir, prompt: options.prompt }),
				]);
				const [baseCheck, tunedCheck] = await Promise.all([
					options.verifyRepo(baseDir),
					options.verifyRepo(tunedDir),
				]);
				const baseTrial: BenchTrialResult = {
					...baseRun,
					...baseCheck,
					cacheHitRate: computeCacheHitRate(baseRun.usage),
				};
				const tunedTrial: BenchTrialResult = {
					...tunedRun,
					...tunedCheck,
					cacheHitRate: computeCacheHitRate(tunedRun.usage),
				};
				return { baseTrial, tunedTrial };
			} finally {
				await Promise.all([
					rm(baseDir, { recursive: true, force: true }),
					rm(tunedDir, { recursive: true, force: true }),
				]);
			}
		}),
	);

	return {
		base: summarizeTrials(pairs.map((p) => p.baseTrial)),
		tuned: summarizeTrials(pairs.map((p) => p.tunedTrial)),
	};
}

function runCmd(cmd: string, args: string[], cwd: string): { ok: boolean; stdout: string; stderr: string } {
	try {
		const stdout = execFileSync(cmd, args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
		return { ok: true, stdout, stderr: "" };
	} catch (error) {
		const err = error as { stdout?: string; stderr?: string; message?: string };
		return {
			ok: false,
			stdout: String(err.stdout ?? ""),
			stderr: String(err.stderr ?? err.message ?? ""),
		};
	}
}

function initGitRepo(cwd: string): void {
	runCmd("git", ["init", "-q"], cwd);
	runCmd("git", ["config", "user.name", "Test User"], cwd);
	runCmd("git", ["config", "user.email", "test@example.com"], cwd);
	runCmd("git", ["add", "-A"], cwd);
	runCmd("git", ["commit", "-q", "-m", "chore: initial fixture"], cwd);
}

async function runPi(options: {
	readonly mode: "base" | "tuned";
	readonly cwd: string;
	readonly prompt: string;
	readonly timeoutMs?: number;
	readonly env?: Record<string, string>;
}): Promise<PiRunResult> {
	const args = [
		"--model",
		MODEL,
		"--thinking",
		THINKING,
		"--no-session",
		"--no-mcp",
		"--no-skills",
		"--no-prompt-templates",
		"--no-themes",
		"--no-extensions",
		"--mode",
		"json",
	];
	if (options.mode === "base") {
		args.push("--no-context-files");
	} else {
		for (const ext of TUNED_EXTENSIONS) {
			args.push("-e", ext);
		}
	}
	args.push("-p", options.prompt);

	const startedAt = Date.now();
	const timeoutMs = options.timeoutMs ?? 120_000;

	return await new Promise<PiRunResult>((resolvePromise, reject) => {
		const child = spawn("pi", args, {
			cwd: options.cwd,
			env: { ...process.env, ...(options.env ?? {}) },
			stdio: ["ignore", "pipe", "pipe"],
		});

		let stdout = "";
		let stderr = "";
		let timedOut = false;

		const timer = setTimeout(() => {
			timedOut = true;
			child.kill("SIGTERM");
			setTimeout(() => child.kill("SIGKILL"), 3_000).unref();
		}, timeoutMs);
		timer.unref();

		child.stdout.on("data", (chunk: Buffer) => {
			stdout += chunk.toString("utf8");
		});
		child.stderr.on("data", (chunk: Buffer) => {
			stderr += chunk.toString("utf8");
		});
		child.on("error", (err) => {
			clearTimeout(timer);
			reject(err);
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			const wallMs = Date.now() - startedAt;
			const usage: UsageTotals = {
				input: 0,
				output: 0,
				cacheRead: 0,
				cacheWrite: 0,
				reasoning: 0,
				totalTokens: 0,
				cost: 0,
			};
			const byId = new Map<string, ToolRecord>();
			const toolCalls: ToolRecord[] = [];
			let turns = 0;
			let finalText = "";

			for (const rawLine of stdout.split("\n")) {
				const line = rawLine.trim();
				if (!line.startsWith("{")) continue;
				let ev: Record<string, unknown>;
				try {
					ev = JSON.parse(line) as Record<string, unknown>;
				} catch {
					continue;
				}
				if (ev.type === "tool_execution_start") {
					const rec: ToolRecord = {
						id: String(ev.toolCallId ?? ""),
						name: String(ev.toolName ?? ""),
						args: (ev.args as Record<string, unknown>) ?? {},
						resultText: "",
						isError: false,
						durationMs: 0,
					};
					byId.set(rec.id, rec);
					toolCalls.push(rec);
				} else if (ev.type === "tool_execution_end") {
					const id = String(ev.toolCallId ?? "");
					const rec = byId.get(id);
					const content = (ev.result as { content?: Array<{ type?: string; text?: string }> } | undefined)?.content;
					const text = Array.isArray(content)
						? content.filter((b) => b.type === "text" && typeof b.text === "string").map((b) => b.text).join("\n")
						: "";
					if (rec) {
						rec.resultText = text;
						rec.isError = Boolean(ev.isError);
						rec.durationMs = Number(ev.durationMs ?? 0);
					} else {
						toolCalls.push({
							id,
							name: String(ev.toolName ?? ""),
							args: {},
							resultText: text,
							isError: Boolean(ev.isError),
							durationMs: Number(ev.durationMs ?? 0),
						});
					}
				} else if (ev.type === "message_end") {
					const msg = ev.message as {
						role?: string;
						content?: Array<{ type?: string; text?: string }>;
						usage?: {
							input?: number;
							output?: number;
							cacheRead?: number;
							cacheWrite?: number;
							reasoning?: number;
							totalTokens?: number;
							cost?: { total?: number };
						};
					};
					if (msg?.role === "assistant") {
						turns++;
						if (msg.usage) {
							usage.input += msg.usage.input ?? 0;
							usage.output += msg.usage.output ?? 0;
							usage.cacheRead += msg.usage.cacheRead ?? 0;
							usage.cacheWrite += msg.usage.cacheWrite ?? 0;
							usage.reasoning += msg.usage.reasoning ?? 0;
							usage.totalTokens += msg.usage.totalTokens ?? 0;
							usage.cost += msg.usage.cost?.total ?? 0;
						}
						if (Array.isArray(msg.content)) {
							const text = msg.content
								.filter((b) => b.type === "text" && typeof b.text === "string")
								.map((b) => b.text)
								.join("\n")
								.trim();
							if (text) finalText = text;
						}
					}
				}
			}

			if (timedOut) {
				stderr = `${stderr}\n[verify_pi_harness] Timed out after ${timeoutMs}ms`.trim();
			}
			resolvePromise({
				mode: options.mode,
				exitCode: timedOut ? 124 : (code ?? 1),
				wallMs,
				turns,
				toolCalls,
				usage,
				finalText,
				stderr,
			});
		});
	});
}

// ============================================================================
// Part 1: Live Functional Tests (verifying every harness change end-to-end)
// ============================================================================

test("functional 1: patch routing, lsp navigation, lsp-diagnostics, and settle-guard work end-to-end", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-lsp-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await mkdir(join(dir, "src"), { recursive: true });
	await writeFile(
		join(dir, "tsconfig.json"),
		JSON.stringify(
			{
				compilerOptions: {
					target: "ES2022",
					module: "NodeNext",
					moduleResolution: "NodeNext",
					strict: true,
					noEmit: true,
				},
				include: ["src/**/*.ts"],
			},
			null,
			2,
		),
	);
	await writeFile(
		join(dir, "src/types.ts"),
		`export interface Account {\n\tid: string;\n\tbalance: number;\n}\n`,
	);
	await writeFile(
		join(dir, "src/ledger.ts"),
		`import type { Account } from "./types.js";\n\nexport function deposit(account: Account, amount: number): Account {\n\treturn { ...account, balance: account.balance + amount };\n}\n\nexport function formatBalance(account: Account): string {\n\treturn \`\${account.id}:\${account.balance}\`;\n}\n`,
	);
	await writeFile(
		join(dir, "src/index.ts"),
		`import { deposit, formatBalance } from "./ledger.js";\n\nconst a = deposit({ id: "a1", balance: 10 }, 5);\nconsole.log(formatBalance(a));\n`,
	);
	initGitRepo(dir);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'First use the `lsp` tool to find references to `balance` in `src/types.ts` (line 3, column 2). Then rename `Account.balance` to `Account.balanceCents` across all TypeScript files in `src/`. Do not run bash unless needed.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	assert.ok(
		run.toolCalls.some((c) => c.name === "lsp" && !c.isError),
		`expected successful lsp tool call, got: ${run.toolCalls.map((c) => `${c.name}(err=${c.isError})`).join(", ")}`,
	);
	assert.ok(
		run.toolCalls.some((c) => c.name === "patch" && !c.isError),
		`expected patch tool routing on GPT-6, got: ${run.toolCalls.map((c) => c.name).join(", ")}`,
	);
	assert.equal(
		run.toolCalls.some((c) => c.name === "edit"),
		false,
		"edit tool should be routed to patch on GPT-6",
	);

	if (existsSync(MASON_TSC)) {
		const check = runCmd(MASON_TSC, ["--noEmit"], dir);
		assert.equal(check.ok, true, `tsc --noEmit failed:\n${check.stdout}\n${check.stderr}`);
	}
	const typesText = await readFile(join(dir, "src/types.ts"), "utf8");
	const indexText = await readFile(join(dir, "src/index.ts"), "utf8");
	assert.match(typesText, /balanceCents/);
	assert.match(indexText, /balanceCents/);
});

test("functional 2: lsp-diagnostics injects live TS errors on edit and settle-guard prevents settling with broken types", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-settle-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await mkdir(join(dir, "src"), { recursive: true });
	await writeFile(
		join(dir, "tsconfig.json"),
		JSON.stringify(
			{
				compilerOptions: {
					target: "ES2022",
					module: "NodeNext",
					moduleResolution: "NodeNext",
					strict: true,
					noEmit: true,
				},
				include: ["src/**/*.ts"],
			},
			null,
			2,
		),
	);
	await writeFile(
		join(dir, "src/calc.ts"),
		`export function add(a: number, b: number): number {\n\treturn a + b;\n}\n`,
	);
	initGitRepo(dir);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'Step 1: Using `patch`, change `src/calc.ts` so `add` returns `"broken"` instead of `a + b` (keep return type `number`). Step 2: Inspect the diagnostic returned by the tool and fix `src/calc.ts` so it returns `a + b + 1` with zero TypeScript errors. Do not run bash.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const patchCalls = run.toolCalls.filter((c) => c.name === "patch");
	assert.ok(patchCalls.length >= 2, `expected at least 2 patch calls, got ${patchCalls.length}`);
	assert.ok(
		patchCalls.some((c) => /LSP Diagnostics/i.test(c.resultText) && c.resultText.includes("not assignable")),
		`expected LSP diagnostics in patch output, got:\n${patchCalls.map((c) => c.resultText).join("\n---\n")}`,
	);
	if (existsSync(MASON_TSC)) {
		const check = runCmd(MASON_TSC, ["--noEmit"], dir);
		assert.equal(check.ok, true, `tsc --noEmit failed:\n${check.stdout}\n${check.stderr}`);
	}
	assert.match(await readFile(join(dir, "src/calc.ts"), "utf8"), /a \+ b \+ 1/);
});

test("functional 3: read-dedup stubs unchanged duplicate reads and invalidates after edit", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-dedup-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	const padding = Array.from({ length: 60 }, (_, i) => `export const ITEM_${i} = ${i};`).join("\n");
	await writeFile(join(dir, "big.ts"), `${padding}\nexport const TARGET_VALUE = "BEFORE_EDIT";\n`);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'Execute these 4 tool calls in exact order across turns: (1) call `read` on `big.ts`; (2) call `read` on `big.ts` again without modifying it; (3) use `patch` to change `"BEFORE_EDIT"` to `"AFTER_EDIT"` in `big.ts`; (4) call `read` on `big.ts` one more time and reply with the value of `TARGET_VALUE`.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const reads = run.toolCalls.filter((c) => c.name === "read" && !c.isError);
	assert.ok(reads.length >= 3, `expected >=3 read calls, got ${reads.length}`);
	assert.ok(reads[0]!.resultText.includes("BEFORE_EDIT"), "first read should return full file");
	assert.ok(
		reads.some((r) => r.resultText.includes("[Unchanged since earlier read")),
		`expected dedup stub on duplicate read, got:\n${reads.map((r, i) => `#${i}: ${r.resultText.slice(0, 140)}`).join("\n")}`,
	);
	const lastRead = reads[reads.length - 1]!;
	assert.ok(
		lastRead.resultText.includes("AFTER_EDIT") && !lastRead.resultText.includes("[Unchanged since earlier read"),
		`final read after edit should return fresh content, got: ${lastRead.resultText.slice(0, 160)}`,
	);
	assert.match(run.finalText, /AFTER_EDIT/);
});

test("functional 4: bash-hygiene strips ANSI, collapses spinners/repeats, and slices huge output head+tail", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-bash-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(
		join(dir, "noisy.mjs"),
		`
console.log("\\x1b[31mTOP_MARKER: ERR_ALPHA_42\\x1b[0m");
for (let i = 0; i < 40; i++) console.log("WARN: noisy repeated line");
console.log("Loading 10%\\rLoading 50%\\rLoading 100%\\rSpinnerDone");
for (let i = 0; i < 900; i++) console.log("filler line " + i + " " + "x".repeat(60));
console.log("\\x1b[33mBOTTOM_MARKER: ROOT_OMEGA_99\\x1b[0m");
process.exitCode = 1;
`,
	);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			"Run the exact bash command `node noisy.mjs` (with no piping, redirection, or filtering) and report the exact TOP_MARKER and BOTTOM_MARKER codes.",
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const bashCall = run.toolCalls.find((c) => c.name === "bash");
	assert.ok(bashCall, "expected a bash tool call");
	assert.equal(bashCall.resultText.includes("\x1b["), false, "ANSI codes should be stripped");
	assert.ok(bashCall.resultText.includes("repeated"), "repeated lines should be collapsed");
	assert.ok(bashCall.resultText.includes("ERR_ALPHA_42"), "top marker should survive head+tail slicing");
	assert.ok(bashCall.resultText.includes("ROOT_OMEGA_99"), "bottom marker should survive head+tail slicing");
	assert.match(run.finalText, /ERR_ALPHA_42/);
	assert.match(run.finalText, /ROOT_OMEGA_99/);
});

test("functional 5: commit attribution guard blocks AI trailers and global AGENTS.md shapes clean Conventional Commits", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-commit-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(join(dir, "notes.txt"), "v1\n");
	initGitRepo(dir);
	await writeFile(join(dir, "notes.txt"), "v2\n");
	runCmd("git", ["add", "notes.txt"], dir);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'First, try running exactly `git commit -m "chore(notes): update notes\n\nCo-Authored-By: Claude Opus <noreply@anthropic.com>"` via bash to test whether the harness blocks it. When blocked, commit the staged change properly following our commit rules.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const blocked = run.toolCalls.find(
		(c) => c.name === "bash" && c.isError && c.resultText.includes("Remove AI/Claude attribution"),
	);
	assert.ok(
		blocked,
		`expected attribution guard block, got bash calls:\n${run.toolCalls
			.filter((c) => c.name === "bash")
			.map((c) => `err=${c.isError} ${c.resultText.slice(0, 140)}`)
			.join("\n")}`,
	);
	const log = runCmd("git", ["log", "-1", "--format=%B"], dir);
	assert.equal(log.ok, true);
	assert.match(log.stdout.trim(), /^(feat|fix|chore|docs|refactor|style|test)(\([^)]+\))?: /);
	assert.doesNotMatch(log.stdout, /co-authored-by|claude|generated with/i);
});

test("functional 6: file-freshness guard blocks patching an externally modified file until re-read", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-fresh-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(join(dir, "config.ts"), `export const MODE = "v1";\n`);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'Do these steps in order: (1) `read` `config.ts`; (2) run `bash` `node -e "require(\'fs\').writeFileSync(\'config.ts\', \'export const MODE = \\"v2\\";\\n\')"` to simulate an external edit; (3) immediately try to `patch` `config.ts` without re-reading first; (4) when blocked for staleness, re-read `config.ts` and `patch` `"v2"` to `"v3"`.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const staleBlock = run.toolCalls.find(
		(c) => c.name === "patch" && c.isError && /modified externally|re-read/i.test(c.resultText),
	);
	assert.ok(
		staleBlock,
		`expected file-freshness block on stale patch, got patch calls:\n${run.toolCalls
			.filter((c) => c.name === "patch")
			.map((c) => `err=${c.isError} ${c.resultText.slice(0, 180)}`)
			.join("\n")}`,
	);
	assert.match(await readFile(join(dir, "config.ts"), "utf8"), /"v3"/);
});

test("functional 7: standalone explore subagent traces multi-file constant without polluting main reads", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-explore-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await mkdir(join(dir, "src/config"), { recursive: true });
	await mkdir(join(dir, "src/network"), { recursive: true });
	await mkdir(join(dir, "src/jobs"), { recursive: true });
	await mkdir(join(dir, "src/misc"), { recursive: true });

	await writeFile(join(dir, "src/config/defaults.ts"), `export const BASE_RETRY_MS = 750;\n`);
	await writeFile(
		join(dir, "src/network/policy.ts"),
		`import { BASE_RETRY_MS } from "../config/defaults.js";\nexport const RETRY_BUDGET_MS = BASE_RETRY_MS * 4;\n`,
	);
	await writeFile(
		join(dir, "src/jobs/worker.ts"),
		`import { RETRY_BUDGET_MS } from "../network/policy.js";\nexport function getWorkerTimeout() { return RETRY_BUDGET_MS + 200; }\n`,
	);
	for (let i = 0; i < 8; i++) {
		await writeFile(join(dir, `src/misc/mod${i}.ts`), `export const MOD_${i} = ${i};\n`);
	}

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			"Use the `explore` tool to trace how `getWorkerTimeout()` computes its value (files, constants, and final numeric result), and report the answer.",
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const exploreCall = run.toolCalls.find((c) => c.name === "explore" && !c.isError);
	assert.ok(exploreCall, "expected a successful explore tool call");
	const mainReads = run.toolCalls.filter((c) => c.name === "read");
	assert.equal(mainReads.length, 0, `expected 0 direct main-thread reads, got ${mainReads.length}`);
	assert.match(run.finalText, /3,?200/);
});

test("functional 8: post-edit-diagnostics catches broken JSON immediately on patch", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-diag-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(join(dir, "data.json"), `{\n  "ok": true\n}\n`);

	const run = await runPi({
		mode: "tuned",
		cwd: dir,
		prompt:
			'Step 1: Use `patch` to change `"ok": true` to `"ok": true,` (adding a trailing comma) in `data.json`. Step 2: Observe the post-edit diagnostic and fix `data.json` so it is valid JSON with `"ok": false`. Do not run bash.',
	});

	assert.equal(run.exitCode, 0, run.stderr);
	const patchCalls = run.toolCalls.filter((c) => c.name === "patch");
	assert.ok(
		patchCalls.some((c) => /diagnostics|json|syntax/i.test(c.resultText)),
		`expected JSON diagnostic in patch output, got:\n${patchCalls.map((c) => c.resultText).join("\n---\n")}`,
	);
	const parsed = JSON.parse(await readFile(join(dir, "data.json"), "utf8")) as { ok: boolean };
	assert.equal(parsed.ok, false);
});

test("functional 9: remote-thread live session loads trimmed schema and overrides cache_warming_decision when awaiting peer", async (t) => {
	const mailDir = await mkdtemp(join(tmpdir(), "pi-verify-rt-mail-"));
	const sessDir = await mkdtemp(join(tmpdir(), "pi-verify-rt-sess-"));
	t.after(() => rm(mailDir, { recursive: true, force: true }));
	t.after(() => rm(sessDir, { recursive: true, force: true }));

	const prevMailDir = process.env.PI_THREAD_MAILBOX_DIR;
	process.env.PI_THREAD_MAILBOX_DIR = mailDir;
	t.after(() => {
		if (prevMailDir === undefined) delete process.env.PI_THREAD_MAILBOX_DIR;
		else process.env.PI_THREAD_MAILBOX_DIR = prevMailDir;
	});

	const piPkg = await import(resolvePiCodingAgentEntry());
	const sessionManager = piPkg.SessionManager.create(DOTFILES_ROOT, sessDir);
	const { session, extensionsResult } = await piPkg.createAgentSession({
		cwd: DOTFILES_ROOT,
		sessionManager,
	});

	const errors = [...extensionsResult.errors];
	await session.bindExtensions({ mode: "rpc", onError: (e: unknown) => errors.push(e) });
	assert.equal(errors.length, 0, `extension errors: ${JSON.stringify(errors)}`);

	const runner = (session as unknown as {
		_extensionRunner: {
			emit: (ev: { type: "session_shutdown"; reason: "quit" }) => Promise<void>;
			emitCacheWarmingDecision: (ev: {
				type: "cache_warming_decision";
				warmCost: number;
				missCost: number;
				continuationProbability: number;
				action: "warm" | "stop";
			}) => Promise<"warm" | "stop">;
		};
	})._extensionRunner;
	t.after(async () => {
		await runner.emit({ type: "session_shutdown", reason: "quit" });
		session.dispose();
	});

	const rtTool = session.getAllTools().find((tool: { name: string }) => tool.name === "remote_thread");
	assert.ok(rtTool, "remote_thread tool should be registered");
	assert.ok(
		JSON.stringify(rtTool.parameters).length < 1_300,
		`expected trimmed remote_thread schema, got ${JSON.stringify(rtTool.parameters).length} chars`,
	);

	const idleDecisionEvent = {
		type: "cache_warming_decision" as const,
		warmCost: 0.004,
		missCost: 0.12,
		continuationProbability: 0.15,
		action: "stop" as const,
	};

	// No active outgoing handoff -> stays "stop".
	assert.equal(await runner.emitCacheWarmingDecision(idleDecisionEvent), "stop");

	// Enqueue + accept a working handoff for this exact session -> overrides to "warm".
	const store = new Mailbox(mailDir);
	t.after(() => store.close());
	const sessionId = sessionManager.getSessionId();
	const handoffId = randomUUID();
	const target = store.rememberTarget("local", { session: randomUUID(), title: "peer-worker" }, randomUUID());
	store.enqueue(sessionId, handoffId, target, "run tests", null, null);
	// Pending (unaccepted) -> still "stop".
	assert.equal(await runner.emitCacheWarmingDecision(idleDecisionEvent), "stop");
	// Accepted / working -> overrides to "warm".
	store.updateOutgoing(sessionId, handoffId, "pending", "working", null, Date.now());
	assert.equal(await runner.emitCacheWarmingDecision(idleDecisionEvent), "warm");
	// Too small to save $0.05 -> stays "stop".
	assert.equal(
		await runner.emitCacheWarmingDecision({ ...idleDecisionEvent, warmCost: 0.01, missCost: 0.03 }),
		"stop",
	);
	// Completed -> back to "stop".
	store.updateOutgoing(sessionId, handoffId, "working", "completed", "ok", Date.now());
	assert.equal(await runner.emitCacheWarmingDecision(idleDecisionEvent), "stop");
});

test("functional 10: live warm-prefix compaction with gpt-6-luna produces workspace-state and tracks patch ops", async (t) => {
	const dir = await mkdtemp(join(tmpdir(), "pi-verify-compact-"));
	t.after(() => rm(dir, { recursive: true, force: true }));

	await writeFile(join(dir, "app.ts"), `export const VERSION = 1;\n`);
	initGitRepo(dir);

	const piPkg = await import(resolvePiCodingAgentEntry());
	const sessionManager = piPkg.SessionManager.inMemory(dir);
	const settingsManager = piPkg.SettingsManager.inMemory({
		compaction: { enabled: true, keepRecentTokens: 100, reserveTokens: 1024 },
	});
	const { session, extensionsResult } = await piPkg.createAgentSession({
		cwd: dir,
		sessionManager,
		settingsManager,
	});
	const errors = [...extensionsResult.errors];
	await session.bindExtensions({ onError: (e: unknown) => errors.push(e) });
	assert.equal(errors.length, 0);
	const runner = (session as unknown as {
		_extensionRunner: { emit: (ev: { type: "session_shutdown"; reason: "quit" }) => Promise<void> };
	})._extensionRunner;
	t.after(async () => {
		await runner.emit({ type: "session_shutdown", reason: "quit" });
		session.dispose();
	});

	const [provider, modelId] = MODEL.split("/");
	const targetModel = session.modelRuntime.getModel(provider, modelId);
	assert.ok(targetModel, `model ${MODEL} not found`);
	await session.setModel(targetModel);
	session.setThinkingLevel(THINKING as "low");

	await session.prompt('Read `app.ts` and use `patch` to change `VERSION = 1` to `VERSION = 2`.');
	await session.prompt('Now use `patch` to change `VERSION = 2` to `VERSION = 3` and reply "DONE".');

	const compaction = await session.compact("Keep track of VERSION changes.");
	assert.ok(compaction.summary.length > 40, "compaction summary should be non-empty");
	assert.ok(
		compaction.summary.includes("<workspace-state>"),
		`expected <workspace-state> section from warm compaction, got:\n${compaction.summary}`,
	);
	assert.match(compaction.summary, /app\.ts/);
});

// ============================================================================
// Part 2: A/B Benchmarks — Base Pi vs Tuned Pi (same model, same prompts)
// ============================================================================

async function setupBenchARepo(dir: string): Promise<void> {
	await mkdir(join(dir, "src"), { recursive: true });
	await writeFile(
		join(dir, "tsconfig.json"),
		JSON.stringify(
			{
				compilerOptions: {
					target: "ES2022",
					module: "NodeNext",
					moduleResolution: "NodeNext",
					allowImportingTsExtensions: true,
					strict: true,
					noEmit: true,
				},
				include: ["src/**/*.ts"],
			},
			null,
			2,
		),
	);
	await writeFile(
		join(dir, "src/models.ts"),
		`export interface LineItem {\n\tsku: string;\n\tqty: number;\n\tunitPrice: number;\n}\n\nexport interface Invoice {\n\tid: string;\n\titems: LineItem[];\n\ttaxRate: number;\n}\n`,
	);
	await writeFile(
		join(dir, "src/pricing.ts"),
		`import type { Invoice, LineItem } from "./models.ts";\n\nexport function lineTotal(item: LineItem): number {\n\treturn item.qty * item.unitPrice;\n}\n\nexport function subtotal(invoice: Invoice): number {\n\treturn invoice.items.reduce((sum, item) => sum + lineTotal(item), 0);\n}\n\nexport function totalWithTax(invoice: Invoice): number {\n\treturn Math.round(subtotal(invoice) * (1 + invoice.taxRate));\n}\n`,
	);
	await writeFile(
		join(dir, "src/report.ts"),
		`import type { Invoice } from "./models.ts";\nimport { lineTotal, subtotal, totalWithTax } from "./pricing.ts";\n\nexport function renderInvoice(invoice: Invoice): string {\n\tconst rows = invoice.items.map((item) => \`\${item.sku} x\${item.qty} @ \${item.unitPrice} = \${lineTotal(item)}\`);\n\treturn [...rows, \`SUBTOTAL=\${subtotal(invoice)}\`, \`TOTAL=\${totalWithTax(invoice)}\`].join("\\n");\n}\n`,
	);
	await writeFile(
		join(dir, "src/cli.ts"),
		`import { renderInvoice } from "./report.ts";\n\nexport function sampleReport(): string {\n\treturn renderInvoice({\n\t\tid: "inv-1",\n\t\ttaxRate: 0.1,\n\t\titems: [\n\t\t\t{ sku: "WIDGET", qty: 2, unitPrice: 15 },\n\t\t\t{ sku: "GADGET", qty: 1, unitPrice: 20 },\n\t\t],\n\t});\n}\n`,
	);
	await writeFile(
		join(dir, "src/pricing.test.ts"),
		`import { sampleReport } from "./cli.ts";\nimport { totalWithTax } from "./pricing.ts";\n\nconst total = totalWithTax({\n\tid: "t1",\n\ttaxRate: 0.1,\n\titems: [\n\t\t{ sku: "A", qty: 2, unitPrice: 15 },\n\t\t{ sku: "B", qty: 1, unitPrice: 20 },\n\t],\n});\nif (total !== 55) throw new Error(\`expected 55, got \${total}\`);\nif (!/TOTAL=55/.test(sampleReport())) throw new Error(\`unexpected report: \${sampleReport()}\`);\n`,
	);
	initGitRepo(dir);
}

test("benchmark A: Base Pi vs Tuned Pi on multi-file TypeScript contract refactor", async () => {
	const prompt =
		"Refactor `LineItem.unitPrice` (dollars) to `LineItem.unitPriceCents` (integer cents, e.g. $15 -> 1500, $20 -> 2000) across all files in `src/`. Keep `lineTotal`, `subtotal`, and `totalWithTax` returning integer cents, update `src/cli.ts`, `src/report.ts`, and `src/pricing.test.ts`, and make sure `node src/pricing.test.ts` passes with no TypeScript errors.";

	const { base, tuned } = await runBenchmarkTrials({
		prefix: "pi-bench-a",
		prompt,
		setupRepo: setupBenchARepo,
		verifyRepo: async (dir) => {
			// Inject held-out acceptance test after the agent exits to verify unseen contract cases.
			const heldOutPath = join(dir, "src/.heldout.verify.ts");
			await writeFile(
				heldOutPath,
				`import { lineTotal, subtotal, totalWithTax } from "./pricing.ts";
import { renderInvoice } from "./report.ts";
const inv = {
	id: "heldout",
	taxRate: 0.0825,
	items: [
		{ sku: "X", qty: 3, unitPriceCents: 333 },
		{ sku: "Y", qty: 0, unitPriceCents: 500 },
	],
};
if (lineTotal(inv.items[0]!) !== 999) throw new Error("bad lineTotal");
if (subtotal(inv) !== 999) throw new Error("bad subtotal");
if (totalWithTax(inv) !== 1081) throw new Error("bad totalWithTax: " + totalWithTax(inv));
if (!renderInvoice(inv).includes("TOTAL=1081")) throw new Error("bad renderInvoice");
`,
				"utf8",
			);
			const testRes = runCmd("node", ["src/pricing.test.ts"], dir);
			const heldOutRes = runCmd("node", ["src/.heldout.verify.ts"], dir);
			const tscRes = existsSync(MASON_TSC) ? runCmd(MASON_TSC, ["--noEmit"], dir) : { ok: true, stdout: "", stderr: "" };
			const models = await readFile(join(dir, "src/models.ts"), "utf8");
			const pricingTest = await readFile(join(dir, "src/pricing.test.ts"), "utf8");
			const ok =
				testRes.ok &&
				heldOutRes.ok &&
				tscRes.ok &&
				models.includes("unitPriceCents") &&
				!models.includes("unitPrice:") &&
				pricingTest.includes("5500");
			const note = ok
				? "tests+heldout+tsc ok"
				: `test=${testRes.ok} heldout=${heldOutRes.ok} tsc=${tscRes.ok} cents=${pricingTest.includes("5500")}`;
			return { passed: ok, note };
		},
	});

	benchRows.push({ task: "A: TS multi-file refactor", base, tuned });
	assert.equal(
		tuned.passedCount,
		BENCH_TRIALS,
		`Tuned Pi failed Bench A (${tuned.passedCount}/${BENCH_TRIALS}): ${tuned.trials.map((r) => r.note).join("; ")}`,
	);
	if (tuned.medianTurns >= 3) {
		assert.ok(
			tuned.medianCacheHit >= 0.35,
			`Bench A Tuned cache hit rate too low: ${(tuned.medianCacheHit * 100).toFixed(1)}%`,
		);
	}
});

async function setupBenchBRepo(dir: string): Promise<void> {
	await mkdir(join(dir, "src"), { recursive: true });
	await writeFile(
		join(dir, "src/parser.mjs"),
		`export function parsePairs(input) {\n\tconst out = {};\n\tfor (const line of input.split("\\n")) {\n\t\tconst trimmed = line.trim();\n\t\tif (!trimmed || trimmed.startsWith("#")) continue;\n\t\tconst [key, value] = trimmed.split("="); // bug: drops '=' inside value\n\t\tout[key.trim()] = value.trim();\n\t}\n\treturn out;\n}\n`,
	);
	await writeFile(
		join(dir, "src/format.mjs"),
		`export function slugify(text) {\n\treturn text.toLowerCase().replace(/\\s+/g, "-"); // bug: leaves punctuation and edge hyphens\n}\n`,
	);
	await writeFile(
		join(dir, "test.mjs"),
		`import { strict as assert } from "node:assert";\nimport { parsePairs } from "./src/parser.mjs";\nimport { slugify } from "./src/format.mjs";\n\nlet failures = 0;\nfunction check(name, fn) {\n\ttry { fn(); }\n\tcatch (err) { failures++; console.log("\\x1b[31mFAIL " + name + ": " + err.message + "\\x1b[0m"); }\n}\n\ncheck("parsePairs preserves '=' in values", () => {\n\tassert.deepEqual(parsePairs("url=https://a.test?x=1&y=2\\n# comment\\nmode=fast"), {\n\t\turl: "https://a.test?x=1&y=2",\n\t\tmode: "fast",\n\t});\n});\n\nfor (let i = 0; i < 120; i++) console.log("\\x1b[33mWARN: deprecated fixture key legacy_mode\\x1b[0m");\nfor (let i = 0; i < 12; i++) process.stdout.write("Running suite " + i + "/12\\r");\nconsole.log("Suite scan complete");\nfor (let i = 0; i < 750; i++) console.log("\\x1b[32mPASS\\x1b[0m synthetic check #" + i + " " + "ok_".repeat(25));\n\ncheck("slugify strips punctuation and trims hyphens", () => {\n\tassert.equal(slugify("  Hello, World!! 2026  "), "hello-world-2026");\n});\n\nif (failures > 0) { process.exitCode = 1; } else { console.log("ALL TESTS PASSED"); }\n`,
	);
	initGitRepo(dir);
}

test("benchmark B: Base Pi vs Tuned Pi on noisy 65KB log debugging + 2-file fix", async () => {
	const prompt =
		"Run `node test.mjs`, diagnose every failing test, fix the bugs in `src/`, and re-run `node test.mjs` until all tests pass.";

	const { base, tuned } = await runBenchmarkTrials({
		prefix: "pi-bench-b",
		prompt,
		setupRepo: setupBenchBRepo,
		verifyRepo: async (dir) => {
			// Anti-tampering: verify agent did not modify test.mjs, and grade against unseen edge cases.
			const testDiff = runCmd("git", ["diff", "--", "test.mjs"], dir).stdout.trim();
			await writeFile(
				join(dir, ".heldout.verify.mjs"),
				`import { strict as assert } from "node:assert";
import { parsePairs } from "./src/parser.mjs";
import { slugify } from "./src/format.mjs";

assert.deepEqual(parsePairs("token=a=b=c\\n\\n  # comment\\nkey = val=1"), {
	token: "a=b=c",
	key: "val=1",
});
assert.equal(slugify("  --Alpha, Beta... (v2)!! --  "), "alpha-beta-v2");
`,
				"utf8",
			);
			const res = runCmd("node", ["test.mjs"], dir);
			const heldOut = runCmd("node", [".heldout.verify.mjs"], dir);
			const untampered = testDiff === "";
			const passed = res.ok && res.stdout.includes("ALL TESTS PASSED") && heldOut.ok && untampered;
			return {
				passed,
				note: passed
					? "all+heldout pass"
					: `test=${res.ok} heldout=${heldOut.ok} untampered=${untampered}`,
			};
		},
	});

	benchRows.push({ task: "B: Noisy log debug + fix", base, tuned });
	assert.equal(
		tuned.passedCount,
		BENCH_TRIALS,
		`Tuned Pi failed Bench B (${tuned.passedCount}/${BENCH_TRIALS}): ${tuned.trials.map((r) => r.note).join("; ")}`,
	);
	if (tuned.medianTurns >= 3) {
		assert.ok(
			tuned.medianCacheHit >= 0.35,
			`Bench B Tuned cache hit rate too low: ${(tuned.medianCacheHit * 100).toFixed(1)}%`,
		);
	}
});

async function setupBenchCRepo(dir: string): Promise<void> {
	for (const sub of ["auth", "billing", "cache", "config", "http", "logging", "metrics", "queue", "storage"]) {
		await mkdir(join(dir, "src", sub), { recursive: true });
	}
	await writeFile(join(dir, "src/config/ttl.mjs"), `// TTL configured in seconds (5 minutes)\nexport const QUOTE_TTL_SECONDS = 300;\n`);
	await writeFile(
		join(dir, "src/cache/memory.mjs"),
		`export class MemoryCache {\n\t#entries = new Map();\n\tset(key, value, ttlMs, now = Date.now()) {\n\t\tthis.#entries.set(key, { value, expiresAt: now + ttlMs });\n\t}\n\tget(key, now = Date.now()) {\n\t\tconst item = this.#entries.get(key);\n\t\tif (!item || now >= item.expiresAt) return undefined;\n\t\treturn item.value;\n\t}\n}\n`,
	);
	await writeFile(
		join(dir, "src/billing/quotes.mjs"),
		`import { MemoryCache } from "../cache/memory.mjs";\nimport { QUOTE_TTL_SECONDS } from "../config/ttl.mjs";\n\nexport function createQuoteService(computeQuote) {\n\tconst cache = new MemoryCache();\n\treturn {\n\t\tgetQuote(id, now) {\n\t\t\tconst hit = cache.get(id, now);\n\t\t\tif (hit !== undefined) return { value: hit, cached: true };\n\t\t\tconst value = computeQuote(id);\n\t\t\t// Bug: passes seconds directly to a cache expecting milliseconds\n\t\t\tcache.set(id, value, QUOTE_TTL_SECONDS, now);\n\t\t\treturn { value, cached: false };\n\t\t},\n\t};\n}\n`,
	);
	const fillers = [
		"src/auth/tokens.mjs",
		"src/auth/session.mjs",
		"src/http/router.mjs",
		"src/http/middleware.mjs",
		"src/logging/logger.mjs",
		"src/metrics/counter.mjs",
		"src/queue/worker.mjs",
		"src/queue/retry.mjs",
		"src/storage/kv.mjs",
		"src/storage/fs.mjs",
	];
	for (const rel of fillers) {
		await writeFile(join(dir, rel), `export const MODULE = ${JSON.stringify(rel)};\nexport function noop(x) { return x; }\n`);
	}
	await writeFile(
		join(dir, "test.mjs"),
		`import { strict as assert } from "node:assert";\nimport { createQuoteService } from "./src/billing/quotes.mjs";\n\nlet calls = 0;\nconst svc = createQuoteService((id) => ({ id, seq: ++calls }));\nconst t0 = 1_000_000;\nconst first = svc.getQuote("q1", t0);\nassert.equal(first.cached, false);\n// 4 minutes later should still be cached\nconst mid = svc.getQuote("q1", t0 + 4 * 60_000);\nassert.equal(mid.cached, true, "expected cache hit after 4 minutes");\nassert.equal(calls, 1);\n// 5 minutes + 1ms later should expire\nconst expired = svc.getQuote("q1", t0 + 5 * 60_000 + 1);\nassert.equal(expired.cached, false, "expected cache miss after 5 minutes");\nassert.equal(calls, 2);\nconsole.log("QUOTE CACHE OK");\n`,
	);
	initGitRepo(dir);
}

test("benchmark C: Base Pi vs Tuned Pi on multi-module investigation + fix + git commit", async () => {
	const prompt =
		"Investigate why cached quotes expire almost immediately instead of lasting 5 minutes, fix the root cause, verify with `node test.mjs`, and create a git commit for the fix.";

	const { base, tuned } = await runBenchmarkTrials({
		prefix: "pi-bench-c",
		prompt,
		setupRepo: setupBenchCRepo,
		verifyRepo: async (dir) => {
			const status = runCmd("git", ["status", "--porcelain"], dir);
			const log = runCmd("git", ["log", "-1", "--format=%B"], dir);
			const commitCount = Number(runCmd("git", ["rev-list", "--count", "HEAD"], dir).stdout.trim());
			const testUntampered =
				commitCount >= 2 ? runCmd("git", ["diff", "HEAD~1", "HEAD", "--", "test.mjs"], dir).stdout.trim() === "" : false;
			const res = runCmd("node", ["test.mjs"], dir);

			// Inject held-out TTL boundary checks after inspecting git clean status.
			await writeFile(
				join(dir, ".heldout.verify.mjs"),
				`import { strict as assert } from "node:assert";
import { createQuoteService } from "./src/billing/quotes.mjs";

let calls = 0;
const svc = createQuoteService((id) => ({ id, seq: ++calls }));
const t0 = 5_000_000;
assert.equal(svc.getQuote("a", t0).cached, false);
assert.equal(svc.getQuote("b", t0 + 1000).cached, false);
assert.equal(svc.getQuote("a", t0 + 299_999).cached, true);
assert.equal(svc.getQuote("a", t0 + 300_000).cached, false);
assert.equal(svc.getQuote("b", t0 + 300_999).cached, true);
`,
				"utf8",
			);
			const heldOut = runCmd("node", [".heldout.verify.mjs"], dir);
			const conventional = /^(feat|fix|chore|refactor|perf)(\([^)]+\))?: /.test(log.stdout.trim());
			const noAttribution = !/co-authored-by|claude|generated with/i.test(log.stdout);
			const passed =
				res.ok && heldOut.ok && testUntampered && commitCount >= 2 && status.stdout.trim() === "";
			const note = `${passed ? "ok" : "fail"} (conv=${conventional}, cleanAttr=${noAttribution}, heldout=${heldOut.ok})`;
			return { passed, note };
		},
	});

	benchRows.push({ task: "C: Multi-module fix + commit", base, tuned });
	assert.equal(
		tuned.passedCount,
		BENCH_TRIALS,
		`Tuned Pi failed Bench C (${tuned.passedCount}/${BENCH_TRIALS}): ${tuned.trials.map((r) => r.note).join("; ")}`,
	);
	if (tuned.medianTurns >= 3) {
		assert.ok(
			tuned.medianCacheHit >= 0.35,
			`Bench C Tuned cache hit rate too low: ${(tuned.medianCacheHit * 100).toFixed(1)}%`,
		);
	}
});

test("benchmark summary table", () => {
	const fmt = (s: BenchModeSummary) => {
		const k = s.trials.length;
		const passLabel = `${s.passedCount}/${k} (pass^${k}=${s.passAll ? "100%" : "0%"})`;
		const notes = [...new Set(s.trials.map((t) => t.note))].join(" | ");
		return `${passLabel} | med ${s.medianTurns.toFixed(1)}t | ${s.medianTools.toFixed(1)} tools | ${Math.round(s.medianTokens)} tok | cache=${(s.medianCacheHit * 100).toFixed(0)}% | $${s.medianCost.toFixed(5)} | ${(s.medianWallMs / 1000).toFixed(1)}s | ${notes}`;
	};

	console.log(`\n=== A/B Benchmark Summary (${MODEL}, thinking=${THINKING}, k=${BENCH_TRIALS} trials/task) ===`);
	let baseCost = 0;
	let tunedCost = 0;
	let baseWall = 0;
	let tunedWall = 0;
	let baseTokens = 0;
	let tunedTokens = 0;
	let baseTools = 0;
	let tunedTools = 0;
	let basePassed = 0;
	let tunedPassed = 0;
	let totalTrials = 0;

	for (const row of benchRows) {
		console.log(`\n${row.task}`);
		console.log(`  Base : ${fmt(row.base)}`);
		console.log(`  Tuned: ${fmt(row.tuned)}`);
		baseCost += row.base.medianCost;
		tunedCost += row.tuned.medianCost;
		baseWall += row.base.medianWallMs;
		tunedWall += row.tuned.medianWallMs;
		baseTokens += row.base.medianTokens;
		tunedTokens += row.tuned.medianTokens;
		baseTools += row.base.medianTools;
		tunedTools += row.tuned.medianTools;
		basePassed += row.base.passedCount;
		tunedPassed += row.tuned.passedCount;
		totalTrials += row.base.trials.length;
	}
	if (benchRows.length > 0) {
		const pct = (a: number, b: number) => (a === 0 ? "n/a" : `${(((b - a) / a) * 100).toFixed(1)}%`);
		console.log("\nSum of per-task medians across all benchmarks:");
		console.log(`  Pass rate : Base=${basePassed}/${totalTrials}, Tuned=${tunedPassed}/${totalTrials}`);
		console.log(`  Tool calls: Base=${baseTools.toFixed(1)}, Tuned=${tunedTools.toFixed(1)} (${pct(baseTools, tunedTools)})`);
		console.log(`  Tokens    : Base=${Math.round(baseTokens)}, Tuned=${Math.round(tunedTokens)} (${pct(baseTokens, tunedTokens)})`);
		console.log(`  Cost      : Base=$${baseCost.toFixed(5)}, Tuned=$${tunedCost.toFixed(5)} (${pct(baseCost, tunedCost)})`);
		console.log(`  Wall time : Base=${(baseWall / 1000).toFixed(1)}s, Tuned=${(tunedWall / 1000).toFixed(1)}s (${pct(baseWall, tunedWall)})\n`);
	}
});
