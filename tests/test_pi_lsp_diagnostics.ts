import { strict as assert } from "node:assert";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PassThrough } from "node:stream";
import { test } from "node:test";
import { createJsonRpcConnection } from "../.pi/agent/extensions/lsp-diagnostics/jsonrpc.ts";
import {
	createLspDiagnosticsManager,
	LSP_DIAGNOSTICS_DISABLE_ENV,
	resolveLineColumn0,
} from "../.pi/agent/extensions/lsp-diagnostics/manager.ts";
import {
	DEFAULT_LSP_SERVERS,
	hasConfiguredLspWorkspace,
	type LspServerSpec,
	resolveServerBinary,
} from "../.pi/agent/extensions/lsp-diagnostics/servers.ts";
import {
	createLspSettleGuard,
	LSP_SETTLE_GUARD_DISABLE_ENV,
} from "../.pi/agent/extensions/lsp-diagnostics/settle-guard.ts";

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

test("resolveLineColumn0 and LSP settle guard behave deterministically and nudge at most once per turn", async () => {
	assert.equal(resolveLineColumn0("  const result = computeSum(a, b);", undefined, "computeSum"), 17);
	assert.equal(resolveLineColumn0("  const result = computeSum(a, b);", 9, "computeSum"), 8);
	assert.equal(resolveLineColumn0("    return x;", undefined, undefined), 4);

	const guard = createLspSettleGuard();
	const cwd = "/tmp/workspace";
	const badAbs = "/tmp/workspace/src/a.ts";

	guard.recordCheckResult(cwd, ["src/a.ts"], [], new Map([[badAbs, ["src/a.ts:1:1 error bad"]]]));
	assert.equal(guard.unresolvedCount, 1);

	// Recheck confirms error still exists -> returns one nudge.
	const nudge1 = await guard.buildSettleNudge(cwd, async () => ({
		block: "[LSP Diagnostics]\nsrc/a.ts:1:1 error bad",
		errorsByFile: new Map([[badAbs, ["src/a.ts:1:1 error bad"]]]),
	}));
	assert.match(nudge1 ?? "", /resolve the remaining LSP error/);
	assert.match(nudge1 ?? "", /src\/a\.ts:1:1 error bad/);

	// Second settle in same turn does not loop.
	const nudge2 = await guard.buildSettleNudge(cwd, async () => {
		throw new Error("should not recheck after nudging once in same turn");
	});
	assert.equal(nudge2, undefined);

	// New turn resets nudge cap; if recheck finds errors resolved, returns undefined.
	guard.resetTurn();
	guard.recordCheckResult(cwd, ["src/a.ts"], [], new Map([[badAbs, ["src/a.ts:1:1 error bad"]]]));
	const resolved = await guard.buildSettleNudge(cwd, async () => ({
		errorsByFile: new Map(),
	}));
	assert.equal(resolved, undefined);
	assert.equal(guard.unresolvedCount, 0);

	// Opt-out env disables settle guard.
	guard.recordCheckResult(cwd, ["src/a.ts"], [], new Map([[badAbs, ["src/a.ts:1:1 error bad"]]]));
	process.env[LSP_SETTLE_GUARD_DISABLE_ENV] = "0";
	try {
		assert.equal(
			await guard.buildSettleNudge(cwd, async () => {
				throw new Error("should not run when disabled");
			}),
			undefined,
		);
	} finally {
		delete process.env[LSP_SETTLE_GUARD_DISABLE_ENV];
	}
});

test("real typescript-language-server supports definition, references, hover, and symbols (when installed)", async (t) => {
	const tsSpec = DEFAULT_LSP_SERVERS.find((s) => s.id === "typescript")!;
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-nav-ts-"));
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
		await writeFile(
			join(dir, "lib.ts"),
			"export function computeTotal(price: number, qty: number): number {\n  return price * qty;\n}\n",
			"utf-8",
		);
		await writeFile(
			join(dir, "app.ts"),
			'import { computeTotal } from "./lib.js";\nexport const total = computeTotal(10, 3);\n',
			"utf-8",
		);

		const manager = createLspDiagnosticsManager({
			servers: [tsSpec],
			coldWaitMs: 6_000,
			warmWaitMs: 3_000,
			navTimeoutMs: 6_000,
		});
		try {
			const defOut = await manager.queryNavigation(dir, {
				action: "definition",
				path: "app.ts",
				line: 2,
				symbol: "computeTotal",
			});
			assert.match(defOut, /lib\.ts:1:\d+: export function computeTotal/);

			const hoverOut = await manager.queryNavigation(dir, {
				action: "hover",
				path: "app.ts",
				line: 2,
				symbol: "computeTotal",
			});
			assert.match(hoverOut, /computeTotal\(price: number, qty: number\): number/);

			const refsOut = await manager.queryNavigation(dir, {
				action: "references",
				path: "lib.ts",
				line: 1,
				symbol: "computeTotal",
			});
			assert.match(refsOut, /lib\.ts:1:/);
			assert.match(refsOut, /app\.ts:/);

			const symOut = await manager.queryNavigation(dir, {
				action: "symbols",
				path: "lib.ts",
			});
			assert.match(symOut, /L1-3 function computeTotal/);
		} finally {
			await manager.shutdownAll();
		}
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("concurrent cold-start multi-file checks spawn only a single LSP server process", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-concurrent-"));
	try {
		const binDir = join(dir, "bin");
		await mkdir(binDir, { recursive: true });
		const spawnCountFile = join(dir, "spawns.log");
		const serverPath = join(binDir, "counting-lsp");
		await writeFile(
			serverPath,
			`#!/usr/bin/env node
const fs = require("node:fs");
fs.appendFileSync(${JSON.stringify(spawnCountFile)}, process.pid + "\\n");
let buf = Buffer.alloc(0);
function send(msg) {
  const body = Buffer.from(JSON.stringify(msg), "utf8");
  process.stdout.write("Content-Length: " + body.length + "\\r\\n\\r\\n");
  process.stdout.write(body);
}
process.stdin.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  while (true) {
    const idx = buf.indexOf("\\r\\n\\r\\n");
    if (idx === -1) break;
    const header = buf.subarray(0, idx).toString("ascii");
    const m = /Content-Length:\\s*(\\d+)/i.exec(header);
    if (!m) break;
    const len = Number(m[1]);
    if (buf.length < idx + 4 + len) break;
    const msg = JSON.parse(buf.subarray(idx + 4, idx + 4 + len).toString("utf8"));
    buf = buf.subarray(idx + 4 + len);
    if (msg.method === "initialize") send({ jsonrpc: "2.0", id: msg.id, result: { capabilities: {} } });
    else if (msg.method === "textDocument/didOpen" || msg.method === "textDocument/didChange") {
      send({ jsonrpc: "2.0", method: "textDocument/publishDiagnostics", params: { uri: msg.params.textDocument.uri, version: msg.params.textDocument.version, diagnostics: [] } });
    } else if (msg.method === "shutdown") send({ jsonrpc: "2.0", id: msg.id, result: null });
    else if (msg.method === "exit") process.exit(0);
  }
});
`,
			"utf-8",
		);
		await chmod(serverPath, 0o755);
		await writeFile(join(dir, "fake.config"), "{}\n");
		await writeFile(join(dir, "a.fake"), "const a = 1;\n");
		await writeFile(join(dir, "b.fake"), "const b = 2;\n");
		await writeFile(join(dir, "c.fake"), "const c = 3;\n");

		const manager = createLspDiagnosticsManager({
			servers: [
				{
					id: "fake",
					extensions: new Set([".fake"]),
					rootMarkers: ["fake.config"],
					binary: "counting-lsp",
					args: [],
					languageIdForExtension: () => "fake",
				},
			],
			extraBinDirs: [binDir],
		});
		try {
			await manager.checkFilesDetailed(dir, ["a.fake", "b.fake", "c.fake"]);
			assert.equal(manager.activeServerCount, 1);
			const spawns = (await readFile(spawnCountFile, "utf-8")).trim().split("\n").filter(Boolean);
			assert.equal(spawns.length, 1, `expected 1 spawned LSP server, got ${spawns.length}`);
		} finally {
			await manager.shutdownAll();
		}
		assert.equal(manager.activeServerCount, 0);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("hasConfiguredLspWorkspace gates lsp tool to workspaces with matching config and binary", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-gate-"));
	try {
		const binDir = join(dir, "bin");
		await mkdir(binDir, { recursive: true });
		const fakeSpec: LspServerSpec = {
			id: "fake",
			extensions: new Set([".fake"]),
			rootMarkers: ["fake.config"],
			binary: "gate-test-lsp",
			args: [],
			languageIdForExtension: () => "fake",
		};

		// Empty workspace without marker -> false.
		assert.equal(await hasConfiguredLspWorkspace(dir, [fakeSpec], [binDir]), false);

		// Marker present in nested monorepo package (depth 2), but binary missing -> false.
		const pkgDir = join(dir, "packages", "app");
		await mkdir(pkgDir, { recursive: true });
		await writeFile(join(pkgDir, "fake.config"), "{}", "utf-8");
		assert.equal(await hasConfiguredLspWorkspace(dir, [fakeSpec], [binDir]), false);

		// Once binary exists -> true for both root and nested subdir.
		const binPath = join(binDir, "gate-test-lsp");
		await writeFile(binPath, "#!/bin/sh\nexit 0\n", "utf-8");
		await chmod(binPath, 0o755);
		assert.equal(await hasConfiguredLspWorkspace(dir, [fakeSpec], [binDir]), true);
		assert.equal(await hasConfiguredLspWorkspace(pkgDir, [fakeSpec], [binDir]), true);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});
