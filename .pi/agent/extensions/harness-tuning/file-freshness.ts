import { stat } from "node:fs/promises";
import { relative, resolve } from "node:path";
import type { PatchHunk } from "./patch-parser.ts";

const DEFAULT_MTIME_TOLERANCE_MS = 50;

interface FileSnapshot {
	readonly mtimeMs: number;
	readonly size: number;
}

export interface FreshnessCheckResult {
	readonly stale: boolean;
	readonly displayPath?: string;
	readonly reason?: string;
}

function resolveTrackedPath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

function formatDisplayPath(cwd: string, absPath: string): string {
	const rel = relative(cwd, absPath);
	if (rel && !rel.startsWith("..") && !rel.startsWith("/")) return rel;
	return absPath;
}

export function createFileFreshnessTracker(options?: { mtimeToleranceMs?: number }) {
	const mtimeToleranceMs = options?.mtimeToleranceMs ?? DEFAULT_MTIME_TOLERANCE_MS;
	const snapshots = new Map<string, FileSnapshot>();

	const recordAbsPath = async (absPath: string): Promise<void> => {
		try {
			const info = await stat(absPath);
			if (info.isFile()) {
				snapshots.set(absPath, { mtimeMs: info.mtimeMs, size: info.size });
			}
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") {
				snapshots.delete(absPath);
			}
		}
	};

	const checkAbsPath = async (cwd: string, absPath: string): Promise<FreshnessCheckResult> => {
		const recorded = snapshots.get(absPath);
		if (!recorded) return { stale: false };

		const displayPath = formatDisplayPath(cwd, absPath);
		try {
			const info = await stat(absPath);
			if (!info.isFile()) return { stale: false };
			const mtimeChanged = Math.abs(info.mtimeMs - recorded.mtimeMs) > mtimeToleranceMs;
			const sizeChanged = info.size !== recorded.size;
			if (mtimeChanged || sizeChanged) {
				return {
					stale: true,
					displayPath,
					reason: `File '${displayPath}' was modified on disk since it was last read. Re-read it before editing so you do not overwrite external changes.`,
				};
			}
			return { stale: false };
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") {
				return {
					stale: true,
					displayPath,
					reason: `File '${displayPath}' was deleted on disk since it was last read. Re-check its status before editing.`,
				};
			}
			return { stale: false };
		}
	};

	return {
		clear(): void {
			snapshots.clear();
		},

		async recordFromDisk(cwd: string, rawPath: string): Promise<void> {
			await recordAbsPath(resolveTrackedPath(cwd, rawPath));
		},

		forget(cwd: string, rawPath: string): void {
			snapshots.delete(resolveTrackedPath(cwd, rawPath));
		},

		async checkFreshness(cwd: string, rawPath: string): Promise<FreshnessCheckResult> {
			return checkAbsPath(cwd, resolveTrackedPath(cwd, rawPath));
		},

		async checkPathsForPatch(cwd: string, hunks: readonly PatchHunk[]): Promise<FreshnessCheckResult> {
			const addedInPatch = new Set<string>();
			const checked = new Set<string>();
			for (const hunk of hunks) {
				const absPath = resolveTrackedPath(cwd, hunk.path);
				if (hunk.type === "add") {
					addedInPatch.add(absPath);
					continue;
				}
				if (addedInPatch.has(absPath) || checked.has(absPath)) continue;
				checked.add(absPath);
				const result = await checkAbsPath(cwd, absPath);
				if (result.stale) return result;
			}
			return { stale: false };
		},
	};
}
