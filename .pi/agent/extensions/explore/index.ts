import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { EXPLORE_ENV_FLAG, EXPLORE_TOOL_NAME, runExploreSubagent } from "./runner.ts";

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
	if (process.env[EXPLORE_ENV_FLAG] === "1") return;

	pi.registerTool({
		name: EXPLORE_TOOL_NAME,
		label: "explore",
		description:
			"Run an isolated read-only subagent for broad, unfamiliar, multi-directory codebase research (20+ files) without filling main context. Do not use for small repos, known paths, or targeted bug fixes; use find/grep/read/lsp directly instead.",
		promptSnippet:
			"Run a read-only subagent for broad, unfamiliar multi-directory research (20+ files) without filling main context",
		promptGuidelines: [
			"Use explore only for broad, unfamiliar, multi-directory research (20+ files); use find/grep/read (or lsp) directly for small repos, known paths, or targeted fixes.",
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
