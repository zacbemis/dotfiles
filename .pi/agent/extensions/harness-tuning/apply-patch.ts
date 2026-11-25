import { mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { applyUpdateChunks, parsePatch } from "./patch-parser.ts";

export interface ModelLike {
	readonly id?: string;
	readonly provider?: string;
	readonly compat?: {
		readonly supportsOpenAIGrammarTools?: boolean;
	};
}

export const PATCH_TOOL_NAME = "patch";

export type FileLockFn = <T>(path: string, fn: () => Promise<T>) => Promise<T>;

const passthroughLock: FileLockFn = (_path, fn) => fn();

export function usesPatchModel(model: ModelLike | undefined): boolean {
	if (!model?.id) return false;
	if (model.compat?.supportsOpenAIGrammarTools !== true) return false;
	const id = model.id.toLowerCase();
	return id.includes("gpt-") && !id.includes("oss") && !id.includes("gpt-4");
}

export function computeRoutedTools(
	activeTools: readonly string[],
	availableTools: ReadonlySet<string>,
	preferPatch: boolean,
): string[] | undefined {
	const hasEdit = activeTools.includes("edit");
	const hasWrite = activeTools.includes("write");
	const hasPatch = activeTools.includes(PATCH_TOOL_NAME);

	if (preferPatch) {
		if (!availableTools.has(PATCH_TOOL_NAME)) return undefined;
		if (!hasEdit && !hasWrite) return undefined;
		const next: string[] = [];
		let inserted = false;
		for (const tool of activeTools) {
			if (tool === "edit" || tool === "write") {
				if (!inserted && !hasPatch) {
					next.push(PATCH_TOOL_NAME);
					inserted = true;
				}
				continue;
			}
			next.push(tool);
		}
		if (!inserted && !next.includes(PATCH_TOOL_NAME)) {
			next.push(PATCH_TOOL_NAME);
		}
		return next;
	}

	if (!hasPatch) return undefined;
	const next: string[] = [];
	for (const tool of activeTools) {
		if (tool === PATCH_TOOL_NAME) {
			if (!hasEdit && availableTools.has("edit")) next.push("edit");
			if (!hasWrite && availableTools.has("write")) next.push("write");
			continue;
		}
		next.push(tool);
	}
	return next;
}

function resolvePatchPath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

function formatDisplayPath(cwd: string, absolutePath: string): string {
	const rel = relative(cwd, absolutePath);
	if (rel && !rel.startsWith("..") && !rel.startsWith("/")) {
		return rel;
	}
	return absolutePath;
}

async function withOrderedFileLocks<T>(
	paths: readonly string[],
	lockFile: FileLockFn,
	fn: () => Promise<T>,
): Promise<T> {
	const uniqueSorted = [...new Set(paths)].sort();
	const run = (index: number): Promise<T> => {
		if (index >= uniqueSorted.length) return fn();
		return lockFile(uniqueSorted[index]!, () => run(index + 1));
	};
	return run(0);
}

export interface PatchSummaryEntry {
	status: "A" | "D" | "M";
	path: string;
	movedFrom?: string;
}

export async function executePatchInDirectory(
	cwd: string,
	patchText: string,
	lockFile: FileLockFn = passthroughLock,
): Promise<{ text: string; files: PatchSummaryEntry[] }> {
	const hunks = parsePatch(patchText);

	const lockPaths: string[] = [];
	for (const hunk of hunks) {
		lockPaths.push(resolvePatchPath(cwd, hunk.path));
		if (hunk.type === "update" && hunk.movePath) {
			lockPaths.push(resolvePatchPath(cwd, hunk.movePath));
		}
	}

	return withOrderedFileLocks(lockPaths, lockFile, async () => {
		// Stage all reads and transformations in memory first so a later mismatch leaves disk untouched.
		const staged = new Map<string, string | null>();
		const summary: PatchSummaryEntry[] = [];

		const readCurrent = async (absPath: string, displayPath: string): Promise<string> => {
			if (staged.has(absPath)) {
				const value = staged.get(absPath);
				if (value === null || value === undefined) {
					throw new Error(`File '${displayPath}' was deleted earlier in the same patch`);
				}
				return value;
			}
			try {
				return await readFile(absPath, "utf-8");
			} catch (error) {
				const code = (error as NodeJS.ErrnoException).code;
				if (code === "ENOENT") {
					throw new Error(`File not found: ${displayPath}`);
				}
				throw error;
			}
		};

		for (const hunk of hunks) {
			const absPath = resolvePatchPath(cwd, hunk.path);
			const displayPath = formatDisplayPath(cwd, absPath);

			if (hunk.type === "add") {
				const body = hunk.contents.length > 0 && !hunk.contents.endsWith("\n") ? `${hunk.contents}\n` : hunk.contents;
				staged.set(absPath, body);
				summary.push({ status: "A", path: displayPath });
				continue;
			}

			if (hunk.type === "delete") {
				await readCurrent(absPath, displayPath);
				staged.set(absPath, null);
				summary.push({ status: "D", path: displayPath });
				continue;
			}

			const original = await readCurrent(absPath, displayPath);
			const updated = applyUpdateChunks(original, displayPath, hunk.chunks);

			if (hunk.movePath) {
				const destAbs = resolvePatchPath(cwd, hunk.movePath);
				const destDisplay = formatDisplayPath(cwd, destAbs);
				if (destAbs !== absPath) {
					staged.set(absPath, null);
				}
				staged.set(destAbs, updated);
				summary.push({ status: "M", path: destDisplay, movedFrom: displayPath });
			} else {
				staged.set(absPath, updated);
				summary.push({ status: "M", path: displayPath });
			}
		}

		for (const [absPath, content] of staged) {
			if (content === null) {
				try {
					await unlink(absPath);
				} catch (error) {
					if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
				}
			} else {
				await mkdir(dirname(absPath), { recursive: true });
				await writeFile(absPath, content, "utf-8");
			}
		}

		const lines = summary.map((entry) =>
			entry.movedFrom ? `${entry.status} ${entry.path} (moved from ${entry.movedFrom})` : `${entry.status} ${entry.path}`,
		);
		return {
			text: `Success. Updated the following files:\n${lines.join("\n")}`,
			files: summary,
		};
	});
}
