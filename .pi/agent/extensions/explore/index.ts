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
			"Run an isolated read-only subagent to understand a project, survey multiple directories/files (6+ files), or gather broad context without filling main context. Prefer parallel explore calls by area for whole-project onboarding; use read/grep/find/lsp directly for narrow lookups or 1-5 specific files.",
		promptSnippet:
			"Run an isolated read-only subagent for project understanding, multi-file surveys (6+ files), or codebase discovery without filling main context",
		promptGuidelines: [
			"Use explore (or parallel explore calls by area) whenever you need to understand a project, survey multiple directories, or inspect more than ~5 files—never chain many sequential read/view_file calls in the main thread. Use read/grep/find/lsp directly for targeted lookups or 1-5 specific files.",
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
