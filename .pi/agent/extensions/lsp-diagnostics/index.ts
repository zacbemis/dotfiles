import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createLspDiagnosticsManager } from "./manager.ts";

type ContentBlock = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };

interface PatchFileDetail {
	readonly status?: "A" | "D" | "M";
	readonly path?: string;
	readonly movedFrom?: string;
}

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
	const manager = createLspDiagnosticsManager();

	pi.on("tool_result", async (event, ctx) => {
		if (event.isError) return;
		if (event.toolName !== "edit" && event.toolName !== "write" && event.toolName !== "patch") {
			return;
		}

		const { modified, deleted } = extractEditedPaths(event.toolName, event.input, event.details);
		if (modified.length === 0 && deleted.length === 0) return;

		const diagnosticBlock = await manager.checkFiles(ctx.cwd, modified, deleted);
		if (!diagnosticBlock) return;

		return {
			content: appendToLastTextBlock(event.content as ContentBlock[], diagnosticBlock),
			...(event.structuredContent !== undefined ? { structuredContent: event.structuredContent } : {}),
		};
	});

	pi.on("session_shutdown", async () => {
		await manager.shutdownAll();
	});
}
