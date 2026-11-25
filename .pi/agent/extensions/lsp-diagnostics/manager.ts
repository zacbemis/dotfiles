import { dirname, relative, resolve } from "node:path";
import { LspClient, type LspDiagnosticItem } from "./client.ts";
import {
	DEFAULT_LSP_SERVERS,
	findGitRoot,
	findProjectRoot,
	isInsideDirectory,
	type LspServerSpec,
	matchServerSpec,
	resolveServerBinary,
} from "./servers.ts";

export const LSP_DIAGNOSTICS_DISABLE_ENV = "PI_LSP_DIAGNOSTICS";

const DEFAULT_MAX_SERVERS = 4;
const DEFAULT_MAX_FILES = 4;
const DEFAULT_MAX_LINES = 10;
const DEFAULT_MAX_CHARS = 1_600;
const DEFAULT_IDLE_TIMEOUT_MS = 5 * 60_000;
const REAPER_INTERVAL_MS = 60_000;

export interface LspManagerOptions {
	readonly servers?: readonly LspServerSpec[];
	readonly extraBinDirs?: readonly string[];
	readonly maxServers?: number;
	readonly maxFiles?: number;
	readonly maxLines?: number;
	readonly maxChars?: number;
	readonly idleTimeoutMs?: number;
	readonly initTimeoutMs?: number;
	readonly warmWaitMs?: number;
	readonly coldWaitMs?: number;
}

function formatDiagnosticLine(displayPath: string, item: LspDiagnosticItem): string {
	const codeTag = item.code ? ` [${item.source ? `${item.source} ` : ""}${item.code}]` : "";
	return `${displayPath}:${item.line}:${item.column} error${codeTag} ${item.message}`;
}

export function createLspDiagnosticsManager(options?: LspManagerOptions) {
	const servers = options?.servers ?? DEFAULT_LSP_SERVERS;
	const extraBinDirs = options?.extraBinDirs ?? [];
	const maxServers = options?.maxServers ?? DEFAULT_MAX_SERVERS;
	const maxFiles = options?.maxFiles ?? DEFAULT_MAX_FILES;
	const maxLines = options?.maxLines ?? DEFAULT_MAX_LINES;
	const maxChars = options?.maxChars ?? DEFAULT_MAX_CHARS;
	const idleTimeoutMs = options?.idleTimeoutMs ?? DEFAULT_IDLE_TIMEOUT_MS;

	const clients = new Map<string, LspClient>();
	const stopDirCache = new Map<string, string>();
	const binaryCache = new Map<string, string | null>();
	let reaperTimer: ReturnType<typeof setInterval> | undefined;

	const ensureReaper = (): void => {
		if (reaperTimer || idleTimeoutMs <= 0) return;
		reaperTimer = setInterval(() => {
			const now = Date.now();
			for (const [key, client] of clients) {
				if (client.isClosed || now - client.lastActiveAt >= idleTimeoutMs) {
					clients.delete(key);
					void client.shutdown();
				}
			}
			if (clients.size === 0 && reaperTimer) {
				clearInterval(reaperTimer);
				reaperTimer = undefined;
			}
		}, Math.min(REAPER_INTERVAL_MS, Math.max(1_000, Math.floor(idleTimeoutMs / 2))));
		reaperTimer.unref?.();
	};

	const getStopDir = async (cwd: string): Promise<string> => {
		const normalized = resolve(cwd);
		const cached = stopDirCache.get(normalized);
		if (cached) return cached;
		const stopDir = (await findGitRoot(normalized)) ?? normalized;
		stopDirCache.set(normalized, stopDir);
		return stopDir;
	};

	const getBinaryPath = async (spec: LspServerSpec, rootDir: string, stopDir: string): Promise<string | undefined> => {
		const key = `${spec.id}::${rootDir}`;
		if (binaryCache.has(key)) {
			return binaryCache.get(key) ?? undefined;
		}
		const found = await resolveServerBinary(spec.binary, rootDir, stopDir, extraBinDirs);
		binaryCache.set(key, found ?? null);
		return found;
	};

	const evictIfNeeded = async (): Promise<void> => {
		if (clients.size < maxServers) return;
		let oldestKey: string | undefined;
		let oldestTime = Number.POSITIVE_INFINITY;
		for (const [key, client] of clients) {
			if (client.isClosed) {
				clients.delete(key);
				continue;
			}
			if (client.lastActiveAt < oldestTime) {
				oldestTime = client.lastActiveAt;
				oldestKey = key;
			}
		}
		if (clients.size >= maxServers && oldestKey) {
			const victim = clients.get(oldestKey);
			clients.delete(oldestKey);
			await victim?.shutdown();
		}
	};

	const getOrCreateClient = async (workspaceCwd: string, absPath: string): Promise<LspClient | undefined> => {
		const spec = matchServerSpec(absPath, servers);
		if (!spec) return undefined;

		const stopDir = await getStopDir(workspaceCwd);
		const rootDir = await findProjectRoot(dirname(absPath), stopDir, spec.rootMarkers);
		if (!rootDir) return undefined;

		const poolKey = `${spec.id}::${rootDir}`;
		const existing = clients.get(poolKey);
		if (existing && !existing.isClosed) {
			return existing;
		}
		if (existing) {
			clients.delete(poolKey);
		}

		const binaryPath = await getBinaryPath(spec, rootDir, stopDir);
		if (!binaryPath) return undefined;

		await evictIfNeeded();
		const client = new LspClient({
			spec,
			rootDir,
			binaryPath,
			initTimeoutMs: options?.initTimeoutMs,
			warmWaitMs: options?.warmWaitMs,
			coldWaitMs: options?.coldWaitMs,
		});
		clients.set(poolKey, client);
		ensureReaper();
		return client;
	};

	const closeDeletedPaths = (workspaceCwd: string, deletedPaths: readonly string[]): void => {
		for (const raw of deletedPaths) {
			const cleaned = raw.startsWith("@") ? raw.slice(1) : raw;
			const absPath = resolve(workspaceCwd, cleaned);
			for (const client of clients.values()) {
				if (!client.isClosed && isInsideDirectory(client.rootDir, absPath)) {
					client.closeFile(absPath);
				}
			}
		}
	};

	return {
		get activeServerCount(): number {
			let count = 0;
			for (const client of clients.values()) {
				if (!client.isClosed) count++;
			}
			return count;
		},

		async checkFiles(
			workspaceCwd: string,
			modifiedPaths: readonly string[],
			deletedPaths: readonly string[] = [],
		): Promise<string | undefined> {
			if (process.env[LSP_DIAGNOSTICS_DISABLE_ENV] === "0") return undefined;

			if (deletedPaths.length > 0) {
				closeDeletedPaths(workspaceCwd, deletedPaths);
			}

			const normalizedCwd = resolve(workspaceCwd);
			const uniqueAbsPaths = [
				...new Set(
					modifiedPaths
						.map((raw) => (raw.startsWith("@") ? raw.slice(1) : raw))
						.map((p) => resolve(normalizedCwd, p))
						.filter((abs) => isInsideDirectory(normalizedCwd, abs)),
				),
			].slice(0, maxFiles);

			if (uniqueAbsPaths.length === 0) return undefined;

			const allLines: string[] = [];
			await Promise.all(
				uniqueAbsPaths.map(async (absPath) => {
					const client = await getOrCreateClient(normalizedCwd, absPath);
					if (!client) return;
					const items = await client.diagnoseFile(absPath);
					if (items.length === 0) return;

					const rel = relative(normalizedCwd, absPath);
					const displayPath = rel && !rel.startsWith("..") ? rel : absPath;
					for (const item of items) {
						allLines.push(formatDiagnosticLine(displayPath, item));
					}
				}),
			);

			if (allLines.length === 0) return undefined;

			allLines.sort();
			let body = allLines.slice(0, maxLines).join("\n");
			if (allLines.length > maxLines) {
				body += `\n[... ${allLines.length - maxLines} more LSP error lines omitted]`;
			}
			if (body.length > maxChars) {
				body = `${body.slice(0, maxChars)}... [truncated]`;
			}
			return `[LSP Diagnostics]\n${body}`;
		},

		async shutdownAll(): Promise<void> {
			if (reaperTimer) {
				clearInterval(reaperTimer);
				reaperTimer = undefined;
			}
			const list = [...clients.values()];
			clients.clear();
			stopDirCache.clear();
			binaryCache.clear();
			await Promise.all(list.map((client) => client.shutdown()));
		},
	};
}
