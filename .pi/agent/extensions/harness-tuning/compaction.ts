import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { type PatchSummaryEntry } from "./apply-patch.ts";
import { parsePatch } from "./patch-parser.ts";

const execFileAsync = promisify(execFile);

export const COMPACTION_DISABLE_ENV = "PI_HARNESS_COMPACTION";

const GIT_STATE_TIMEOUT_MS = 1_500;
const MAX_STATE_LINES = 25;
const MAX_STATE_CHARS = 1_200;

export interface FileOperationsLike {
	read: Set<string>;
	written: Set<string>;
	edited: Set<string>;
}

export interface CompactionPreparationLike {
	firstKeptEntryId: string;
	messagesToSummarize: readonly AgentMessageLike[];
	turnPrefixMessages: readonly AgentMessageLike[];
	isSplitTurn: boolean;
	tokensBefore: number;
	previousSummary?: string;
	fileOps: FileOperationsLike;
}

export interface AgentMessageLike {
	readonly role: string;
	readonly content?: unknown;
	readonly stopReason?: string;
	readonly toolName?: string;
	readonly details?: unknown;
	readonly timestamp?: number;
}

export interface AssistantResponseLike {
	readonly role: "assistant";
	readonly content: readonly { readonly type: string; readonly text?: string }[];
	readonly stopReason?: string;
	readonly usage?: unknown;
}

export interface CompactionResultLike {
	summary: string;
	firstKeptEntryId: string;
	tokensBefore: number;
	usage?: unknown;
	details?: {
		readFiles: string[];
		modifiedFiles: string[];
		warmPrefix: boolean;
	};
}

function messageHasToolCalls(message: AgentMessageLike): boolean {
	if (message.role !== "assistant" || !Array.isArray(message.content)) return false;
	return message.content.some(
		(block) => typeof block === "object" && block !== null && (block as { type?: string }).type === "toolCall",
	);
}

function extractTextFromResponse(response: AssistantResponseLike): string {
	return response.content
		.filter((block): block is { type: "text"; text: string } => block.type === "text" && typeof block.text === "string")
		.map((block) => block.text)
		.join("\n")
		.trim();
}

/**
 * Extract files modified/added/deleted/moved via the custom `patch` tool and merge
 * them into Pi's compaction FileOperations (which only inspects read/write/edit).
 */
export function enrichFileOpsWithPatch(
	fileOps: FileOperationsLike,
	messages: readonly AgentMessageLike[],
): void {
	for (const msg of messages) {
		if (msg.role === "assistant" && Array.isArray(msg.content)) {
			for (const block of msg.content) {
				if (typeof block !== "object" || block === null) continue;
				const candidate = block as { type?: string; name?: string; arguments?: Record<string, unknown> };
				if (candidate.type !== "toolCall" || candidate.name !== "patch") continue;
				const patchText = candidate.arguments?.patch;
				if (typeof patchText !== "string") continue;
				try {
					for (const hunk of parsePatch(patchText)) {
						if (hunk.type === "add") {
							fileOps.written.add(hunk.path);
						} else if (hunk.type === "delete") {
							fileOps.edited.add(hunk.path);
						} else {
							fileOps.edited.add(hunk.path);
							if (hunk.movePath) {
								fileOps.written.add(hunk.movePath);
							}
						}
					}
				} catch {
					// Malformed patch call that failed validation; ignore.
				}
			}
			continue;
		}

		if (msg.role === "toolResult" && msg.toolName === "patch") {
			const details = msg.details as { files?: readonly PatchSummaryEntry[] } | undefined;
			if (!Array.isArray(details?.files)) continue;
			for (const entry of details.files) {
				if (!entry?.path) continue;
				if (entry.status === "A") {
					fileOps.written.add(entry.path);
				} else {
					fileOps.edited.add(entry.path);
				}
				if (entry.movedFrom) {
					fileOps.edited.add(entry.movedFrom);
				}
			}
		}
	}
}

export function computeCompactionFileLists(fileOps: FileOperationsLike): {
	readFiles: string[];
	modifiedFiles: string[];
} {
	const modified = new Set<string>([...fileOps.edited, ...fileOps.written]);
	const readFiles = [...fileOps.read].filter((path) => !modified.has(path)).sort();
	const modifiedFiles = [...modified].sort();
	return { readFiles, modifiedFiles };
}

export function formatCompactionFileLists(readFiles: readonly string[], modifiedFiles: readonly string[]): string {
	const sections: string[] = [];
	if (readFiles.length > 0) {
		sections.push(`<read-files>\n${readFiles.join("\n")}\n</read-files>`);
	}
	if (modifiedFiles.length > 0) {
		sections.push(`<modified-files>\n${modifiedFiles.join("\n")}\n</modified-files>`);
	}
	return sections.length > 0 ? `\n\n${sections.join("\n\n")}` : "";
}

function clampBlock(text: string, maxLines: number, maxChars: number): string {
	const lines = text
		.split("\n")
		.map((line) => line.trimEnd())
		.filter((line) => line.length > 0);
	let result = lines.slice(0, maxLines).join("\n");
	if (lines.length > maxLines) {
		result += `\n[... ${lines.length - maxLines} more lines omitted]`;
	}
	if (result.length > maxChars) {
		result = `${result.slice(0, maxChars)}... [truncated]`;
	}
	return result;
}

export async function collectWorkspaceState(
	cwd: string,
	timeoutMs = GIT_STATE_TIMEOUT_MS,
): Promise<string | undefined> {
	const runGit = async (args: readonly string[]): Promise<string | undefined> => {
		try {
			const { stdout } = await execFileAsync("git", [...args], {
				cwd,
				timeout: timeoutMs,
				maxBuffer: 128 * 1024,
				windowsHide: true,
			});
			const trimmed = stdout.trim();
			return trimmed.length > 0 ? trimmed : undefined;
		} catch {
			return undefined;
		}
	};

	const [status, diffStat] = await Promise.all([
		runGit(["status", "--short", "--untracked-files=normal"]),
		runGit(["diff", "--stat"]),
	]);
	if (!status && !diffStat) return undefined;

	const parts: string[] = [];
	if (status) {
		parts.push(`git status:\n${clampBlock(status, MAX_STATE_LINES, MAX_STATE_CHARS)}`);
	}
	if (diffStat) {
		parts.push(`git diff --stat:\n${clampBlock(diffStat, MAX_STATE_LINES, MAX_STATE_CHARS)}`);
	}
	const combined = clampBlock(parts.join("\n\n"), MAX_STATE_LINES + 10, MAX_STATE_CHARS + 400);
	return `\n\n<workspace-state>\n${combined}\n</workspace-state>`;
}

export function buildWarmCompactionPrompt(options: {
	readonly previousSummary?: string;
	readonly customInstructions?: string;
}): string {
	const sections = [
		"Create a structured context checkpoint summary of this conversation so work can continue seamlessly after compaction.",
		"RULES:",
		"- Do NOT call any tools. Do NOT continue the conversation or answer pending questions. Output ONLY the checkpoint summary.",
		"- The most recent conversation turns will remain verbatim after this checkpoint, so prioritize preserving earlier goals, decisions, constraints, exact file paths, symbol names, commands, and unresolved errors.",
	];

	if (options.previousSummary) {
		sections.push(
			"- An earlier checkpoint already exists in the conversation above: preserve all still-relevant facts from it, move completed items to Done, and update Next Steps.",
		);
	}

	sections.push(
		"",
		"Use this EXACT format:",
		"",
		"## Goal",
		"[What the user is trying to accomplish]",
		"",
		"## Constraints & Preferences",
		"- [Requirements, constraints, or preferences stated by the user, or \"(none)\"]",
		"",
		"## Progress",
		"### Done",
		"- [x] [Completed tasks/changes]",
		"",
		"### In Progress",
		"- [ ] [Current work]",
		"",
		"### Blocked",
		"- [Issues preventing progress, if any]",
		"",
		"## Key Decisions",
		"- **[Decision]**: [Brief rationale]",
		"",
		"## Next Steps",
		"1. [Ordered list of what should happen next]",
		"",
		"## Critical Context",
		"- [Exact file paths, function/type names, error messages, or test commands needed to continue, or \"(none)\"]",
	);

	if (options.customInstructions?.trim()) {
		sections.push("", `Additional focus: ${options.customInstructions.trim()}`);
	}

	return sections.join("\n");
}

export function createWarmPrefixTracker() {
	let lastContextMessages: AgentMessageLike[] | undefined;
	let trailingAssistant: AgentMessageLike | undefined;

	return {
		clear(): void {
			lastContextMessages = undefined;
			trailingAssistant = undefined;
		},

		recordContextWithSystem(messages: readonly AgentMessageLike[]): void {
			if (messages.length === 0 || messages[0]?.role !== "system") {
				lastContextMessages = undefined;
				trailingAssistant = undefined;
				return;
			}
			lastContextMessages = structuredClone(messages) as AgentMessageLike[];
			trailingAssistant = undefined;
		},

		recordAssistantMessage(message: AgentMessageLike): void {
			if (!lastContextMessages) return;
			if (message.role !== "assistant") return;
			if (
				message.stopReason === "error" ||
				message.stopReason === "aborted" ||
				message.stopReason === "toolUse"
			) {
				return;
			}
			if (messageHasToolCalls(message)) return;
			trailingAssistant = structuredClone(message);
		},

		hasWarmPrefix(): boolean {
			return Boolean(lastContextMessages && lastContextMessages.length > 0 && lastContextMessages[0]?.role === "system");
		},

		buildForkedMessages<TMessage extends AgentMessageLike>(
			convertToLlmFn: (messages: AgentMessageLike[]) => TMessage[],
			promptText: string,
		): TMessage[] | undefined {
			if (!lastContextMessages || lastContextMessages.length === 0) return undefined;
			const converted = convertToLlmFn(structuredClone(lastContextMessages));
			if (converted.length === 0 || converted[0]?.role !== "system") return undefined;

			// Never append a user turn directly after an assistant message with unresponded tool calls.
			const tail = converted[converted.length - 1];
			if (tail && messageHasToolCalls(tail)) {
				return undefined;
			}

			const forked: TMessage[] = [...converted];
			if (trailingAssistant && tail?.role !== "assistant") {
				forked.push(structuredClone(trailingAssistant) as TMessage);
			}
			forked.push({
				role: "user",
				content: [{ type: "text", text: promptText }],
				timestamp: Date.now(),
			} as unknown as TMessage);

			return forked;
		},
	};
}

export type WarmPrefixTracker = ReturnType<typeof createWarmPrefixTracker>;

export async function runWarmCompaction<TMessage extends AgentMessageLike>(options: {
	readonly reason: "manual" | "threshold" | "overflow";
	readonly preparation: CompactionPreparationLike;
	readonly cwd: string;
	readonly sessionId?: string;
	readonly customInstructions?: string;
	readonly signal?: AbortSignal;
	readonly tracker: WarmPrefixTracker;
	readonly convertToLlm: (messages: AgentMessageLike[]) => TMessage[];
	readonly completeWarm: (messages: TMessage[]) => Promise<AssistantResponseLike>;
	readonly collectState?: (cwd: string) => Promise<string | undefined>;
}): Promise<CompactionResultLike | undefined> {
	// Always enrich preparation.fileOps with `patch` edits so even Pi's default fallback tracks them.
	enrichFileOpsWithPatch(options.preparation.fileOps, options.preparation.messagesToSummarize);
	if (options.preparation.turnPrefixMessages.length > 0) {
		enrichFileOpsWithPatch(options.preparation.fileOps, options.preparation.turnPrefixMessages);
	}

	if (process.env[COMPACTION_DISABLE_ENV] === "0") return undefined;
	if (options.reason === "overflow") return undefined;
	if (!options.tracker.hasWarmPrefix()) return undefined;

	const promptText = buildWarmCompactionPrompt({
		previousSummary: options.preparation.previousSummary,
		customInstructions: options.customInstructions,
	});
	const forkedMessages = options.tracker.buildForkedMessages(options.convertToLlm, promptText);
	if (!forkedMessages) return undefined;

	let response: AssistantResponseLike;
	try {
		response = await options.completeWarm(forkedMessages);
	} catch (error) {
		if (options.signal?.aborted) throw error;
		return undefined;
	}

	if (options.signal?.aborted) return undefined;
	if (
		response.stopReason === "error" ||
		response.stopReason === "aborted" ||
		response.stopReason === "length"
	) {
		return undefined;
	}
	if (response.content.some((block) => block.type === "toolCall")) {
		return undefined;
	}

	const summaryBody = extractTextFromResponse(response);
	if (!summaryBody) return undefined;

	const { readFiles, modifiedFiles } = computeCompactionFileLists(options.preparation.fileOps);
	const workspaceState = await (options.collectState ?? collectWorkspaceState)(options.cwd);
	const summary = `${summaryBody}${formatCompactionFileLists(readFiles, modifiedFiles)}${workspaceState ?? ""}`;

	return {
		summary,
		firstKeptEntryId: options.preparation.firstKeptEntryId,
		tokensBefore: options.preparation.tokensBefore,
		usage: response.usage,
		details: {
			readFiles,
			modifiedFiles,
			warmPrefix: true,
		},
	};
}
