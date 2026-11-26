import { type ChildProcess, spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { basename, extname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createJsonRpcConnection } from "./jsonrpc.ts";
import type { LspServerSpec } from "./servers.ts";

export interface LspDiagnosticItem {
	readonly line: number; // 1-indexed
	readonly column: number; // 1-indexed
	readonly severity: number; // 1 = Error, 2 = Warning, 3 = Info, 4 = Hint
	readonly code?: string;
	readonly source?: string;
	readonly message: string;
}

export interface LspLocation {
	readonly absPath: string;
	readonly line: number; // 1-indexed
	readonly column: number; // 1-indexed
}

export interface LspSymbolItem {
	readonly name: string;
	readonly kind: string;
	readonly line: number; // 1-indexed
	readonly endLine: number; // 1-indexed
	readonly depth: number;
	readonly container?: string;
}

interface RawLspRange {
	readonly start?: { readonly line?: number; readonly character?: number };
	readonly end?: { readonly line?: number; readonly character?: number };
}

interface RawLspDiagnostic {
	readonly range?: RawLspRange;
	readonly severity?: number;
	readonly code?: string | number | { readonly value?: string | number };
	readonly source?: string;
	readonly message?: string;
}

interface RawLocation {
	readonly uri?: string;
	readonly range?: RawLspRange;
	readonly targetUri?: string;
	readonly targetSelectionRange?: RawLspRange;
	readonly targetRange?: RawLspRange;
}

interface RawDocumentSymbol {
	readonly name?: string;
	readonly kind?: number;
	readonly range?: RawLspRange;
	readonly selectionRange?: RawLspRange;
	readonly children?: readonly RawDocumentSymbol[];
	// SymbolInformation shape
	readonly location?: RawLocation;
	readonly containerName?: string;
}

interface PublishDiagnosticsParams {
	readonly uri?: string;
	readonly version?: number;
	readonly diagnostics?: readonly RawLspDiagnostic[];
}

interface DiagnosticWaiter {
	readonly expectedVersion: number;
	latest: LspDiagnosticItem[] | undefined;
	settleTimer: ReturnType<typeof setTimeout> | undefined;
	readonly hardTimer: ReturnType<typeof setTimeout>;
	readonly resolve: (items: LspDiagnosticItem[]) => void;
}

interface OpenDocumentState {
	version: number;
	text: string;
}

type ClientState = "starting" | "ready" | "closed";

const DEFAULT_INIT_TIMEOUT_MS = 6_000;
const DEFAULT_WARM_WAIT_MS = 2_000;
const DEFAULT_COLD_WAIT_MS = 4_000;
const DEFAULT_NAV_TIMEOUT_MS = 5_000;
const VERSIONLESS_NONEMPTY_SETTLE_MS = 120;
const VERSIONLESS_EMPTY_SETTLE_MS = 300;
const SHUTDOWN_TIMEOUT_MS = 500;

const SYMBOL_KIND_NAMES: Record<number, string> = {
	1: "file",
	2: "module",
	3: "namespace",
	4: "package",
	5: "class",
	6: "method",
	7: "property",
	8: "field",
	9: "constructor",
	10: "enum",
	11: "interface",
	12: "function",
	13: "variable",
	14: "constant",
	15: "string",
	16: "number",
	17: "boolean",
	18: "array",
	19: "object",
	20: "key",
	21: "null",
	22: "enumMember",
	23: "struct",
	24: "event",
	25: "operator",
	26: "typeParam",
};

function normalizeUriToPath(uri: string): string | undefined {
	try {
		if (uri.startsWith("file://")) {
			return resolve(fileURLToPath(uri));
		}
		return resolve(uri);
	} catch {
		return undefined;
	}
}

function normalizeDiagnosticCode(code: RawLspDiagnostic["code"]): string | undefined {
	if (typeof code === "string" || typeof code === "number") {
		return String(code);
	}
	if (code && typeof code === "object" && (typeof code.value === "string" || typeof code.value === "number")) {
		return String(code.value);
	}
	return undefined;
}

function parseErrorDiagnostics(rawList: readonly RawLspDiagnostic[] | undefined): LspDiagnosticItem[] {
	if (!Array.isArray(rawList)) return [];
	const items: LspDiagnosticItem[] = [];
	for (const raw of rawList) {
		// Strictly errors only (severity 1); skip warnings/info/hints.
		if (raw.severity !== 1) continue;
		const message = typeof raw.message === "string" ? raw.message.replace(/\s+/g, " ").trim() : "";
		if (!message) continue;
		items.push({
			line: (raw.range?.start?.line ?? 0) + 1,
			column: (raw.range?.start?.character ?? 0) + 1,
			severity: 1,
			code: normalizeDiagnosticCode(raw.code),
			source: typeof raw.source === "string" ? raw.source : undefined,
			message,
		});
	}
	items.sort((a, b) => a.line - b.line || a.column - b.column);
	return items;
}

function parseLocations(raw: unknown): LspLocation[] {
	if (!raw) return [];
	const list: RawLocation[] = Array.isArray(raw) ? (raw as RawLocation[]) : [raw as RawLocation];
	const results: LspLocation[] = [];
	const seen = new Set<string>();

	for (const item of list) {
		if (!item || typeof item !== "object") continue;
		const uri = item.targetUri ?? item.uri;
		const range = item.targetSelectionRange ?? item.targetRange ?? item.range;
		if (!uri || !range?.start) continue;
		const absPath = normalizeUriToPath(uri);
		if (!absPath) continue;
		const line = (range.start.line ?? 0) + 1;
		const column = (range.start.character ?? 0) + 1;
		const key = `${absPath}:${line}:${column}`;
		if (seen.has(key)) continue;
		seen.add(key);
		results.push({ absPath, line, column });
	}

	results.sort((a, b) => a.absPath.localeCompare(b.absPath) || a.line - b.line || a.column - b.column);
	return results;
}

function parseHoverText(raw: unknown): string | undefined {
	if (!raw || typeof raw !== "object") return undefined;
	const contents = (raw as { contents?: unknown }).contents;
	if (!contents) return undefined;

	const extractPart = (part: unknown): string => {
		if (typeof part === "string") return part;
		if (part && typeof part === "object") {
			const obj = part as { value?: unknown; language?: unknown };
			if (typeof obj.value === "string") return obj.value;
		}
		return "";
	};

	const rawText = Array.isArray(contents) ? contents.map(extractPart).filter(Boolean).join("\n") : extractPart(contents);
	const cleaned = rawText
		.replace(/\r\n?/g, "\n")
		.replace(/^```[\w-]*\n/gm, "")
		.replace(/^```\s*$/gm, "")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
	return cleaned || undefined;
}

function parseDocumentSymbols(raw: unknown): LspSymbolItem[] {
	if (!Array.isArray(raw)) return [];
	const items: LspSymbolItem[] = [];

	const walk = (nodes: readonly RawDocumentSymbol[], depth: number): void => {
		for (const node of nodes) {
			if (!node || typeof node !== "object" || typeof node.name !== "string") continue;
			const kind = SYMBOL_KIND_NAMES[node.kind ?? 0] ?? "symbol";

			if (node.location?.range?.start) {
				const line = (node.location.range.start.line ?? 0) + 1;
				const endLine = (node.location.range.end?.line ?? line - 1) + 1;
				items.push({
					name: node.name,
					kind,
					line,
					endLine,
					depth,
					container: node.containerName,
				});
				continue;
			}

			const range = node.range ?? node.selectionRange;
			if (!range?.start) continue;
			const line = (range.start.line ?? 0) + 1;
			const endLine = (range.end?.line ?? line - 1) + 1;
			items.push({ name: node.name, kind, line, endLine, depth });
			if (Array.isArray(node.children) && node.children.length > 0) {
				walk(node.children, depth + 1);
			}
		}
	};

	walk(raw as readonly RawDocumentSymbol[], 0);
	return items;
}

export class LspClient {
	readonly spec: LspServerSpec;
	readonly rootDir: string;
	readonly binaryPath: string;

	private state: ClientState = "starting";
	private child: ChildProcess | undefined;
	private rpc: ReturnType<typeof createJsonRpcConnection> | undefined;
	private startupPromise: Promise<boolean> | undefined;
	private readonly openDocs = new Map<string, OpenDocumentState>();
	private readonly waiters = new Map<string, DiagnosticWaiter>();
	private lastUsedAtMs = Date.now();
	private hasCompletedFirstDiagnose = false;

	private readonly initTimeoutMs: number;
	private readonly warmWaitMs: number;
	private readonly coldWaitMs: number;
	private readonly navTimeoutMs: number;

	constructor(options: {
		readonly spec: LspServerSpec;
		readonly rootDir: string;
		readonly binaryPath: string;
		readonly initTimeoutMs?: number;
		readonly warmWaitMs?: number;
		readonly coldWaitMs?: number;
		readonly navTimeoutMs?: number;
	}) {
		this.spec = options.spec;
		this.rootDir = resolve(options.rootDir);
		this.binaryPath = options.binaryPath;
		this.initTimeoutMs = options.initTimeoutMs ?? DEFAULT_INIT_TIMEOUT_MS;
		this.warmWaitMs = options.warmWaitMs ?? DEFAULT_WARM_WAIT_MS;
		this.coldWaitMs = options.coldWaitMs ?? DEFAULT_COLD_WAIT_MS;
		this.navTimeoutMs = options.navTimeoutMs ?? DEFAULT_NAV_TIMEOUT_MS;
	}

	get isClosed(): boolean {
		return this.state === "closed";
	}

	get lastActiveAt(): number {
		return this.lastUsedAtMs;
	}

	private finishWaiter(absPath: string, items: LspDiagnosticItem[]): void {
		const waiter = this.waiters.get(absPath);
		if (!waiter) return;
		this.waiters.delete(absPath);
		if (waiter.settleTimer) clearTimeout(waiter.settleTimer);
		clearTimeout(waiter.hardTimer);
		waiter.resolve(items);
	}

	private handlePublishDiagnostics(params: PublishDiagnosticsParams | undefined): void {
		if (!params?.uri) return;
		const absPath = normalizeUriToPath(params.uri);
		if (!absPath) return;

		const waiter = this.waiters.get(absPath);
		if (!waiter) return;

		// Ignore diagnostics from an older document revision.
		if (typeof params.version === "number" && params.version < waiter.expectedVersion) {
			return;
		}

		const errors = parseErrorDiagnostics(params.diagnostics);
		waiter.latest = errors;

		if (typeof params.version === "number" && params.version === waiter.expectedVersion) {
			this.finishWaiter(absPath, errors);
			return;
		}

		if (waiter.settleTimer) clearTimeout(waiter.settleTimer);
		const delay = errors.length > 0 ? VERSIONLESS_NONEMPTY_SETTLE_MS : VERSIONLESS_EMPTY_SETTLE_MS;
		waiter.settleTimer = setTimeout(() => {
			this.finishWaiter(absPath, waiter.latest ?? []);
		}, delay);
		waiter.settleTimer.unref?.();
	}

	private handleServerRequest(method: string, params: unknown): unknown {
		if (method === "workspace/configuration") {
			const items = (params as { items?: unknown[] } | undefined)?.items;
			return Array.isArray(items) ? items.map(() => ({})) : [{}];
		}
		if (method === "workspace/workspaceFolders") {
			return [{ uri: pathToFileURL(this.rootDir).href, name: basename(this.rootDir) }];
		}
		// client/registerCapability, window/workDoneProgress/create, etc.
		return null;
	}

	private markClosed(): void {
		if (this.state === "closed") return;
		this.state = "closed";
		for (const [absPath, waiter] of this.waiters) {
			this.finishWaiter(absPath, waiter.latest ?? []);
		}
		this.waiters.clear();
		this.openDocs.clear();
		this.rpc?.dispose();
		this.rpc = undefined;
	}

	async ensureReady(): Promise<boolean> {
		if (this.state === "ready") return true;
		if (this.state === "closed") return false;
		if (this.startupPromise) return this.startupPromise;

		this.startupPromise = (async () => {
			try {
				const child = spawn(this.binaryPath, [...this.spec.args], {
					cwd: this.rootDir,
					stdio: ["pipe", "pipe", "pipe"],
					windowsHide: true,
				});
				this.child = child;
				// Drain stderr so the OS pipe buffer never fills and stalls the LSP server.
				child.stderr?.resume();

				if (!child.stdout || !child.stdin) {
					this.markClosed();
					return false;
				}

				const rpc = createJsonRpcConnection({
					readable: child.stdout,
					writable: child.stdin,
					onNotification: (method, params) => {
						if (method === "textDocument/publishDiagnostics") {
							this.handlePublishDiagnostics(params as PublishDiagnosticsParams | undefined);
						}
					},
					onRequest: (method, params) => this.handleServerRequest(method, params),
					onClose: () => this.markClosed(),
				});
				this.rpc = rpc;

				child.once("error", () => this.markClosed());
				child.once("exit", () => this.markClosed());

				const rootUri = pathToFileURL(this.rootDir).href;
				await rpc.request(
					"initialize",
					{
						processId: process.pid,
						clientInfo: { name: "pi-lsp-diagnostics", version: "1.1.0" },
						rootPath: this.rootDir,
						rootUri,
						workspaceFolders: [{ uri: rootUri, name: basename(this.rootDir) }],
						capabilities: {
							general: { positionEncodings: ["utf-16"] },
							workspace: {
								workspaceFolders: true,
								configuration: true,
							},
							textDocument: {
								synchronization: {
									didSave: true,
									dynamicRegistration: false,
								},
								publishDiagnostics: {
									versionSupport: true,
								},
								definition: { linkSupport: true },
								references: {},
								hover: { contentFormat: ["plaintext", "markdown"] },
								documentSymbol: { hierarchicalDocumentSymbolSupport: true },
							},
						},
					},
					this.initTimeoutMs,
				);

				if (this.state === "closed") return false;
				rpc.notify("initialized", {});
				this.state = "ready";
				this.lastUsedAtMs = Date.now();
				return true;
			} catch {
				await this.shutdown();
				return false;
			}
		})();

		return this.startupPromise;
	}

	private async syncDocument(
		absPath: string,
		forceRepublish: boolean,
	): Promise<{ uri: string; text: string; version: number } | undefined> {
		const normalized = resolve(absPath);
		const ready = await this.ensureReady();
		if (!ready || !this.rpc || this.state !== "ready") return undefined;

		let text: string;
		try {
			text = await readFile(normalized, "utf-8");
		} catch {
			return undefined;
		}

		const uri = pathToFileURL(normalized).href;
		const existing = this.openDocs.get(normalized);

		if (!existing) {
			const nextVersion = 1;
			this.openDocs.set(normalized, { version: nextVersion, text });
			const ext = extname(normalized).toLowerCase();
			this.rpc.notify("textDocument/didOpen", {
				textDocument: {
					uri,
					languageId: this.spec.languageIdForExtension(ext),
					version: nextVersion,
					text,
				},
			});
			if (forceRepublish) {
				this.rpc.notify("textDocument/didSave", { textDocument: { uri }, text });
			}
			return { uri, text, version: nextVersion };
		}

		if (existing.text === text && !forceRepublish) {
			return { uri, text, version: existing.version };
		}

		const nextVersion = existing.version + 1;
		existing.version = nextVersion;
		existing.text = text;
		this.rpc.notify("textDocument/didChange", {
			textDocument: { uri, version: nextVersion },
			contentChanges: [{ text }],
		});
		if (forceRepublish) {
			this.rpc.notify("textDocument/didSave", { textDocument: { uri }, text });
		}
		return { uri, text, version: nextVersion };
	}

	async diagnoseFile(absPath: string): Promise<LspDiagnosticItem[]> {
		const normalized = resolve(absPath);
		this.lastUsedAtMs = Date.now();

		const ready = await this.ensureReady();
		if (!ready || !this.rpc || this.state !== "ready") return [];

		let text: string;
		try {
			text = await readFile(normalized, "utf-8");
		} catch {
			return [];
		}

		const uri = pathToFileURL(normalized).href;
		const existing = this.openDocs.get(normalized);
		const nextVersion = (existing?.version ?? 0) + 1;

		// Cancel any superseded waiter for the same file before registering a new one.
		if (this.waiters.has(normalized)) {
			this.finishWaiter(normalized, []);
		}

		const waitMs = this.hasCompletedFirstDiagnose ? this.warmWaitMs : this.coldWaitMs;
		const resultPromise = new Promise<LspDiagnosticItem[]>((resolvePromise) => {
			const hardTimer = setTimeout(() => {
				const active = this.waiters.get(normalized);
				this.finishWaiter(normalized, active?.latest ?? []);
			}, waitMs);
			hardTimer.unref?.();

			this.waiters.set(normalized, {
				expectedVersion: nextVersion,
				latest: undefined,
				settleTimer: undefined,
				hardTimer,
				resolve: resolvePromise,
			});
		});

		this.openDocs.set(normalized, { version: nextVersion, text });
		if (!existing) {
			const ext = extname(normalized).toLowerCase();
			this.rpc.notify("textDocument/didOpen", {
				textDocument: {
					uri,
					languageId: this.spec.languageIdForExtension(ext),
					version: nextVersion,
					text,
				},
			});
		} else {
			this.rpc.notify("textDocument/didChange", {
				textDocument: { uri, version: nextVersion },
				contentChanges: [{ text }],
			});
		}
		this.rpc.notify("textDocument/didSave", {
			textDocument: { uri },
			text,
		});

		const items = await resultPromise;
		this.hasCompletedFirstDiagnose = true;
		this.lastUsedAtMs = Date.now();
		return items;
	}

	async definition(absPath: string, line0: number, char0: number): Promise<LspLocation[]> {
		this.lastUsedAtMs = Date.now();
		if (!this.hasCompletedFirstDiagnose) {
			await this.diagnoseFile(absPath);
		}
		const synced = await this.syncDocument(absPath, false);
		if (!synced || !this.rpc || this.state !== "ready") return [];
		try {
			const raw = await this.rpc.request(
				"textDocument/definition",
				{ textDocument: { uri: synced.uri }, position: { line: line0, character: char0 } },
				this.navTimeoutMs,
			);
			this.lastUsedAtMs = Date.now();
			return parseLocations(raw);
		} catch {
			return [];
		}
	}

	async references(absPath: string, line0: number, char0: number, includeDeclaration = true): Promise<LspLocation[]> {
		this.lastUsedAtMs = Date.now();
		if (!this.hasCompletedFirstDiagnose) {
			await this.diagnoseFile(absPath);
		}
		const synced = await this.syncDocument(absPath, false);
		if (!synced || !this.rpc || this.state !== "ready") return [];
		try {
			const raw = await this.rpc.request(
				"textDocument/references",
				{
					textDocument: { uri: synced.uri },
					position: { line: line0, character: char0 },
					context: { includeDeclaration },
				},
				this.navTimeoutMs,
			);
			this.lastUsedAtMs = Date.now();
			return parseLocations(raw);
		} catch {
			return [];
		}
	}

	async hover(absPath: string, line0: number, char0: number): Promise<string | undefined> {
		this.lastUsedAtMs = Date.now();
		if (!this.hasCompletedFirstDiagnose) {
			await this.diagnoseFile(absPath);
		}
		const synced = await this.syncDocument(absPath, false);
		if (!synced || !this.rpc || this.state !== "ready") return undefined;
		try {
			const raw = await this.rpc.request(
				"textDocument/hover",
				{ textDocument: { uri: synced.uri }, position: { line: line0, character: char0 } },
				this.navTimeoutMs,
			);
			this.lastUsedAtMs = Date.now();
			return parseHoverText(raw);
		} catch {
			return undefined;
		}
	}

	async documentSymbols(absPath: string): Promise<LspSymbolItem[]> {
		this.lastUsedAtMs = Date.now();
		if (!this.hasCompletedFirstDiagnose) {
			await this.diagnoseFile(absPath);
		}
		const synced = await this.syncDocument(absPath, false);
		if (!synced || !this.rpc || this.state !== "ready") return [];
		try {
			const raw = await this.rpc.request(
				"textDocument/documentSymbol",
				{ textDocument: { uri: synced.uri } },
				this.navTimeoutMs,
			);
			this.lastUsedAtMs = Date.now();
			return parseDocumentSymbols(raw);
		} catch {
			return [];
		}
	}

	closeFile(absPath: string): void {
		const normalized = resolve(absPath);
		if (!this.openDocs.has(normalized)) return;
		this.openDocs.delete(normalized);
		this.finishWaiter(normalized, []);
		if (this.rpc && this.state === "ready") {
			this.rpc.notify("textDocument/didClose", {
				textDocument: { uri: pathToFileURL(normalized).href },
			});
		}
	}

	async shutdown(): Promise<void> {
		const rpc = this.rpc;
		const child = this.child;
		if (rpc && this.state === "ready") {
			try {
				await rpc.request("shutdown", null, SHUTDOWN_TIMEOUT_MS);
				rpc.notify("exit");
			} catch {
				// Best-effort graceful shutdown before SIGTERM.
			}
		}
		this.markClosed();
		if (child) {
			child.stdin?.destroy();
			child.stdout?.destroy();
			child.stderr?.destroy();
			if (!child.killed && child.exitCode === null) {
				try {
					child.kill("SIGTERM");
				} catch {
					// Already exited.
				}
			}
			child.unref();
		}
		this.child = undefined;
	}
}
