import { strict as assert } from "node:assert";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PassThrough } from "node:stream";
import { test } from "node:test";
import { createJsonRpcConnection } from "../.pi/agent/extensions/lsp-diagnostics/jsonrpc.ts";
import {
	createLspDiagnosticsManager,
	LSP_DIAGNOSTICS_DISABLE_ENV,
} from "../.pi/agent/extensions/lsp-diagnostics/manager.ts";
import {
	DEFAULT_LSP_SERVERS,
	type LspServerSpec,
	resolveServerBinary,
} from "../.pi/agent/extensions/lsp-diagnostics/servers.ts";

function frameJsonRpc(payload: Record<string, unknown>): Buffer {
	const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...payload }), "utf-8");
	const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "ascii");
	return Buffer.concat([header, body]);
}

test("jsonrpc transport handles UTF-8 framing, split chunks, notifications, and server requests", async () => {
	const serverToClient = new PassThrough();
	const clientToServer = new PassThrough();

	const notifications: Array<{ method: string; params: unknown }> = [];
	const outboundChunks: Buffer[] = [];
	clientToServer.on("data", (chunk: Buffer) => outboundChunks.push(chunk));

	const rpc = createJsonRpcConnection({
		readable: serverToClient,
		writable: clientToServer,
		onNotification: (method, params) => notifications.push({ method, params }),
		onRequest: (method) => {
			if (method === "workspace/configuration") return [{ strict: true }];
			return null;
		},
	});

	// Send a client request and reply in split UTF-8 chunks.
	const reqPromise = rpc.request<{ greeting: string }>("test/echo", { text: "héllo 🌍" }, 2_000);
	const responseFrame = frameJsonRpc({ id: 1, result: { greeting: "héllo 🌍" } });
	serverToClient.write(responseFrame.subarray(0, 10));
	serverToClient.write(responseFrame.subarray(10));
	const reply = await reqPromise;
	assert.deepEqual(reply, { greeting: "héllo 🌍" });

	// Server notification + server-to-client request.
	serverToClient.write(frameJsonRpc({ method: "textDocument/publishDiagnostics", params: { uri: "file:///a.ts" } }));
	serverToClient.write(frameJsonRpc({ id: 99, method: "workspace/configuration", params: { items: [{}] } }));
	await new Promise((r) => setTimeout(r, 30));

	assert.equal(notifications.length, 1);
	assert.equal(notifications[0]?.method, "textDocument/publishDiagnostics");
	const sentRaw = Buffer.concat(outboundChunks).toString("utf-8");
	assert.match(sentRaw, /"id":99,"result":\[\{"strict":true\}\]/);

	rpc.dispose();
	assert.equal(rpc.isClosed, true);
});

test("lsp diagnostics manager spawns lazily on configured projects, filters to errors, updates on edits, and shuts down cleanly", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-mock-"));
	const binDir = join(dir, "bin");
	const configuredRepo = join(dir, "configured");
	const plainRepo = join(dir, "plain");

	try {
		await import("node:fs/promises").then((fs) =>
			Promise.all([
				fs.mkdir(binDir, { recursive: true }),
				fs.mkdir(configuredRepo, { recursive: true }),
				fs.mkdir(plainRepo, { recursive: true }),
			]),
		);

		// Create a lightweight mock LSP server in Node.
		const mockServerPath = join(binDir, "mock-lsp");
		await writeFile(
			mockServerPath,
			`#!/usr/bin/env node
let buf = Buffer.alloc(0);
function send(obj) {
  const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...obj }), "utf8");
  process.stdout.write(Buffer.concat([Buffer.from("Content-Length: " + body.length + "\\r\\n\\r\\n", "ascii"), body]));
}
function checkDoc(uri, version, text) {
  const diagnostics = [
    { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, severity: 2, source: "mock", code: "W1", message: "warning should be ignored" },
  ];
  const lines = text.split("\\n");
  lines.forEach((line, idx) => {
    const col = line.indexOf("TYPE_ERR");
    if (col !== -1) {
      diagnostics.push({
        range: { start: { line: idx, character: col }, end: { line: idx, character: col + 8 } },
        severity: 1,
        source: "mock",
        code: "E42",
        message: "Incompatible type detected",
      });
    }
  });
  send({ method: "textDocument/publishDiagnostics", params: { uri, version, diagnostics } });
}
process.stdin.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  while (true) {
    const sep = buf.indexOf("\\r\\n\\r\\n");
    if (sep === -1) return;
    const m = /content-length:\\s*(\\d+)/i.exec(buf.subarray(0, sep).toString("ascii"));
    if (!m) { buf = buf.subarray(sep + 4); continue; }
    const len = parseInt(m[1], 10);
    if (buf.length < sep + 4 + len) return;
    const msg = JSON.parse(buf.subarray(sep + 4, sep + 4 + len).toString("utf8"));
    buf = buf.subarray(sep + 4 + len);
    if (msg.method === "initialize") {
      send({ id: msg.id, result: { capabilities: { textDocumentSync: 1 } } });
    } else if (msg.method === "textDocument/didOpen") {
      checkDoc(msg.params.textDocument.uri, msg.params.textDocument.version, msg.params.textDocument.text);
    } else if (msg.method === "textDocument/didChange") {
      checkDoc(msg.params.textDocument.uri, msg.params.textDocument.version, msg.params.contentChanges[0].text);
    } else if (msg.method === "shutdown") {
      send({ id: msg.id, result: null });
    } else if (msg.method === "exit") {
      process.exit(0);
    }
  }
});
`,
			"utf-8",
		);
		await chmod(mockServerPath, 0o755);

		const mockSpec: LspServerSpec = {
			id: "mock",
			extensions: new Set([".mock"]),
			rootMarkers: ["mock.config.json"],
			binary: "mock-lsp",
			args: [],
			languageIdForExtension: () => "mock",
		};

		const manager = createLspDiagnosticsManager({
			servers: [mockSpec],
			extraBinDirs: [binDir],
			warmWaitMs: 1_500,
			coldWaitMs: 2_500,
		});

		try {
			// Unconfigured repo without marker never spawns a server.
			await writeFile(join(plainRepo, "a.mock"), "const x = TYPE_ERR;\n", "utf-8");
			assert.equal(await manager.checkFiles(plainRepo, ["a.mock"]), undefined);
			assert.equal(manager.activeServerCount, 0);

			// Configured repo spawns once, reports only severity=1 errors, ignores warnings.
			await writeFile(join(configuredRepo, "mock.config.json"), "{}\n", "utf-8");
			await writeFile(join(configuredRepo, "app.mock"), "const ok = 1;\nconst bad = TYPE_ERR;\n", "utf-8");
			const errBlock = await manager.checkFiles(configuredRepo, ["app.mock"]);
			assert.equal(manager.activeServerCount, 1);
			assert.match(errBlock ?? "", /^\[LSP Diagnostics\]\n/);
			assert.match(errBlock ?? "", /app\.mock:2:13 error \[mock E42\] Incompatible type detected/);
			assert.doesNotMatch(errBlock ?? "", /warning should be ignored/);

			// Fixing the file clears diagnostics via didChange on the warm server.
			await writeFile(join(configuredRepo, "app.mock"), "const ok = 1;\nconst good = 2;\n", "utf-8");
			assert.equal(await manager.checkFiles(configuredRepo, ["app.mock"]), undefined);
			assert.equal(manager.activeServerCount, 1);

			// Opt-out env disables checks.
			await writeFile(join(configuredRepo, "app.mock"), "const bad = TYPE_ERR;\n", "utf-8");
			process.env[LSP_DIAGNOSTICS_DISABLE_ENV] = "0";
			try {
				assert.equal(await manager.checkFiles(configuredRepo, ["app.mock"]), undefined);
			} finally {
				delete process.env[LSP_DIAGNOSTICS_DISABLE_ENV];
			}
		} finally {
			await manager.shutdownAll();
			assert.equal(manager.activeServerCount, 0);
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("real typescript-language-server catches type mismatch and clears after fix (when installed)", async (t) => {
	const tsSpec = DEFAULT_LSP_SERVERS.find((s) => s.id === "typescript")!;
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-ts-"));
	try {
		const bin = await resolveServerBinary(tsSpec.binary, dir, dir);
		if (!bin) {
			t.skip("typescript-language-server not installed");
			return;
		}

		await writeFile(
			join(dir, "tsconfig.json"),
			JSON.stringify({ compilerOptions: { target: "ES2022", module: "NodeNext", strict: true, noEmit: true } }),
			"utf-8",
		);
		await writeFile(join(dir, "sample.ts"), 'export const count: number = "not-a-number";\n', "utf-8");

		const manager = createLspDiagnosticsManager({
			servers: [tsSpec],
			coldWaitMs: 6_000,
			warmWaitMs: 3_000,
		});
		try {
			const result = await manager.checkFiles(dir, ["sample.ts"]);
			assert.match(result ?? "", /^\[LSP Diagnostics\]\n/);
			assert.match(result ?? "", /sample\.ts:1:14 error/);
			assert.match(result ?? "", /not assignable to type 'number'/);

			await writeFile(join(dir, "sample.ts"), "export const count: number = 42;\n", "utf-8");
			const clean = await manager.checkFiles(dir, ["sample.ts"]);
			assert.equal(clean, undefined);
		} finally {
			await manager.shutdownAll();
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("real pyright-langserver catches type mismatch and clears after fix (when installed)", async (t) => {
	const pySpec = DEFAULT_LSP_SERVERS.find((s) => s.id === "pyright")!;
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-py-"));
	try {
		const bin = await resolveServerBinary(pySpec.binary, dir, dir);
		if (!bin) {
			t.skip("pyright-langserver not installed");
			return;
		}

		await writeFile(join(dir, "pyrightconfig.json"), JSON.stringify({ typeCheckingMode: "basic" }), "utf-8");
		await writeFile(join(dir, "sample.py"), 'def add(a: int, b: int) -> int:\n    return a + b\n\nx: int = add("bad", 2)\n', "utf-8");

		const manager = createLspDiagnosticsManager({
			servers: [pySpec],
			coldWaitMs: 6_000,
			warmWaitMs: 3_000,
		});
		try {
			const result = await manager.checkFiles(dir, ["sample.py"]);
			assert.match(result ?? "", /^\[LSP Diagnostics\]\n/);
			assert.match(result ?? "", /sample\.py:4:\d+ error/);

			await writeFile(join(dir, "sample.py"), "def add(a: int, b: int) -> int:\n    return a + b\n\nx: int = add(1, 2)\n", "utf-8");
			const clean = await manager.checkFiles(dir, ["sample.py"]);
			assert.equal(clean, undefined);
		} finally {
			await manager.shutdownAll();
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});
