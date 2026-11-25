import { spawn } from "node:child_process";
import { stat } from "node:fs/promises";
import { resolve } from "node:path";

export const EXPLORE_TOOL_NAME = "explore";
export const EXPLORE_ENV_FLAG = "PI_EXPLORE_SUBAGENT";
export const EXPLORE_TIMEOUT_MS = 120_000;
export const MAX_EXPLORE_OUTPUT_CHARS = 16_000;

const KILL_GRACE_MS = 3_000;

const EXPLORE_SYSTEM_PROMPT = `You are a fast, read-only codebase exploration subagent.
Answer the caller's question accurately using only read, grep, find, and ls.
- Prefer parallelizing independent find, grep, and read calls.
- Run targeted searches first; read only the relevant slices of files.
- Report exact file paths, symbol names, line numbers, and concise findings.
- Do not speculate about files you did not inspect, and do not suggest edits unless asked.`;

const BUILTIN_PROVIDERS = new Set([
	"openai-codex",
	"openai",
	"anthropic",
	"google",
	"google-vertex",
	"openrouter",
	"amazon-bedrock",
	"azure-openai-responses",
	"github-copilot",
	"xai",
	"groq",
	"deepseek",
	"mistral",
	"kimi-coding",
	"opencode",
]);

export interface ExploreModelCandidate {
	readonly provider: string;
	readonly id: string;
}

export function selectExploreModel(
	current: ExploreModelCandidate | undefined,
	available: readonly ExploreModelCandidate[],
): ExploreModelCandidate | undefined {
	if (!current) return undefined;

	const findModel = (provider: string, predicate: (id: string) => boolean) =>
		available.find((model) => model.provider === provider && predicate(model.id.toLowerCase()));

	const currentId = current.id.toLowerCase();

	if (current.provider === "openai-codex" && currentId.includes("gpt-6.2-sol")) {
		const fast = findModel("openai-codex", (id) => id === "gpt-6.2-astra");
		if (fast) return fast;
	}

	if (currentId.includes("gpt-6") && !/(?:luna|astra|mini|nano)/.test(currentId)) {
		const luna = findModel(current.provider, (id) => id.includes("gpt-6") && id.includes("luna"));
		if (luna) return luna;
		const astra = findModel(current.provider, (id) => id.includes("gpt-6") && id.includes("astra"));
		if (astra) return astra;
	}

	if (currentId.includes("gpt-5") && !/(?:mini|nano)/.test(currentId)) {
		const mini =
			findModel(current.provider, (id) => id === "gpt-5.4-mini") ??
			findModel(current.provider, (id) => id.includes("gpt-5") && id.includes("mini"));
		if (mini) return mini;
	}

	if (currentId.includes("opus")) {
		const sonnet = findModel(current.provider, (id) => id.includes("sonnet"));
		if (sonnet) return sonnet;
		const haiku = findModel(current.provider, (id) => id.includes("haiku"));
		if (haiku) return haiku;
	}

	return current;
}

export function buildExploreArgs(task: string, model: ExploreModelCandidate | undefined): string[] {
	const args = [
		"--mode",
		"json",
		"--no-session",
		"--no-mcp",
		"--no-skills",
		"--no-prompt-templates",
		"--no-themes",
		"--no-context-files",
		"--tools",
		"read,grep,find,ls",
		"--thinking",
		"low",
		"--system-prompt",
		EXPLORE_SYSTEM_PROMPT,
	];

	if (!model || BUILTIN_PROVIDERS.has(model.provider)) {
		args.push("--no-extensions");
	}
	if (model) {
		args.push("--model", `${model.provider}/${model.id}`);
	}

	args.push("-p", "--", task);
	return args;
}

export interface ParsedExploreEvent {
	toolCallName?: string;
	assistantText?: string;
	errorMessage?: string;
}

export function parseExploreJsonLine(line: string): ParsedExploreEvent | undefined {
	const trimmed = line.trim();
	if (!trimmed) return undefined;
	let parsed: Record<string, unknown>;
	try {
		parsed = JSON.parse(trimmed) as Record<string, unknown>;
	} catch {
		return undefined;
	}

	if (parsed.type === "tool_execution_start" && typeof parsed.toolName === "string") {
		return { toolCallName: parsed.toolName };
	}

	if (parsed.type === "message_end" && parsed.message && typeof parsed.message === "object") {
		const message = parsed.message as Record<string, unknown>;
		if (message.role !== "assistant") return undefined;

		const content = Array.isArray(message.content) ? message.content : [];
		const textParts: string[] = [];
		for (const part of content) {
			if (part && typeof part === "object") {
				const record = part as Record<string, unknown>;
				if (record.type === "text" && typeof record.text === "string" && record.text.trim()) {
					textParts.push(record.text);
				}
			}
		}

		return {
			assistantText: textParts.length > 0 ? textParts.join("\n\n") : undefined,
			errorMessage:
				message.stopReason === "error" && typeof message.errorMessage === "string"
					? message.errorMessage
					: undefined,
		};
	}

	return undefined;
}

export interface ExploreRunOptions {
	baseCwd: string;
	subPath?: string;
	task: string;
	currentModel?: ExploreModelCandidate;
	availableModels: readonly ExploreModelCandidate[];
	signal?: AbortSignal;
	onProgress?: (toolCalls: number, toolName: string, modelLabel?: string) => void;
}

export interface ExploreRunResult {
	isError?: boolean;
	text: string;
	details: Record<string, unknown>;
}

async function resolveExploreCwd(baseCwd: string, subPath: string | undefined): Promise<string> {
	if (!subPath) return baseCwd;
	const target = resolve(baseCwd, subPath);
	const info = await stat(target);
	if (!info.isDirectory()) {
		throw new Error(`Explore path is not a directory: ${subPath}`);
	}
	return target;
}

export async function runExploreSubagent(options: ExploreRunOptions): Promise<ExploreRunResult> {
	const cwd = await resolveExploreCwd(options.baseCwd, options.subPath);
	const selected = selectExploreModel(options.currentModel, options.availableModels);
	const modelLabel = selected ? `${selected.provider}/${selected.id}` : undefined;
	const args = buildExploreArgs(options.task, selected);

	return new Promise((resolvePromise, rejectPromise) => {
		const child = spawn("pi", args, {
			cwd,
			stdio: ["ignore", "pipe", "pipe"],
			env: {
				...process.env,
				[EXPLORE_ENV_FLAG]: "1",
			},
		});

		let stdoutBuffer = "";
		let stderr = "";
		let lastAssistantText = "";
		let lastError = "";
		let toolCalls = 0;
		let settled = false;
		let aborted = false;
		let timedOut = false;
		let killTimer: ReturnType<typeof setTimeout> | undefined;

		const terminateChild = () => {
			if (child.exitCode !== null || child.killed) return;
			child.kill("SIGTERM");
			killTimer = setTimeout(() => {
				if (child.exitCode === null) child.kill("SIGKILL");
			}, KILL_GRACE_MS);
		};

		const timeoutTimer = setTimeout(() => {
			timedOut = true;
			terminateChild();
		}, EXPLORE_TIMEOUT_MS);

		const onAbort = () => {
			aborted = true;
			terminateChild();
		};
		if (options.signal) {
			if (options.signal.aborted) {
				onAbort();
			} else {
				options.signal.addEventListener("abort", onAbort, { once: true });
			}
		}

		const cleanup = () => {
			clearTimeout(timeoutTimer);
			if (killTimer) clearTimeout(killTimer);
			options.signal?.removeEventListener("abort", onAbort);
		};

		const handleLine = (line: string) => {
			const parsed = parseExploreJsonLine(line);
			if (!parsed) return;
			if (parsed.toolCallName) {
				toolCalls++;
				options.onProgress?.(toolCalls, parsed.toolCallName, modelLabel);
			}
			if (parsed.assistantText) {
				lastAssistantText = parsed.assistantText;
			}
			if (parsed.errorMessage) {
				lastError = parsed.errorMessage;
			}
		};

		child.stdout.on("data", (chunk: Buffer) => {
			stdoutBuffer += chunk.toString("utf-8");
			let newlineIdx = stdoutBuffer.indexOf("\n");
			while (newlineIdx !== -1) {
				const line = stdoutBuffer.slice(0, newlineIdx);
				stdoutBuffer = stdoutBuffer.slice(newlineIdx + 1);
				handleLine(line);
				newlineIdx = stdoutBuffer.indexOf("\n");
			}
		});

		child.stderr.on("data", (chunk: Buffer) => {
			stderr += chunk.toString("utf-8");
		});

		child.on("error", (error) => {
			if (settled) return;
			settled = true;
			cleanup();
			rejectPromise(error);
		});

		child.on("close", (code) => {
			if (settled) return;
			settled = true;
			cleanup();

			if (stdoutBuffer.trim()) {
				handleLine(stdoutBuffer);
			}

			if (aborted) {
				resolvePromise({
					isError: true,
					text: "Explore subagent aborted.",
					details: { aborted: true, toolCalls },
				});
				return;
			}

			if (timedOut) {
				const partial = lastAssistantText
					? `\n\nPartial findings:\n${lastAssistantText.slice(0, MAX_EXPLORE_OUTPUT_CHARS)}`
					: "";
				resolvePromise({
					isError: true,
					text: `Explore subagent timed out after ${Math.round(EXPLORE_TIMEOUT_MS / 1000)}s.${partial}`,
					details: { timedOut: true, toolCalls },
				});
				return;
			}

			if (code !== 0 || (lastError && !lastAssistantText)) {
				const reason = lastError || stderr.trim() || `exit code ${code}`;
				resolvePromise({
					isError: true,
					text: `Explore subagent failed: ${reason}`,
					details: { exitCode: code, toolCalls },
				});
				return;
			}

			let output = lastAssistantText.trim() || "(Explore subagent returned no text output.)";
			if (output.length > MAX_EXPLORE_OUTPUT_CHARS) {
				output = `${output.slice(0, MAX_EXPLORE_OUTPUT_CHARS)}\n\n[Explore output truncated at ${MAX_EXPLORE_OUTPUT_CHARS} chars]`;
			}

			resolvePromise({
				text: output,
				details: { model: modelLabel, toolCalls, cwd },
			});
		});
	});
}
