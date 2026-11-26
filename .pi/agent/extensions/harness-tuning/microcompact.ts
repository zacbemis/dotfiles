export const MICROCOMPACT_DISABLE_ENV = "PI_HARNESS_MICROCOMPACT";

const ANTHROPIC_CACHE_TTL_MS = 5 * 60_000;
const DEFAULT_CACHE_TTL_MS = 10 * 60_000;
const DEFAULT_KEEP_RECENT_TURNS = 6;
const DEFAULT_KEEP_RECENT_TOOL_RESULTS = 8;
const DEFAULT_MIN_PRUNE_CHARS = 2_400;
const DEFAULT_MIN_CONTEXT_CHARS = 100_000;
const MAX_DYNAMIC_CONTEXT_CHARS = 160_000;
const MIN_DYNAMIC_CONTEXT_CHARS = 80_000;
const ERROR_PREVIEW_EDGE_CHARS = 300;

const PRUNABLE_TOOLS = new Set(["read", "bash", "grep", "find", "ls", "explore"]);

export interface MicrocompactModelLike {
	readonly provider?: string;
	readonly id?: string;
	readonly contextWindow?: number;
}

export interface MicrocompactMessageLike {
	readonly role: string;
	readonly toolCallId?: string;
	readonly toolName?: string;
	readonly isError?: boolean;
	readonly content?: unknown;
}

export interface SessionBranchEntryLike {
	readonly type: string;
	readonly kind?: string;
	readonly provider?: string;
	readonly timestamp?: string;
	readonly message?: { readonly role?: string };
}

export function findRecentCacheWarmAtMs(
	entries: readonly SessionBranchEntryLike[] | undefined,
	provider: string | undefined,
): number | undefined {
	if (!entries || entries.length === 0) return undefined;
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i]!;
		if (entry.type === "usage" && entry.kind === "cache_warm") {
			if (provider && entry.provider && entry.provider !== provider) {
				return undefined;
			}
			const parsed = typeof entry.timestamp === "string" ? Date.parse(entry.timestamp) : Number.NaN;
			return Number.isFinite(parsed) ? parsed : undefined;
		}
		if (
			entry.type === "model_change" ||
			entry.type === "compaction" ||
			(entry.type === "message" && entry.message?.role === "assistant")
		) {
			return undefined;
		}
	}
	return undefined;
}

interface ToolCallMetadata {
	readonly name: string;
	readonly arguments: Record<string, unknown>;
}

export function getProviderCacheTtlMs(model: MicrocompactModelLike | undefined): number {
	const provider = model?.provider?.toLowerCase() ?? "";
	const id = model?.id?.toLowerCase() ?? "";
	if (provider.includes("anthropic") || id.includes("claude")) {
		return ANTHROPIC_CACHE_TTL_MS;
	}
	return DEFAULT_CACHE_TTL_MS;
}

function resolveContextThresholdChars(
	model: MicrocompactModelLike | undefined,
	explicitThreshold?: number,
): number {
	if (explicitThreshold !== undefined) return explicitThreshold;
	const windowTokens = model?.contextWindow;
	if (typeof windowTokens === "number" && windowTokens > 0) {
		const estimatedChars = Math.floor(windowTokens * 4 * 0.25);
		return Math.min(MAX_DYNAMIC_CONTEXT_CHARS, Math.max(MIN_DYNAMIC_CONTEXT_CHARS, estimatedChars));
	}
	return DEFAULT_MIN_CONTEXT_CHARS;
}

function extractTextAndImageState(content: unknown): { text: string; hasImage: boolean } {
	if (typeof content === "string") {
		return { text: content, hasImage: false };
	}
	if (!Array.isArray(content)) {
		return { text: "", hasImage: false };
	}
	const parts: string[] = [];
	let hasImage = false;
	for (const block of content) {
		if (typeof block !== "object" || block === null) continue;
		const typed = block as { type?: string; text?: string };
		if (typed.type === "image") {
			hasImage = true;
		} else if (typed.type === "text" && typeof typed.text === "string") {
			parts.push(typed.text);
		}
	}
	return { text: parts.join("\n"), hasImage };
}

function estimateMessageChars(message: MicrocompactMessageLike): number {
	if (typeof message.content === "string") return message.content.length;
	if (!Array.isArray(message.content)) return 0;
	let chars = 0;
	for (const block of message.content) {
		if (typeof block !== "object" || block === null) continue;
		const typed = block as { type?: string; text?: string; thinking?: string; arguments?: unknown };
		if (typed.type === "text" && typeof typed.text === "string") {
			chars += typed.text.length;
		} else if (typed.type === "thinking" && typeof typed.thinking === "string") {
			chars += typed.thinking.length;
		} else if (typed.type === "toolCall") {
			chars += JSON.stringify(typed.arguments ?? {}).length;
		}
	}
	return chars;
}

function summarizeCallTarget(toolName: string, callArgs: Record<string, unknown> | undefined): string {
	if (!callArgs) return toolName;
	if (toolName === "read") {
		const path = typeof callArgs.path === "string" ? callArgs.path : undefined;
		const offset = typeof callArgs.offset === "number" ? callArgs.offset : undefined;
		const limit = typeof callArgs.limit === "number" ? callArgs.limit : undefined;
		if (path) {
			const range =
				offset !== undefined || limit !== undefined
					? ` (offset=${offset ?? 1}${limit !== undefined ? `, limit=${limit}` : ""})`
					: "";
			return `read of ${path}${range}`;
		}
	}
	if (toolName === "bash") {
		const cmd = typeof callArgs.command === "string" ? callArgs.command.trim().replace(/\s+/g, " ") : undefined;
		if (cmd) {
			const shortCmd = cmd.length > 80 ? `${cmd.slice(0, 77)}...` : cmd;
			return `bash \`${shortCmd}\``;
		}
	}
	if (toolName === "grep") {
		const pattern = typeof callArgs.pattern === "string" ? callArgs.pattern : undefined;
		const path = typeof callArgs.path === "string" ? callArgs.path : undefined;
		if (pattern) {
			return `grep "${pattern.slice(0, 60)}"${path ? ` in ${path}` : ""}`;
		}
	}
	if (toolName === "find" || toolName === "ls") {
		const path = typeof callArgs.path === "string" ? callArgs.path : ".";
		const pattern = typeof callArgs.pattern === "string" ? ` "${callArgs.pattern}"` : "";
		return `${toolName}${pattern} in ${path}`;
	}
	if (toolName === "explore") {
		const task = typeof callArgs.task === "string" ? callArgs.task.trim().replace(/\s+/g, " ") : undefined;
		if (task) {
			return `explore "${task.length > 70 ? `${task.slice(0, 67)}...` : task}"`;
		}
	}
	return toolName;
}

function buildPrunedStub(
	toolName: string,
	callArgs: Record<string, unknown> | undefined,
	originalText: string,
	isError: boolean,
): string {
	const target = summarizeCallTarget(toolName, callArgs);
	const lines = originalText.split("\n").length;
	const header = `[Microcompacted ${target} (${lines} lines, ${originalText.length.toLocaleString("en-US")} chars${isError ? ", error" : ""}) — re-run tool if full output is needed]`;
	if (!isError) return header;

	const head = originalText.slice(0, ERROR_PREVIEW_EDGE_CHARS).trim();
	const tail = originalText.slice(-ERROR_PREVIEW_EDGE_CHARS).trim();
	return `${header}\nError excerpt:\n${head}\n[...]\n${tail}`;
}

export function createMicrocompactor(options?: {
	readonly keepRecentTurns?: number;
	readonly keepRecentToolResults?: number;
	readonly minPruneChars?: number;
	readonly minContextChars?: number;
}) {
	const keepRecentTurns = options?.keepRecentTurns ?? DEFAULT_KEEP_RECENT_TURNS;
	const keepRecentToolResults = options?.keepRecentToolResults ?? DEFAULT_KEEP_RECENT_TOOL_RESULTS;
	const minPruneChars = options?.minPruneChars ?? DEFAULT_MIN_PRUNE_CHARS;
	const explicitMinContextChars = options?.minContextChars;

	let lastActivityAtMs: number | undefined;
	// Sticky stub map: once a cold-cache pass stubs a toolCallId, subsequent warm turns
	// keep applying the exact same stub so the newly warmed prefix cache stays 100% valid.
	const prunedStubs = new Map<string, string>();

	return {
		reset(): void {
			lastActivityAtMs = undefined;
			prunedStubs.clear();
		},

		get prunedCount(): number {
			return prunedStubs.size;
		},

		isPruned(toolCallId: string): boolean {
			return prunedStubs.has(toolCallId);
		},

		transformContext<TMessage extends MicrocompactMessageLike>(
			messages: readonly TMessage[],
			model: MicrocompactModelLike | undefined,
			nowMs = Date.now(),
			lastCacheWarmAtMs?: number,
		): TMessage[] | undefined {
			if (process.env[MICROCOMPACT_DISABLE_ENV] === "0") {
				lastActivityAtMs = nowMs;
				return undefined;
			}

			const cacheTtlMs = getProviderCacheTtlMs(model);
			const effectiveLastActivityAtMs =
				lastActivityAtMs !== undefined && lastCacheWarmAtMs !== undefined
					? Math.max(lastActivityAtMs, lastCacheWarmAtMs)
					: (lastActivityAtMs ?? lastCacheWarmAtMs);
			const isCold = effectiveLastActivityAtMs === undefined || nowMs - effectiveLastActivityAtMs >= cacheTtlMs;
			lastActivityAtMs = nowMs;

			if (isCold && messages.length > 0) {
				let totalChars = 0;
				for (const msg of messages) {
					totalChars += estimateMessageChars(msg);
				}

				const thresholdChars = resolveContextThresholdChars(model, explicitMinContextChars);
				if (totalChars >= thresholdChars) {
					const toolCalls = new Map<string, ToolCallMetadata>();
					const assistantIndices: number[] = [];
					const toolResultIndices: number[] = [];

					for (let i = 0; i < messages.length; i++) {
						const msg = messages[i]!;
						if (msg.role === "assistant") {
							assistantIndices.push(i);
							if (Array.isArray(msg.content)) {
								for (const block of msg.content) {
									if (typeof block !== "object" || block === null) continue;
									const call = block as {
										type?: string;
										id?: string;
										name?: string;
										arguments?: Record<string, unknown>;
									};
									if (call.type === "toolCall" && typeof call.id === "string" && typeof call.name === "string") {
										toolCalls.set(call.id, { name: call.name, arguments: call.arguments ?? {} });
									}
								}
							}
						} else if (msg.role === "toolResult") {
							toolResultIndices.push(i);
						}
					}

					const turnCutoff =
						assistantIndices.length > keepRecentTurns
							? assistantIndices[assistantIndices.length - keepRecentTurns]!
							: 0;
					const toolResultCutoff =
						toolResultIndices.length > keepRecentToolResults
							? toolResultIndices[toolResultIndices.length - keepRecentToolResults]!
							: 0;
					const cutoffIndex = Math.min(turnCutoff, toolResultCutoff);

					for (let i = 0; i < cutoffIndex; i++) {
						const msg = messages[i]!;
						if (msg.role !== "toolResult" || !msg.toolCallId) continue;
						if (prunedStubs.has(msg.toolCallId)) continue;

						const toolMeta = toolCalls.get(msg.toolCallId);
						const toolName = msg.toolName ?? toolMeta?.name;
						if (!toolName || !PRUNABLE_TOOLS.has(toolName)) continue;

						const { text, hasImage } = extractTextAndImageState(msg.content);
						if (hasImage || text.length < minPruneChars) continue;

						prunedStubs.set(
							msg.toolCallId,
							buildPrunedStub(toolName, toolMeta?.arguments, text, Boolean(msg.isError)),
						);
					}
				}
			}

			if (prunedStubs.size === 0) return undefined;

			let applied = false;
			const next = messages.map((msg) => {
				if (msg.role !== "toolResult" || !msg.toolCallId) return msg;
				const stub = prunedStubs.get(msg.toolCallId);
				if (stub === undefined) return msg;
				applied = true;
				return {
					...msg,
					content: [{ type: "text", text: stub }],
				};
			});

			return applied ? next : undefined;
		},
	};
}
