import { stat } from "node:fs/promises";
import { relative, resolve } from "node:path";

export const READ_DEDUP_DISABLE_ENV = "PI_HARNESS_READ_DEDUP";

const DEFAULT_MIN_DEDUP_CHARS = 1_200;
const DEFAULT_MTIME_TOLERANCE_MS = 50;

interface CachedReadEntry {
	toolCallId: string;
	mtimeMs: number;
	size: number;
	chars: number;
	lines: number;
	stubbedOnce: boolean;
}

export interface ReadDedupInput {
	readonly cwd: string;
	readonly rawPath: string;
	readonly offset?: number;
	readonly limit?: number;
	readonly toolCallId: string;
	readonly text: string;
	readonly hasImage?: boolean;
	readonly isPruned?: (toolCallId: string) => boolean;
}

export interface ReadDedupDecision {
	readonly deduplicated: boolean;
	readonly stub?: string;
}

function resolvePath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

function formatDisplayPath(cwd: string, absPath: string): string {
	const rel = relative(cwd, absPath);
	if (rel && !rel.startsWith("..") && !rel.startsWith("/")) return rel;
	return absPath;
}

function normalizeRangeKey(absPath: string, offset?: number, limit?: number): string {
	const start = typeof offset === "number" && Number.isFinite(offset) && offset > 0 ? Math.floor(offset) : 1;
	const count = typeof limit === "number" && Number.isFinite(limit) && limit > 0 ? Math.floor(limit) : 0;
	return `${absPath}::${start}::${count}`;
}

function formatRangeLabel(offset?: number, limit?: number): string {
	const start = typeof offset === "number" && Number.isFinite(offset) && offset > 0 ? Math.floor(offset) : 1;
	if (typeof limit === "number" && Number.isFinite(limit) && limit > 0) {
		return `lines ${start}-${start + Math.floor(limit) - 1}`;
	}
	return start === 1 ? "full/from line 1" : `from line ${start}`;
}

export function createReadDedupTracker(options?: {
	readonly minDedupChars?: number;
	readonly mtimeToleranceMs?: number;
}) {
	const minDedupChars = options?.minDedupChars ?? DEFAULT_MIN_DEDUP_CHARS;
	const mtimeToleranceMs = options?.mtimeToleranceMs ?? DEFAULT_MTIME_TOLERANCE_MS;

	const cache = new Map<string, CachedReadEntry>();

	const statFile = async (absPath: string): Promise<{ mtimeMs: number; size: number } | undefined> => {
		try {
			const info = await stat(absPath);
			if (!info.isFile()) return undefined;
			return { mtimeMs: info.mtimeMs, size: info.size };
		} catch {
			return undefined;
		}
	};

	return {
		clear(): void {
			cache.clear();
		},

		invalidatePath(cwd: string, rawPath: string): void {
			const prefix = `${resolvePath(cwd, rawPath)}::`;
			for (const key of cache.keys()) {
				if (key.startsWith(prefix)) {
					cache.delete(key);
				}
			}
		},

		get size(): number {
			return cache.size;
		},

		async checkAndRecord(input: ReadDedupInput): Promise<ReadDedupDecision> {
			if (process.env[READ_DEDUP_DISABLE_ENV] === "0") {
				return { deduplicated: false };
			}
			if (input.hasImage || input.text.length < minDedupChars) {
				return { deduplicated: false };
			}

			const absPath = resolvePath(input.cwd, input.rawPath);
			const disk = await statFile(absPath);
			if (!disk) return { deduplicated: false };

			const key = normalizeRangeKey(absPath, input.offset, input.limit);
			const existing = cache.get(key);

			if (existing) {
				const sameMtime = Math.abs(disk.mtimeMs - existing.mtimeMs) <= mtimeToleranceMs;
				const sameSize = disk.size === existing.size;
				const stillInContext = !input.isPruned?.(existing.toolCallId);

				if (sameMtime && sameSize && stillInContext && !existing.stubbedOnce) {
					existing.stubbedOnce = true;
					const displayPath = formatDisplayPath(input.cwd, absPath);
					const rangeLabel = formatRangeLabel(input.offset, input.limit);
					return {
						deduplicated: true,
						stub: `[Unchanged since earlier read of ${displayPath} (${rangeLabel}, ${existing.lines} lines, ${existing.chars.toLocaleString("en-US")} chars) — refer to the prior read in context. Call read again if you need the full content repeated.]`,
					};
				}
			}

			cache.set(key, {
				toolCallId: input.toolCallId,
				mtimeMs: disk.mtimeMs,
				size: disk.size,
				chars: input.text.length,
				lines: input.text.split("\n").length,
				stubbedOnce: false,
			});
			return { deduplicated: false };
		},
	};
}
