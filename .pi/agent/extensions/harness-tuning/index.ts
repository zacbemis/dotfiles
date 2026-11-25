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
import {
	EXPLORE_ENV_FLAG,
	EXPLORE_TOOL_NAME,
	runExploreSubagent,
} from "./explore.ts";
import {
	type ContextMessageLike,
	countTrailingLengthTruncations,
	LENGTH_CONTINUATION_PROMPT,
	LENGTH_CONTINUATION_TYPE,
	MAX_LENGTH_CONTINUATIONS,
} from "./output-continuation.ts";
import { PATCH_DESCRIPTION, PATCH_GRAMMAR } from "./patch-parser.ts";
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

export default function (pi: ExtensionAPI): void {
	const envCache = createEnvCache();
	const formatter = createProjectFormatter();

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
			const result = await executePatchInDirectory(ctx.cwd, params.patch, withFileMutationQueue);
			for (const entry of result.files) {
				if (entry.status !== "D") {
					await formatter.formatFile(ctx.cwd, entry.path, withFileMutationQueue);
				}
			}
			return {
				content: [{ type: "text", text: result.text }],
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
		syncPatchRouting(ctx.model);
	});

	pi.on("model_select", (event) => {
		syncPatchRouting(event.model);
	});

	// 2. Per-model prompt micro-rules + cache-safe upfront <env> section.
	pi.on("before_agent_start", async (event, ctx) => {
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

	// 4. Read ergonomics (canonical sibling, binary guard, negative offset, past-EOF/EISDIR/ENOENT recovery)
	//    + edit missHint + silent project-aware auto-formatting.
	pi.on("tool_call", async (event, ctx) => {
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

	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName === "read") {
			if (!event.isError) {
				let anyChanged = false;
				const nextContent = event.content.map((block) => {
					if (block.type !== "text") return block;
					const clamped = clampLongLines(block.text);
					if (!clamped.changed) return block;
					anyChanged = true;
					return { ...block, text: clamped.text };
				});
				if (anyChanged) return { content: nextContent };
				return;
			}

			const firstText = event.content.find((block) => block.type === "text");
			const rawPath = typeof event.input.path === "string" ? event.input.path : undefined;
			if (!firstText || firstText.type !== "text" || !rawPath) return;

			const pastEof = parsePastEofError(firstText.text);
			if (pastEof) {
				const limit = typeof event.input.limit === "number" ? event.input.limit : undefined;
				const recovered = await recoverPastEofRead(ctx.cwd, rawPath, pastEof.offset, limit);
				if (recovered) {
					return {
						isError: false,
						content: [{ type: "text", text: recovered }],
					};
				}
			}

			if (firstText.text.includes("EISDIR")) {
				const offset = typeof event.input.offset === "number" ? event.input.offset : undefined;
				const limit = typeof event.input.limit === "number" ? event.input.limit : undefined;
				const listed = await recoverDirectoryRead(ctx.cwd, rawPath, offset, limit);
				if (listed) {
					return {
						isError: false,
						content: [{ type: "text", text: listed }],
					};
				}
			}

			if (firstText.text.includes("ENOENT")) {
				const hint = await buildReadMissingPathHint(ctx.cwd, rawPath);
				if (hint) {
					return {
						content: event.content.map((block) =>
							block === firstText ? { ...block, text: `${block.text}\n\n${hint}` } : block,
						),
					};
				}
			}
			return;
		}

		if (event.toolName === "edit" && event.isError) {
			const firstText = event.content.find((block) => block.type === "text");
			if (!firstText || firstText.type !== "text") return;
			const hint = await buildEditMissHint(ctx.cwd, event.input as Record<string, unknown>, firstText.text);
			if (!hint) return;
			return {
				content: event.content.map((block) =>
					block === firstText ? { ...block, text: `${block.text}\n\n${hint}` } : block,
				),
			};
		}

		if ((event.toolName === "edit" || event.toolName === "write") && !event.isError) {
			const rawPath = typeof event.input.path === "string" ? event.input.path : undefined;
			if (rawPath) {
				await formatter.formatFile(ctx.cwd, rawPath, withFileMutationQueue);
			}
		}
	});

	// 5. Automatic continuation (up to 2x) when a response stops at output token limit.
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

	// 6. Isolated read-only explore subagent tool (guarded against recursive spawn).
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
