import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { createLspDiagnosticsManager, type LspNavigationAction } from "./manager.ts";
import { hasConfiguredLspWorkspace } from "./servers.ts";
import { createLspSettleGuard, LSP_SETTLE_CONTINUATION_TYPE } from "./settle-guard.ts";

type ContentBlock = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };

interface PatchFileDetail {
	readonly status?: "A" | "D" | "M";
	readonly path?: string;
	readonly movedFrom?: string;
}

const lspSchema = Type.Object({
	action: Type.Union([
		Type.Literal("definition"),
		Type.Literal("references"),
		Type.Literal("hover"),
		Type.Literal("symbols"),
	]),
	path: Type.String({ description: "File path relative to cwd or absolute" }),
	line: Type.Optional(Type.Number({ description: "1-indexed line (for definition, references, hover)" })),
	column: Type.Optional(Type.Number({ description: "1-indexed column (optional if symbol is provided)" })),
	symbol: Type.Optional(Type.String({ description: "Identifier on line to resolve column automatically" })),
});

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

function extractEditedPaths(
	toolName: string,
	input: Record<string, unknown>,
	details: unknown,
): { modified: string[]; deleted: string[] } {
	if (toolName === "edit" || toolName === "write") {
		const path = typeof input.path === "string" ? input.path : undefined;
		return { modified: path ? [path] : [], deleted: [] };
	}

	if (toolName === "patch") {
		const files = (details as { files?: readonly PatchFileDetail[] } | undefined)?.files;
		if (!Array.isArray(files)) return { modified: [], deleted: [] };

		const modified: string[] = [];
		const deleted: string[] = [];
		for (const entry of files) {
			if (!entry?.path) continue;
			if (entry.status === "D") {
				deleted.push(entry.path);
			} else {
				modified.push(entry.path);
				if (entry.movedFrom) {
					deleted.push(entry.movedFrom);
				}
			}
		}
		return { modified, deleted };
	}

	return { modified: [], deleted: [] };
}

export default function (pi: ExtensionAPI): void {
	if (process.env.PI_EXPLORE_SUBAGENT === "1") return;
	const manager = createLspDiagnosticsManager();
	const settleGuard = createLspSettleGuard();
	let disabledByWorkspaceGate = false;

	pi.registerTool({
		name: "lsp",
		label: "lsp",
		description: "Semantic code navigation via warm project LSPs: definition, references, hover, or document symbols.",
		promptSnippet: "Look up symbol definition, references, hover type, or file outline via project LSP",
		promptGuidelines: [
			"Use lsp for exact definitions, references, hover types, or symbol outlines in typed repos instead of broad grep + full-file reads.",
		],
		parameters: lspSchema,
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const text = await manager.queryNavigation(ctx.cwd, {
				action: params.action as LspNavigationAction,
				path: params.path,
				line: params.line,
				column: params.column,
				symbol: params.symbol,
			});
			return {
				content: [{ type: "text", text }],
				details: { action: params.action, path: params.path },
			};
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		settleGuard.resetTurn();
		const hasLsp = await hasConfiguredLspWorkspace(ctx.cwd);
		const active = pi.getActiveTools();
		if (!hasLsp && active.includes("lsp")) {
			pi.setActiveTools(active.filter((name) => name !== "lsp"));
			disabledByWorkspaceGate = true;
		} else if (hasLsp && disabledByWorkspaceGate && !active.includes("lsp")) {
			pi.setActiveTools([...active, "lsp"]);
			disabledByWorkspaceGate = false;
		}
	});

	pi.on("before_agent_start", () => {
		settleGuard.resetTurn();
	});

	pi.on("session_compact", () => {
		settleGuard.resetTurn();
	});

	pi.on("tool_result", async (event, ctx) => {
		if (event.isError) return;
		if (event.toolName !== "edit" && event.toolName !== "write" && event.toolName !== "patch") {
			return;
		}

		const { modified, deleted } = extractEditedPaths(event.toolName, event.input, event.details);
		if (modified.length === 0 && deleted.length === 0) return;

		const result = await manager.checkFilesDetailed(ctx.cwd, modified, deleted);
		settleGuard.recordCheckResult(ctx.cwd, modified, deleted, result.errorsByFile);

		if (!result.block) return;

		return {
			content: appendToLastTextBlock(event.content as ContentBlock[], result.block),
			...(event.structuredContent !== undefined ? { structuredContent: event.structuredContent } : {}),
		};
	});

	pi.on("agent_before_settle", async (event, ctx) => {
		if (event.outcome !== "completed" || event.continue) return;
		const nudge = await settleGuard.buildSettleNudge(ctx.cwd, (cwd, paths) =>
			manager.checkFilesDetailed(cwd, paths),
		);
		if (!nudge) return;

		return {
			entries: [
				...event.entries,
				{
					type: "custom_message",
					customType: LSP_SETTLE_CONTINUATION_TYPE,
					content: nudge,
					display: false,
					details: { unresolvedCount: settleGuard.unresolvedCount },
				},
			],
			continue: true,
		};
	});

	pi.on("session_shutdown", async () => {
		await manager.shutdownAll();
	});
}
