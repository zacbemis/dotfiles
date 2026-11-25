import {
	type ExtensionAPI,
	isToolCallEventType,
	withFileMutationQueue,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
	computeRoutedTools,
	executePatchInDirectory,
	type ModelLike,
	PATCH_TOOL_NAME,
	usesPatchModel,
} from "./apply-patch.ts";
import { createProjectFormatter } from "./auto-format.ts";
import { type BashToolDetailsLike, sanitizeBashToolResult } from "./bash-hygiene.ts";
import { createDoomLoopTracker } from "./doom-loop.ts";
import {
	EXPLORE_ENV_FLAG,
	EXPLORE_TOOL_NAME,
	runExploreSubagent,
} from "./explore.ts";
import { createFileFreshnessTracker } from "./file-freshness.ts";
import {
	type ContextMessageLike,
	countTrailingLengthTruncations,
	LENGTH_CONTINUATION_PROMPT,
	LENGTH_CONTINUATION_TYPE,
	MAX_LENGTH_CONTINUATIONS,
} from "./output-continuation.ts";
import { PATCH_DESCRIPTION, PATCH_GRAMMAR } from "./patch-parser.ts";
import { createPostEditDiagnostics } from "./post-edit-diagnostics.ts";
import { buildPromptGuidelines, createEnvCache } from "./prompt-tuning.ts";
import { applyProviderHeaders, tuneOpenAIResponsesPayload } from "./provider-tuning.ts";
import {
	buildEditMissHint,
	buildReadMissingPathHint,
	clampLongLines,
	detectBinaryFile,
	parsePastEofError,
	recoverDirectoryRead,
	recoverPastEofRead,
	resolveCanonicalSibling,
	resolveReadOffsetFromDisk,
} from "./tool-ergonomics.ts";

const patchSchema = Type.Object({
	patch: Type.String({
		description: "Complete patch enclosed in *** Begin Patch / *** End Patch markers.",
	}),
});

const exploreSchema = Type.Object({
	task: Type.String({
		description: "Focused read-only exploration question or search goal to investigate in an isolated subagent.",
	}),
	path: Type.Optional(
		Type.String({
			description: "Optional subdirectory to scope the exploration working directory (defaults to current cwd).",
		}),
	),
});

type ContentBlock = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };

function appendToLastTextBlock(content: readonly ContentBlock[], suffix: string): ContentBlock[] {
	for (let i = content.length - 1; i >= 0; i--) {
		const block = content[i]!;
		if (block.type === "text") {
			const next = [...content];
			next[i] = { ...block, text: `${block.text}\n\n${suffix}` };
			return next;
		}
	}
	return [...content, { type: "text", text: suffix }];
}

function extractTextContent(content: readonly ContentBlock[]): string {
	return content
		.filter((block): block is { type: "text"; text: string } => block.type === "text")
		.map((block) => block.text)
		.join("\n");
}

export default function (pi: ExtensionAPI): void {
	const envCache = createEnvCache();
	const formatter = createProjectFormatter();
	const freshness = createFileFreshnessTracker();
	const diagnostics = createPostEditDiagnostics();
	const doomLoop = createDoomLoopTracker();

	// 1. Model-routed, grammar-constrained multi-file patch tool for GPT-5+/6+.
	pi.registerTool({
		name: PATCH_TOOL_NAME,
		label: "patch",
		description: PATCH_DESCRIPTION,
		promptSnippet: "Create, edit, move, or delete one or more files using *** Begin Patch / *** End Patch",
		promptGuidelines: [
			"Use patch for creating, updating, renaming, and deleting files instead of shell redirection or sed.",
		],
		parameters: patchSchema,
		defaultActive: false,
		constrainedSampling: {
			type: "grammar",
			variants: { openai_lark: PATCH_GRAMMAR },
		},
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const result = await executePatchInDirectory(
				ctx.cwd,
				params.patch,
				withFileMutationQueue,
				async (hunks) => {
					const check = await freshness.checkPathsForPatch(ctx.cwd, hunks);
					if (check.stale) {
						throw new Error(check.reason);
					}
				},
			);

			const livePaths: string[] = [];
			for (const entry of result.files) {
				if (entry.status === "D") {
					freshness.forget(ctx.cwd, entry.path);
					continue;
				}
				if (entry.movedFrom) {
					freshness.forget(ctx.cwd, entry.movedFrom);
				}
				await formatter.formatFile(ctx.cwd, entry.path, withFileMutationQueue);
				await freshness.recordFromDisk(ctx.cwd, entry.path);
				livePaths.push(entry.path);
			}

			const diagnosticBlock = await diagnostics.checkFiles(ctx.cwd, livePaths);
			const text = diagnosticBlock ? `${result.text}\n\n${diagnosticBlock}` : result.text;

			return {
				content: [{ type: "text", text }],
				details: { files: result.files },
			};
		},
	});

	const syncPatchRouting = (model: ModelLike | undefined) => {
		const active = pi.getActiveTools();
		const available = new Set(pi.getAllTools().map((tool) => tool.name));
		const routed = computeRoutedTools(active, available, usesPatchModel(model));
		if (routed) {
			pi.setActiveTools(routed);
		}
	};

	pi.on("session_start", (_event, ctx) => {
		envCache.clear();
		formatter.clear();
		freshness.clear();
		diagnostics.clear();
		doomLoop.reset();
		syncPatchRouting(ctx.model);
	});

	pi.on("model_select", (event) => {
		syncPatchRouting(event.model);
	});

	// 2. Per-model prompt micro-rules + cache-safe upfront <env> section.
	pi.on("before_agent_start", async (event, ctx) => {
		doomLoop.reset();
		const guidelines = buildPromptGuidelines({
			model: ctx.model,
			activeTools: event.systemPromptOptions.selectedTools,
		});
		event.systemPromptOptions.promptGuidelines.push(...guidelines);
		event.systemPromptOptions.sections.env = await envCache.resolveEnvSection(ctx.cwd);
	});

	// 3. OpenAI Responses direct-key verbosity/TPM tuning + xAI conversation cache header.
	pi.on("before_provider_request", (event, ctx) => {
		return tuneOpenAIResponsesPayload(event.payload, ctx.model);
	});

	pi.on("before_provider_headers", (event, ctx) => {
		applyProviderHeaders(event.headers, ctx.model, ctx.sessionManager.getSessionId());
	});

	// 4. Pre-execution guards: read ergonomics + stale-file external-modification guard.
	pi.on("tool_call", async (event, ctx) => {
		if (isToolCallEventType("edit", event) || isToolCallEventType("write", event)) {
			const check = await freshness.checkFreshness(ctx.cwd, event.input.path);
			if (check.stale) {
				return { block: true, reason: check.reason };
			}
			return;
		}

		if (!isToolCallEventType("read", event)) return;

		const canonicalPath = await resolveCanonicalSibling(ctx.cwd, event.input.path);
		if (canonicalPath) {
			event.input.path = canonicalPath;
		}

		if (await detectBinaryFile(ctx.cwd, event.input.path)) {
			return {
				block: true,
				reason: `Cannot read binary file: ${event.input.path}`,
			};
		}

		if (typeof event.input.offset === "number" && event.input.offset < 0) {
			const resolved = await resolveReadOffsetFromDisk(ctx.cwd, event.input.path, event.input.offset);
			if (resolved !== undefined) {
				event.input.offset = resolved;
			}
		}
	});

	// 5. Post-execution ergonomics: bash hygiene/head-tail, read recovery, edit missHint,
	//    auto-format + fast diagnostics, file-freshness recording, and doom-loop detection.
	pi.on("tool_result", async (event, ctx) => {
		let nextContent = event.content as ContentBlock[];
		let nextIsError = event.isError;
		let changed = false;

		if (event.toolName === "bash") {
			const firstTextIndex = nextContent.findIndex((block) => block.type === "text");
			if (firstTextIndex !== -1) {
				const firstText = nextContent[firstTextIndex] as { type: "text"; text: string };
				const sanitized = await sanitizeBashToolResult(
					firstText.text,
					event.details as BashToolDetailsLike | undefined,
					event.isError,
				);
				if (sanitized.changed) {
					nextContent = [...nextContent];
					nextContent[firstTextIndex] = { ...firstText, text: sanitized.text };
					changed = true;
				}
			}
		} else if (event.toolName === "read") {
			const rawPath = typeof event.input.path === "string" ? event.input.path : undefined;
			if (!event.isError) {
				let clampedAny = false;
				const clampedContent = nextContent.map((block) => {
					if (block.type !== "text") return block;
					const clamped = clampLongLines(block.text);
					if (!clamped.changed) return block;
					clampedAny = true;
					return { ...block, text: clamped.text };
				});
				if (clampedAny) {
					nextContent = clampedContent;
					changed = true;
				}
				if (rawPath) {
					await freshness.recordFromDisk(ctx.cwd, rawPath);
				}
			} else if (rawPath) {
				const firstText = nextContent.find((block) => block.type === "text");
				if (firstText && firstText.type === "text") {
					const pastEof = parsePastEofError(firstText.text);
					if (pastEof) {
						const limit = typeof event.input.limit === "number" ? event.input.limit : undefined;
						const recovered = await recoverPastEofRead(ctx.cwd, rawPath, pastEof.offset, limit);
						if (recovered) {
							nextContent = [{ type: "text", text: recovered }];
							nextIsError = false;
							changed = true;
							await freshness.recordFromDisk(ctx.cwd, rawPath);
						}
					} else if (firstText.text.includes("EISDIR")) {
						const offset = typeof event.input.offset === "number" ? event.input.offset : undefined;
						const limit = typeof event.input.limit === "number" ? event.input.limit : undefined;
						const listed = await recoverDirectoryRead(ctx.cwd, rawPath, offset, limit);
						if (listed) {
							nextContent = [{ type: "text", text: listed }];
							nextIsError = false;
							changed = true;
						}
					} else if (firstText.text.includes("ENOENT")) {
						const hint = await buildReadMissingPathHint(ctx.cwd, rawPath);
						if (hint) {
							nextContent = appendToLastTextBlock(nextContent, hint);
							changed = true;
						}
					}
				}
			}
		} else if (event.toolName === "edit" && event.isError) {
			const firstText = nextContent.find((block) => block.type === "text");
			if (firstText && firstText.type === "text") {
				const hint = await buildEditMissHint(ctx.cwd, event.input as Record<string, unknown>, firstText.text);
				if (hint) {
					nextContent = appendToLastTextBlock(nextContent, hint);
					changed = true;
				}
			}
		} else if ((event.toolName === "edit" || event.toolName === "write") && !event.isError) {
			const rawPath = typeof event.input.path === "string" ? event.input.path : undefined;
			if (rawPath) {
				await formatter.formatFile(ctx.cwd, rawPath, withFileMutationQueue);
				await freshness.recordFromDisk(ctx.cwd, rawPath);
				const diagnosticBlock = await diagnostics.checkFiles(ctx.cwd, [rawPath]);
				if (diagnosticBlock) {
					nextContent = appendToLastTextBlock(nextContent, diagnosticBlock);
					changed = true;
				}
			}
		}

		if (!event.parentToolCallId) {
			const loopNotice = doomLoop.recordToolResult({
				cwd: ctx.cwd,
				toolName: event.toolName,
				input: event.input,
				isError: nextIsError,
				resultText: extractTextContent(nextContent),
			});
			if (loopNotice) {
				nextContent = appendToLastTextBlock(nextContent, loopNotice);
				changed = true;
			}
		}

		if (!changed) return;
		return {
			content: nextContent,
			...(nextIsError !== event.isError ? { isError: nextIsError } : {}),
			...(event.structuredContent !== undefined ? { structuredContent: event.structuredContent } : {}),
		};
	});

	// 6. Automatic continuation (up to 2x) when a response stops at output token limit.
	pi.on("agent_before_settle", (event) => {
		if (event.outcome !== "completed" || event.continue) return;
		const trailing = countTrailingLengthTruncations(
			event.context.contextMessages as readonly ContextMessageLike[],
		);
		if (trailing === 0 || trailing > MAX_LENGTH_CONTINUATIONS) return;

		return {
			entries: [
				...event.entries,
				{
					type: "custom_message",
					customType: LENGTH_CONTINUATION_TYPE,
					content: LENGTH_CONTINUATION_PROMPT,
					display: false,
					details: { attempt: trailing },
				},
			],
			continue: true,
		};
	});

	// 7. Isolated read-only explore subagent tool (guarded against recursive spawn).
	if (process.env[EXPLORE_ENV_FLAG] !== "1") {
		pi.registerTool({
			name: EXPLORE_TOOL_NAME,
			label: "explore",
			description:
				"Run an isolated read-only subagent with read/grep/find/ls to investigate a codebase question and return concise findings without filling the main context.",
			promptSnippet:
				"Run an isolated read-only subagent for broad codebase discovery or multi-file tracing without bloating the main context",
			promptGuidelines: [
				"Use explore for open-ended codebase discovery or multi-file investigations; use read, grep, or find directly for known files or narrow lookups.",
			],
			parameters: exploreSchema,
			async execute(_toolCallId, params, signal, onUpdate, ctx) {
				const result = await runExploreSubagent({
					baseCwd: ctx.cwd,
					subPath: params.path,
					task: params.task,
					currentModel: ctx.model,
					availableModels: ctx.modelRegistry.getAvailable(),
					signal,
					onProgress: (toolCalls, toolName, modelLabel) => {
						onUpdate?.({
							content: [
								{
									type: "text",
									text: `Exploring (${toolCalls} tool call${toolCalls === 1 ? "" : "s"}: ${toolName})...`,
								},
							],
							details: { model: modelLabel, toolCalls },
						});
					},
				});

				return {
					isError: result.isError,
					content: [{ type: "text", text: result.text }],
					details: result.details,
				};
			},
		});
	}
}
