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
