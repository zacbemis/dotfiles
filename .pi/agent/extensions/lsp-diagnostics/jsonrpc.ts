import type { Readable, Writable } from "node:stream";

export interface JsonRpcMessage {
	readonly jsonrpc: "2.0";
	readonly id?: number | string;
	readonly method?: string;
	readonly params?: unknown;
	readonly result?: unknown;
	readonly error?: { readonly code: number; readonly message: string; readonly data?: unknown };
}

interface PendingRequest {
	readonly resolve: (value: unknown) => void;
	readonly reject: (reason: Error) => void;
	readonly timer: ReturnType<typeof setTimeout>;
}

const HEADER_SEPARATOR = Buffer.from("\r\n\r\n");

export function createJsonRpcConnection(options: {
	readonly readable: Readable;
	readonly writable: Writable;
	readonly onNotification?: (method: string, params: unknown) => void;
	readonly onRequest?: (method: string, params: unknown) => unknown | Promise<unknown>;
	readonly onClose?: (error?: Error) => void;
}) {
	let nextId = 1;
	let disposed = false;
	let buffer = Buffer.alloc(0);
	const pending = new Map<number, PendingRequest>();

	const writeMessage = (payload: Record<string, unknown>): void => {
		if (disposed || options.writable.destroyed) return;
		const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...payload }), "utf-8");
		const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
		try {
			options.writable.write(Buffer.concat([header, body]));
		} catch {
			// Ignore broken pipe writes during shutdown.
		}
	};

	const handleParsedMessage = (msg: JsonRpcMessage): void => {
		if (msg.method !== undefined && msg.id !== undefined) {
			Promise.resolve()
				.then(() => options.onRequest?.(msg.method!, msg.params))
				.then(
					(result) => {
						writeMessage({ id: msg.id, result: result === undefined ? null : result });
					},
					(err) => {
						writeMessage({
							id: msg.id,
							error: { code: -32603, message: err instanceof Error ? err.message : String(err) },
						});
					},
				);
			return;
		}

		if (msg.method !== undefined) {
			try {
				options.onNotification?.(msg.method, msg.params);
			} catch {
				// Never let notification handler throw into stream loop.
			}
			return;
		}

		if (typeof msg.id === "number") {
			const entry = pending.get(msg.id);
			if (!entry) return;
			pending.delete(msg.id);
			clearTimeout(entry.timer);
			if (msg.error) {
				entry.reject(new Error(`LSP error ${msg.error.code}: ${msg.error.message}`));
			} else {
				entry.resolve(msg.result);
			}
		}
	};

	const drainBuffer = (): void => {
		while (true) {
			const headerEnd = buffer.indexOf(HEADER_SEPARATOR);
			if (headerEnd === -1) return;

			const headerText = buffer.subarray(0, headerEnd).toString("ascii");
			const match = /content-length\s*:\s*(\d+)/i.exec(headerText);
			if (!match) {
				// Discard malformed header preamble and continue scanning.
				buffer = buffer.subarray(headerEnd + HEADER_SEPARATOR.length);
				continue;
			}

			const contentLength = Number.parseInt(match[1]!, 10);
			const bodyStart = headerEnd + HEADER_SEPARATOR.length;
			const frameEnd = bodyStart + contentLength;
			if (buffer.length < frameEnd) return;

			const bodySlice = buffer.subarray(bodyStart, frameEnd).toString("utf-8");
			buffer = buffer.subarray(frameEnd);

			try {
				const parsed = JSON.parse(bodySlice) as JsonRpcMessage;
				handleParsedMessage(parsed);
			} catch {
				// Ignore malformed JSON frames.
			}
		}
	};

	const dispose = (reason?: Error): void => {
		if (disposed) return;
		disposed = true;
		const err = reason ?? new Error("LSP JSON-RPC connection closed");
		for (const [, entry] of pending) {
			clearTimeout(entry.timer);
			entry.reject(err);
		}
		pending.clear();
		options.onClose?.(reason);
	};

	options.readable.on("data", (chunk: Buffer | string) => {
		if (disposed) return;
		const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, "utf-8");
		buffer = buffer.length === 0 ? buf : Buffer.concat([buffer, buf]);
		drainBuffer();
	});

	options.readable.on("error", (err: Error) => dispose(err));
	options.readable.on("end", () => dispose());
	options.readable.on("close", () => dispose());

	return {
		request<T = unknown>(method: string, params: unknown, timeoutMs = 5_000): Promise<T> {
			if (disposed) {
				return Promise.reject(new Error("LSP JSON-RPC connection is closed"));
			}
			const id = nextId++;
			return new Promise<T>((resolvePromise, rejectPromise) => {
				const timer = setTimeout(() => {
					pending.delete(id);
					rejectPromise(new Error(`LSP request '${method}' timed out after ${timeoutMs}ms`));
				}, timeoutMs);
				timer.unref?.();
				pending.set(id, {
					resolve: resolvePromise as (value: unknown) => void,
					reject: rejectPromise,
					timer,
				});
				writeMessage({ id, method, params });
			});
		},

		notify(method: string, params?: unknown): void {
			if (disposed) return;
			writeMessage(params === undefined ? { method } : { method, params });
		},

		dispose,

		get isClosed(): boolean {
			return disposed;
		},
	};
}
