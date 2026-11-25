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

interface RawLspDiagnostic {
	readonly range?: {
		readonly start?: { readonly line?: number; readonly character?: number };
	};
	readonly severity?: number;
	readonly code?: string | number | { readonly value?: string | number };
	readonly source?: string;
	readonly message?: string;
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

type ClientState = "starting" | "ready" | "closed";

const DEFAULT_INIT_TIMEOUT_MS = 6_000;
const DEFAULT_WARM_WAIT_MS = 2_000;
const DEFAULT_COLD_WAIT_MS = 4_000;
const VERSIONLESS_NONEMPTY_SETTLE_MS = 120;
const VERSIONLESS_EMPTY_SETTLE_MS = 300;
const SHUTDOWN_TIMEOUT_MS = 500;

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

export class LspClient {
	readonly spec: LspServerSpec;
	readonly rootDir: string;
	readonly binaryPath: string;

	private state: ClientState = "starting";
	private child: ChildProcess | undefined;
	private rpc: ReturnType<typeof createJsonRpcConnection> | undefined;
	private startupPromise: Promise<boolean> | undefined;
	private readonly openVersions = new Map<string, number>();
	private readonly waiters = new Map<string, DiagnosticWaiter>();
	private lastUsedAtMs = Date.now();
	private hasCompletedFirstDiagnose = false;

	private readonly initTimeoutMs: number;
	private readonly warmWaitMs: number;
	private readonly coldWaitMs: number;

	constructor(options: {
		readonly spec: LspServerSpec;
		readonly rootDir: string;
		readonly binaryPath: string;
		readonly initTimeoutMs?: number;
		readonly warmWaitMs?: number;
		readonly coldWaitMs?: number;
	}) {
		this.spec = options.spec;
		this.rootDir = resolve(options.rootDir);
		this.binaryPath = options.binaryPath;
		this.initTimeoutMs = options.initTimeoutMs ?? DEFAULT_INIT_TIMEOUT_MS;
		this.warmWaitMs = options.warmWaitMs ?? DEFAULT_WARM_WAIT_MS;
		this.coldWaitMs = options.coldWaitMs ?? DEFAULT_COLD_WAIT_MS;
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
		this.openVersions.clear();
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
						clientInfo: { name: "pi-lsp-diagnostics", version: "1.0.0" },
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
		const previousVersion = this.openVersions.get(normalized);
		const nextVersion = (previousVersion ?? 0) + 1;
		this.openVersions.set(normalized, nextVersion);

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

		if (previousVersion === undefined) {
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

	closeFile(absPath: string): void {
		const normalized = resolve(absPath);
		if (!this.openVersions.has(normalized)) return;
		this.openVersions.delete(normalized);
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
		if (child && !child.killed && child.exitCode === null) {
			try {
				child.kill("SIGTERM");
			} catch {
				// Already exited.
			}
		}
		this.child = undefined;
	}
}
