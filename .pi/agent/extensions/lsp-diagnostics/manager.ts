import { readFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { LspClient, type LspDiagnosticItem, type LspLocation, type LspSymbolItem } from "./client.ts";
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

const MAX_NAV_LOCATIONS = 30;
const MAX_NAV_SYMBOLS = 60;
const MAX_NAV_CHARS = 2_400;
const MAX_SNIPPET_CHARS = 120;

export type LspNavigationAction = "definition" | "references" | "hover" | "symbols";

export interface LspNavigationRequest {
	readonly action: LspNavigationAction;
	readonly path: string;
	readonly line?: number; // 1-indexed
	readonly column?: number; // 1-indexed
	readonly symbol?: string;
}

export interface LspCheckResult {
	readonly block?: string;
	readonly errorsByFile: Map<string, string[]>;
}

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
	readonly navTimeoutMs?: number;
}

function formatDiagnosticLine(displayPath: string, item: LspDiagnosticItem): string {
	const codeTag = item.code ? ` [${item.source ? `${item.source} ` : ""}${item.code}]` : "";
	return `${displayPath}:${item.line}:${item.column} error${codeTag} ${item.message}`;
}

function formatDisplayPath(workspaceCwd: string, absPath: string): string {
	const rel = relative(workspaceCwd, absPath);
	return rel && !rel.startsWith("..") ? rel : absPath;
}

function escapeRegex(text: string): string {
	return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Resolve 0-indexed column on a 1-indexed line, honoring explicit column, symbol lookup,
 * or first non-whitespace token when neither is given.
 */
export function resolveLineColumn0(lineText: string, column1?: number, symbol?: string): number {
	if (typeof column1 === "number" && Number.isFinite(column1) && column1 >= 1) {
		return Math.min(Math.max(0, Math.floor(column1) - 1), Math.max(0, lineText.length));
	}
	if (symbol?.trim()) {
		const needle = symbol.trim();
		const wordRe = new RegExp(`(?<![A-Za-z0-9_$])${escapeRegex(needle)}(?![A-Za-z0-9_$])`);
		const wordMatch = wordRe.exec(lineText);
		if (wordMatch) return wordMatch.index;
		const plainIdx = lineText.indexOf(needle);
		if (plainIdx !== -1) return plainIdx;
	}
	const nonWs = lineText.search(/\S/);
	return nonWs === -1 ? 0 : nonWs;
}

async function formatLocationLines(
	workspaceCwd: string,
	locations: readonly LspLocation[],
): Promise<string[]> {
	const fileCache = new Map<string, string[] | null>();
	const getLineText = async (absPath: string, line1: number): Promise<string | undefined> => {
		let lines = fileCache.get(absPath);
		if (lines === undefined) {
			try {
				const raw = await readFile(absPath, "utf-8");
				lines = raw.replace(/\r\n?/g, "\n").split("\n");
			} catch {
				lines = null;
			}
			fileCache.set(absPath, lines);
		}
		const line = lines?.[line1 - 1]?.trim();
		if (!line) return undefined;
		return line.length > MAX_SNIPPET_CHARS ? `${line.slice(0, MAX_SNIPPET_CHARS)}...` : line;
	};

	const shown = locations.slice(0, MAX_NAV_LOCATIONS);
	const formatted: string[] = [];
	for (const loc of shown) {
		const display = formatDisplayPath(workspaceCwd, loc.absPath);
		const snippet = await getLineText(loc.absPath, loc.line);
		formatted.push(snippet ? `${display}:${loc.line}:${loc.column}: ${snippet}` : `${display}:${loc.line}:${loc.column}`);
	}
	if (locations.length > MAX_NAV_LOCATIONS) {
		formatted.push(`[... ${locations.length - MAX_NAV_LOCATIONS} more locations omitted]`);
	}
	return formatted;
}

function formatSymbolLines(symbols: readonly LspSymbolItem[]): string[] {
	const shown = symbols.slice(0, MAX_NAV_SYMBOLS);
	const lines = shown.map((sym) => {
		const indent = "  ".repeat(Math.min(sym.depth, 4));
		const range = sym.endLine > sym.line ? `L${sym.line}-${sym.endLine}` : `L${sym.line}`;
		const container = sym.container ? ` (${sym.container})` : "";
		return `${indent}${range} ${sym.kind} ${sym.name}${container}`;
	});
	if (symbols.length > MAX_NAV_SYMBOLS) {
		lines.push(`[... ${symbols.length - MAX_NAV_SYMBOLS} more symbols omitted]`);
	}
	return lines;
}

function clampNavOutput(text: string): string {
	if (text.length <= MAX_NAV_CHARS) return text;
	return `${text.slice(0, MAX_NAV_CHARS)}\n... [truncated]`;
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
	const pendingClients = new Map<string, Promise<LspClient | undefined>>();
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

		// Serialize concurrent cold starts for the same server/root so multi-file edits
		// never spawn duplicate LSP processes or orphan a handle from shutdownAll().
		const inFlight = pendingClients.get(poolKey);
		if (inFlight) {
			return inFlight;
		}

		const createPromise = (async (): Promise<LspClient | undefined> => {
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
				navTimeoutMs: options?.navTimeoutMs,
			});
			clients.set(poolKey, client);
			ensureReaper();
			return client;
		})();

		pendingClients.set(poolKey, createPromise);
		try {
			return await createPromise;
		} finally {
			if (pendingClients.get(poolKey) === createPromise) {
				pendingClients.delete(poolKey);
			}
		}
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

	const checkFilesDetailed = async (
		workspaceCwd: string,
		modifiedPaths: readonly string[],
		deletedPaths: readonly string[] = [],
	): Promise<LspCheckResult> => {
		const errorsByFile = new Map<string, string[]>();
		if (process.env[LSP_DIAGNOSTICS_DISABLE_ENV] === "0") {
			return { errorsByFile };
		}

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

		if (uniqueAbsPaths.length === 0) {
			return { errorsByFile };
		}

		const allLines: string[] = [];
		await Promise.all(
			uniqueAbsPaths.map(async (absPath) => {
				const client = await getOrCreateClient(normalizedCwd, absPath);
				if (!client) return;
				const items = await client.diagnoseFile(absPath);
				if (items.length === 0) return;

				const displayPath = formatDisplayPath(normalizedCwd, absPath);
				const fileLines = items.map((item) => formatDiagnosticLine(displayPath, item));
				errorsByFile.set(absPath, fileLines);
				allLines.push(...fileLines);
			}),
		);

		if (allLines.length === 0) {
			return { errorsByFile };
		}

		allLines.sort();
		let body = allLines.slice(0, maxLines).join("\n");
		if (allLines.length > maxLines) {
			body += `\n[... ${allLines.length - maxLines} more LSP error lines omitted]`;
		}
		if (body.length > maxChars) {
			body = `${body.slice(0, maxChars)}... [truncated]`;
		}
		return { block: `[LSP Diagnostics]\n${body}`, errorsByFile };
	};

	return {
		get activeServerCount(): number {
			let count = 0;
			for (const client of clients.values()) {
				if (!client.isClosed) count++;
			}
			return count;
		},

		checkFilesDetailed,

		async checkFiles(
			workspaceCwd: string,
			modifiedPaths: readonly string[],
			deletedPaths: readonly string[] = [],
		): Promise<string | undefined> {
			const { block } = await checkFilesDetailed(workspaceCwd, modifiedPaths, deletedPaths);
			return block;
		},

		async queryNavigation(workspaceCwd: string, req: LspNavigationRequest): Promise<string> {
			const normalizedCwd = resolve(workspaceCwd);
			const cleaned = req.path.startsWith("@") ? req.path.slice(1) : req.path;
			const absPath = resolve(normalizedCwd, cleaned);
			const displayPath = formatDisplayPath(normalizedCwd, absPath);

			if (!isInsideDirectory(normalizedCwd, absPath)) {
				return `Path '${displayPath}' is outside the current workspace.`;
			}

			const client = await getOrCreateClient(normalizedCwd, absPath);
			if (!client) {
				return `No LSP server available for '${displayPath}' (requires a configured project root such as tsconfig.json, pyproject.toml, Cargo.toml, or go.mod). Use grep/read instead.`;
			}

			if (req.action === "symbols") {
				const symbols = await client.documentSymbols(absPath);
				if (symbols.length === 0) {
					return `No symbols returned by LSP for '${displayPath}'.`;
				}
				return clampNavOutput(`Symbols in ${displayPath}:\n${formatSymbolLines(symbols).join("\n")}`);
			}

			if (typeof req.line !== "number" || !Number.isFinite(req.line) || req.line < 1) {
				return `Action '${req.action}' requires a 1-indexed 'line' parameter.`;
			}

			let fileLines: string[];
			try {
				const raw = await readFile(absPath, "utf-8");
				fileLines = raw.replace(/\r\n?/g, "\n").split("\n");
			} catch {
				return `Cannot read file '${displayPath}'.`;
			}

			const line1 = Math.floor(req.line);
			const lineText = fileLines[line1 - 1];
			if (lineText === undefined) {
				return `Line ${line1} is out of range for '${displayPath}' (${fileLines.length} lines).`;
			}
			const line0 = line1 - 1;
			const char0 = resolveLineColumn0(lineText, req.column, req.symbol);

			if (req.action === "hover") {
				const hover = await client.hover(absPath, line0, char0);
				if (!hover) {
					return `No hover info at ${displayPath}:${line1}:${char0 + 1}.`;
				}
				return clampNavOutput(hover);
			}

			if (req.action === "definition") {
				const locs = await client.definition(absPath, line0, char0);
				if (locs.length === 0) {
					return `No definition found at ${displayPath}:${line1}:${char0 + 1}.`;
				}
				const lines = await formatLocationLines(normalizedCwd, locs);
				return clampNavOutput(lines.join("\n"));
			}

			const refs = await client.references(absPath, line0, char0, true);
			if (refs.length === 0) {
				return `No references found at ${displayPath}:${line1}:${char0 + 1}.`;
			}
			const lines = await formatLocationLines(normalizedCwd, refs);
			return clampNavOutput(`References (${refs.length}):\n${lines.join("\n")}`);
		},

		async shutdownAll(): Promise<void> {
			if (reaperTimer) {
				clearInterval(reaperTimer);
				reaperTimer = undefined;
			}
			const pending = [...pendingClients.values()];
			pendingClients.clear();
			const createdDuringShutdown = (await Promise.allSettled(pending))
				.filter((r): r is PromiseFulfilledResult<LspClient | undefined> => r.status === "fulfilled")
				.map((r) => r.value)
				.filter((c): c is LspClient => Boolean(c));
			const list = [...new Set([...clients.values(), ...createdDuringShutdown])];
			clients.clear();
			stopDirCache.clear();
			binaryCache.clear();
			await Promise.all(list.map((client) => client.shutdown()));
		},
	};
}
