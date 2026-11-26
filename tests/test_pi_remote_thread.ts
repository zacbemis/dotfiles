import { strict as assert } from "node:assert";
import { execFileSync, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, rm, symlink, truncate, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { setTimeout as pause } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { launchModelArgs, register, request } from "../.pi/agent/extensions/remote-thread/bridge.mjs";
import {
	coordinateBash,
	decideOrchestratorCacheWarming,
	ORCHESTRATOR_WARM_MIN_SAVINGS,
	waitForReceipt,
} from "../.pi/agent/extensions/remote-thread/coordination.ts";
import { attachmentBytes, Handoffs, replyFrom } from "../.pi/agent/extensions/remote-thread/handoff.ts";
import { Mailbox, mailbox } from "../.pi/agent/extensions/remote-thread/mailbox.mjs";
import { NativeInbox, NativeThreads, REPLY_TYPE } from "../.pi/agent/extensions/remote-thread/native.ts";
import { parseMachines, shellArgument } from "../.pi/agent/extensions/remote-thread/transport.ts";

test("Pi delegation cannot use the nohup/PID polling recipe", () => {
	for (const command of [
		'cd "$project" && nohup pi -p "review" > report.md &',
		'P=$(cat "$D/pid"); while kill -0 $P 2>/dev/null; do sleep 30; done; wc -c "$D/report.md"',
	]) {
		const reason = coordinateBash({ command }, false)?.reason ?? "";
		assert.match(reason, /remote_thread.*Send waits/);
		assert.doesNotMatch(reason, /wait\s*:\s*false/);
	}
	assert.equal(coordinateBash({ command: 'kill -0 "$P" && echo alive' }, false), undefined);
});

test("peer bash gets a bounded timeout without relaxing a shorter one", () => {
	for (const [timeout, peerTurn, expected] of [[undefined, true, 300], [1800, true, 300], [5, true, 5], [undefined, false, undefined]] as const) {
		const input = { command: "xvfb-run cargo test", timeout };
		assert.equal(coordinateBash(input, peerTurn), undefined);
		assert.equal(input.timeout, expected);
	}
});

test("launch passes the exact model and thinking as separate Pi CLI arguments", async () => {
	assert.deepEqual(launchModelArgs("claude-bridge/claude-opus-5-5", "high"), ["--model", "claude-bridge/claude-opus-5-5", "--thinking", "high"]);
	assert.deepEqual(launchModelArgs(undefined, undefined), []);
	for (const model of ["opus", "--tools", "provider/id; whoami"]) assert.throws(() => launchModelArgs(model, undefined), /provider\/model/);
	assert.throws(() => launchModelArgs(undefined, "fast"), /thinking level/);
	await assert.rejects(request({ op: "launch", mode: "standalone", title: "invalid model test", model: "--tools" }), /provider\/model/);
});

test("a loaded bridge delegates worker operations to the current on-disk bridge", async t => {
	const dir = await mkdtemp(join(tmpdir(), "pi-thread-bridge-update."));
	t.after(() => rm(dir, { recursive: true, force: true }));
	const bridge = join(dir, "bridge.mjs");
	const source = new URL("../.pi/agent/extensions/remote-thread/", import.meta.url);
	await copyFile(new URL("bridge.mjs", source), bridge);
	await copyFile(new URL("mailbox.mjs", source), join(dir, "mailbox.mjs"));
	const loaded = await import(pathToFileURL(bridge).href);
	await writeFile(bridge, `
		if (process.argv[2] !== 'rpc') process.exit(2);
		let body = '';
		for await (const chunk of process.stdin) body += chunk;
		console.log(JSON.stringify({ result: { fromUpdatedBridge: JSON.parse(body) } }));
	`);
	for (const input of [
		{ op: "launch", mode: "standalone", title: "Update test", cwd: join(dir, "missing"), model: "test/model", thinking: "high" },
		{ op: "mail_accept", text: "Test restart" },
		{ op: "mail_status" },
	]) {
		assert.deepEqual(await loaded.request(input), { fromUpdatedBridge: input });
	}
});

test("machine routes do not accept SSH flags or shell syntax", () => {
	assert.deepEqual(parseMachines({ home: null, laptop: "zacb@arch.example" }), [
		{ name: "local" }, { name: "home", ssh: undefined }, { name: "laptop", ssh: "zacb@arch.example" },
	]);
	assert.deepEqual(parseMachines({ home: { via: "home" }, laptop: { ssh: "zacb@arch.example", offer: "home" } }), [
		{ name: "local" }, { name: "home", via: "home" }, { name: "laptop", ssh: "zacb@arch.example", offer: "home" },
	]);
	assert.throws(() => parseMachines({ home: { via: "../../elsewhere" } }), /Invalid SSH address/);
	for (const ssh of ["-oProxyCommand=sh", "host;whoami", "user@host other", "user@-host"]) {
		assert.throws(() => parseMachines({ laptop: ssh }), /Invalid SSH address/);
	}
});

test("the remote shell passes a multiline prompt as exactly one argument", () => {
	const literal = "It's OK\n$(printf WRONG); * \"quoted\"";
	assert.equal(execFileSync("sh", ["-c", `printf '%s' ${shellArgument(literal)}`], { encoding: "utf8" }), literal);
});

test("only a complete matching reply is returned, not prompt echo or unrelated terminal lines", () => {
	const output = "original prompt mentioning REPLY-id and END-id\ninternal output\n  REPLY-id\n  first line\n  second line\n  END-id\nfooter";
	assert.equal(replyFrom(output, "id"), "first line\nsecond line");
	assert.equal(replyFrom(output, "different"), undefined);
	assert.equal(replyFrom("REPLY-id\nno end", "id"), undefined);
	assert.equal(replyFrom("END-id\nREPLY-id\nnot a reply", "id"), undefined);
});

test("native discovery and request routing do not depend on terminal panes", async () => {
	const endpoint = randomUUID();
	const close = await register(endpoint, ({ op, text }: { op: string; text?: string }) => op === "info" ? { endpoint, mode: "standalone" } : { text });
	try {
		assert.ok((await request({ op: "list" }) as { endpoint: string }[]).some(thread => thread.endpoint === endpoint));
		assert.deepEqual(await request({ op: "send", endpoint, text: "A\nB" }), { text: "A\nB" });
		await assert.rejects(request({ op: "send", endpoint: "../../somewhere" }), /Invalid thread endpoint/);
	} finally { close(); }
});

test("outbox, queued inbox, and completed reply survive reopening both stores", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-mailbox-test."));
	const a = join(root, "sender");
	const b = join(root, "receiver");
	const id = randomUUID(), source = randomUUID(), session = randomUUID(), owner = randomUUID();
	const thread = { session, title: "peer" };
	let out = new Mailbox(a), inbox = new Mailbox(b);
	try {
		const t = out.rememberTarget("laptop", thread, randomUUID());
		out.enqueue(source, id, t, "read the artifact", "aGk=", "probe.txt");
		out.close();
		out = new Mailbox(a);
		assert.equal(out.rememberTarget("laptop", thread, randomUUID()), t);
		assert.deepEqual(out.due(source, Date.now()), [id]);
		const saved = out.outgoing(source, id)!;
		assert.equal(saved.status, "pending");
		const envelope = { id, source, session, text: saved.text, attachment: saved.attachment, filename: saved.filename };
		assert.throws(() => inbox.accept(envelope), /unknown/);
		inbox.rememberThread(thread);
		assert.equal(inbox.accept(envelope)?.status, "queued");
		inbox.close();
		inbox = new Mailbox(b);
		assert.equal(inbox.accept(envelope)?.status, "queued");
		const task = inbox.claim(session, owner)!;
		assert.equal(task.attachment, "aGk=");
		assert.equal(inbox.claim(session, randomUUID()), undefined);
		assert.equal(inbox.finish(session, id, randomUUID(), "completed", "wrong owner"), false);
		assert.equal(inbox.finish(session, id, owner, "completed", "read hi"), true);
		inbox.close();
		inbox = new Mailbox(b);
		const result = inbox.accept(envelope)!;
		assert.equal(result.status, "completed");
		assert.equal(result.reply, "read hi");
		assert.equal(inbox.claim(session, owner), undefined);
		out.updateOutgoing(source, id, "pending", result.status, result.reply, 0);
		out.close();
		out = new Mailbox(a);
		assert.equal(out.outgoing(source, id)?.reply, "read hi");
		assert.equal(out.outgoing(source, id)?.attachment, null);
		assert.equal(out.notifications(source).length, 1);
		out.acknowledge(source, id);
		assert.equal(out.notifications(source).length, 0);
	} finally {
		out.close(); inbox.close(); await rm(root, { recursive: true });
	}
});

test("a lost owner is marked interrupted and queued work is never confused with replay", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-mailbox-crash."));
	const session = randomUUID(), source = randomUUID(), first = randomUUID(), second = randomUUID(), owner = randomUUID();
	let store = new Mailbox(root);
	try {
		store.rememberThread({ session });
		const envelope = { session, source, text: "work once" };
		for (const id of [first, second]) store.accept({ ...envelope, id });
		assert.equal(store.claim(session, owner)?.id, first);
		store.close();
		store = new Mailbox(root);
		assert.equal(store.running(session)?.id, first);
		assert.equal(store.claim(session, randomUUID()), undefined);
		assert.equal(store.finish(session, first, owner, "interrupted", "do not replay"), true);
		assert.equal(store.accept({ ...envelope, id: first })?.status, "interrupted");
		assert.equal(store.claim(session, randomUUID())?.id, second);
	} finally { store.close(); await rm(root, { recursive: true }); }
});

test("only standalone workers retry queued work, with persistent backoff and a terminal failure", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-mailbox-wake."));
	const worker = randomUUID(), person = randomUUID(), source = randomUUID(), id = randomUUID();
	let store = new Mailbox(root);
	try {
		const thread = { title: "slice", cwd: "/home/someone/project", mode: "standalone" };
		store.rememberThread({ ...thread, session: worker, file: "/sessions/worker.jsonl", worker: true });
		store.rememberThread({ ...thread, session: person, worker: false });
		assert.equal(store.beginWake(worker, 1000), undefined, "nothing queued");
		for (const session of [worker, person]) store.accept({ session, source, id, text: "next task" });
		assert.equal(store.beginWake(person, 1000), undefined);
		assert.equal(store.beginWake(worker, 1000)?.attempts, 1);
		store.wakeFailed(worker, 1, 2000);
		store.close();
		store = new Mailbox(root);
		assert.equal(store.beginWake(worker, 6999), undefined);
		assert.equal(store.beginWake(worker, 7000)?.attempts, 2);
		store.rememberThread({ ...thread, session: worker, worker: true, workerToken: randomUUID() });
		store.wakeFailed(worker, 2, 8000); // Registration alone does not reset the retry budget.
		assert.equal(store.beginWake(worker, 17_999), undefined);
		assert.equal(store.beginWake(worker, 18_000)?.attempts, 3);
		store.wakeFailed(worker, 3, 19_000);
		const failed = store.incoming(worker, id, source)!;
		assert.equal(failed.status, "failed");
		assert.match(failed.reply, /could not restart after three attempts/);
		assert.equal(store.beginWake(worker, 100_000), undefined);
		assert.equal(store.claim(worker, randomUUID()), undefined);
	} finally { store.close(); await rm(root, { recursive: true }); }
});

test("cancellation is idempotent, cannot cancel another sender's request, and loses to an existing claim", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-mailbox-cancel."));
	const store = new Mailbox(root);
	const session = randomUUID(), id = randomUUID(), source = randomUUID(), owner = randomUUID();
	try {
		store.rememberThread({ session });
		store.accept({ session, id, source, text: "do not deliver" });
		assert.equal(store.cancel(session, id, randomUUID()), null);
		assert.equal(store.cancel(session, id, source)?.status, "cancelled");
		assert.equal(store.accept({ session, id, source, text: "do not replay" })?.status, "cancelled");
		assert.equal(store.claim(session, owner), undefined);
		const working = randomUUID();
		store.accept({ session, id: working, source, text: "already claimed" });
		assert.equal(store.claim(session, owner)?.id, working);
		assert.equal(store.cancel(session, working, source)?.status, "working");
	} finally { store.close(); await rm(root, { recursive: true }); }
});

test("one standalone worker resumes a lazy session with its original options, then resumes its saved state", async t => {
	const home = await mkdtemp(join(tmpdir(), "pi-thread-worker."));
	const bin = join(home, ".pi", "agent", "bin");
	const fixture = fileURLToPath(new URL("./fixtures/pi-thread-worker.mjs", import.meta.url));
	const bridge = fileURLToPath(new URL("../.pi/agent/extensions/remote-thread/bridge.mjs", import.meta.url));
	await mkdir(bin, { recursive: true });
	await writeFile(join(bin, "pi"), `#!/bin/sh\nexec ${shellArgument(process.execPath)} ${shellArgument(fixture)} "$@"\n`, { mode: 0o700 });
	const store = new Mailbox(home);
	const env = { ...process.env, HOME: home, PI_THREAD_MAILBOX_DIR: home };
	const hold = join(home, "hold-registration");
	const boots = (): { session: string; token: string; args: string[] }[] => existsSync(join(home, "boots")) ?
		readFileSync(join(home, "boots"), "utf8").trim().split("\n").filter(Boolean).map(line => JSON.parse(line)) : [];
	const stop = async (token: string) => {
		await writeFile(join(home, `stop-${token}`), "");
		await eventually(() => existsSync(join(home, `done-${token}`)));
	};
	t.after(async () => {
		await rm(hold, { force: true });
		await Promise.all(boots().map(({ token }) => stop(token)));
		store.close();
		await rm(home, { recursive: true });
	});
	const call = <T = unknown>(input: object) => new Promise<T>((resolve, reject) => {
		const child = spawn(process.execPath, [bridge, "rpc"], { env });
		let stdout = "";
		child.stdout.on("data", chunk => { stdout += chunk; });
		child.once("error", reject);
		child.once("close", code => {
			try {
				if (code !== 0) throw new Error(`Bridge exited with ${code}`);
				const response = JSON.parse(stdout);
				if (response.error) throw new Error(response.error);
				resolve(response.result);
			} catch (error) { reject(error); }
		});
		child.stdin.end(JSON.stringify(input));
	});
	const { session } = await call<{ session: string }>({ op: "launch", mode: "standalone", title: "Worker test", model: "test/original", thinking: "high" });
	const file = join(home, `${session}.jsonl`);
	await stop(boots()[0]!.token);
	assert.equal(existsSync(file), false);
	await writeFile(hold, "");
	const envelope = { session, source: randomUUID(), id: randomUUID(), text: "deliver after an idle restart" };
	await call({ op: "mail_accept", ...envelope });
	await eventually(async () => {
		if (boots()[1]) return boots()[1];
		await call({ op: "mail_status", ...envelope });
	});
	await pause(5100); // Retry time has passed, but the OS lock is still held before registration.
	await Promise.all(Array.from({ length: 4 }, () => call({ op: "mail_status", ...envelope })));
	assert.equal(boots().length, 2);
	assert.deepEqual(boots()[1]!.args, ["--mode", "rpc", "--session-id", session, "--name", "Worker test", "--model", "test/original", "--thinking", "high"]);
	await rm(hold);
	assert.equal((await eventually(() => {
		const result = store.incoming(session, envelope.id, envelope.source);
		return result?.status === "completed" && result;
	})).reply, "test/original/high");
	await stop(boots()[1]!.token);
	const next = { ...envelope, id: randomUUID() };
	await call({ op: "mail_accept", ...next });
	assert.equal((await eventually(async () => {
		const result = await call<{ status: string; reply?: string }>({ op: "mail_status", ...next });
		return result.status === "completed" && result;
	})).reply, "test/persisted/low");
	assert.deepEqual(boots()[2]!.args, ["--mode", "rpc", "--session", file]);
	await writeFile(join(bin, "pi"), "#!/bin/sh\nexit 1\n");
	await assert.rejects(call({ op: "launch", mode: "standalone", title: "Failed start" }),
		/Standalone Pi worker exited before registration \(exit code 1\)/);
});

test("a wait timeout bounds even a stalled refresh and does not cancel shared delivery", async () => {
	const shared = pause(100, "completed");
	const result = await waitForReceipt("pending", () => shared, status => status === "completed", 20);
	assert.deepEqual(result, { result: "pending", waitTimedOut: true });
	assert.equal(await shared, "completed");
	await assert.rejects(waitForReceipt("pending", async () => { throw new Error("storage failed"); }, () => false, 100), /storage failed/);
});

async function eventually<T>(check: () => T | undefined | false | Promise<T | undefined | false>): Promise<T> {
	const deadline = Date.now() + 6000;
	do {
		const result = await check();
		if (result) return result;
		await pause(15);
	} while (Date.now() < deadline);
	throw new Error("Expected condition was not reached");
}

function piContext(session: string, mode = "rpc") {
	const state = { busy: false, pending: false, branch: [] as unknown[] };
	const ctx = { mode, cwd: process.cwd(), isIdle: () => !state.busy, hasPendingMessages: () => state.pending,
		ui: { notify: () => {} }, sessionManager: { getSessionId: () => session, getSessionFile: () => `${session}.jsonl`,
			getSessionName: () => "test thread", getBranch: () => state.branch } } as unknown as Parameters<NativeThreads["start"]>[0];
	return { state, ctx };
}

test("native waits and completion wakes use the same durable receipt", async t => {
	const root = await mkdtemp(join(tmpdir(), "pi-thread-wait."));
	const old = process.env.PI_THREAD_MAILBOX_DIR;
	process.env.PI_THREAD_MAILBOX_DIR = root;
	const store = mailbox(), machines = [{ name: "local" }];
	t.after(async () => {
		store.close();
		if (old === undefined) delete process.env.PI_THREAD_MAILBOX_DIR;
		else process.env.PI_THREAD_MAILBOX_DIR = old;
		await rm(root, { recursive: true });
	});

	await t.test("cancelling through the native receipt updates both mailboxes", async t => {
		const source = randomUUID(), session = randomUUID(), id = randomUUID();
		const native = new NativeThreads(machines, () => assert.fail("unexpected wake in print mode"));
		native.start(piContext(source, "print").ctx);
		t.after(() => native.close());
		store.rememberThread({ session });
		const target = store.rememberTarget("local", { session }, randomUUID());
		store.enqueue(source, id, target, "do not deliver");
		store.accept({ session, source, id, text: "do not deliver" });
		store.updateOutgoing(source, id, "pending", "queued", null, Date.now());
		assert.equal((await native.cancel(id)).status, "cancelled");
		assert.equal(store.incoming(session, id, source)?.status, "cancelled");
		assert.equal(native.receipts().find(receipt => receipt.receipt === id)?.status, "cancelled");
	});

	await t.test("default wait retries pending delivery and ignores the background batch limit", async t => {
		const source = randomUUID(), session = randomUUID(), missing = randomUUID(), owner = randomUUID();
		const { ctx } = piContext(source, "print"); // No background poller.
		const native = new NativeThreads(machines, () => assert.fail("unexpected wake in print mode"), { waitMs: 8000 });
		native.start(ctx);
		t.after(() => native.close());
		const other = store.rememberTarget("local", { session: missing }, randomUUID());
		for (let i = 0; i < 8; i++) store.enqueue(source, randomUUID(), other, "unrelated");
		const target = store.rememberTarget("local", { session }, randomUUID());
		const waiting = native.send(target, "review", ctx.cwd, undefined);
		// The receiver is not registered yet, so the first delivery attempt fails.
		const receipt = store.receipts(source)[0].receipt as string;
		assert.ok(!store.due(source, Date.now()).includes(receipt));
		await eventually(() => Number(store.outgoing(source, receipt)?.failures) > 0);
		store.rememberThread({ session });
		const task = await eventually(() => store.claim(session, owner));
		assert.equal(task.id, receipt);
		store.finish(session, receipt, owner, "completed", "reviewed");
		const result = await waiting;
		assert.equal(result.status, "completed");
		assert.equal(result.reply, "reviewed");
		assert.equal(result.waitTimedOut, false);
	});

	await t.test("a timed-out wait resumes the idle sender once, even after reopening", async t => {
		const source = randomUUID(), session = randomUUID(), owner = randomUUID();
		const { state, ctx } = piContext(source);
		store.rememberThread({ session });
		const target = store.rememberTarget("local", { session }, randomUUID());
		const notices: string[] = [];
		const notify = (id: string) => {
			notices.push(id);
			state.branch.push({ type: "custom_message", customType: REPLY_TYPE, details: { id } });
		};
		const native = new NativeThreads(machines, notify, { waitMs: 50 });
		native.start(ctx);
		t.after(() => native.close());
		const result = await native.send(target, "review", ctx.cwd, undefined);
		assert.ok(result.status === "pending" || result.status === "queued");
		assert.equal(result.waitTimedOut, true);
		assert.match(result.next ?? "", /start a new turn/);
		const work = await eventually(() => store.claim(session, owner));
		assert.equal(work.id, result.receipt);
		assert.equal(store.finish(session, result.receipt, owner, "failed", "test failure"), true);
		native.close();
		const resumed = new NativeThreads(machines, notify);
		resumed.start(ctx);
		t.after(() => resumed.close());
		state.busy = true;
		await eventually(() => store.outgoing(source, result.receipt)?.status === "failed");
		assert.deepEqual(notices, []);
		state.busy = false;
		resumed.wake();
		resumed.wake();
		assert.deepEqual(notices, [result.receipt]);
		assert.deepEqual(store.notifications(source), []);
	});

	await t.test("abort preserves the handoff; a persisted inline result suppresses its wake", async t => {
		const source = randomUUID(), session = randomUUID(), owner = randomUUID();
		const { state, ctx } = piContext(source);
		store.rememberThread({ session });
		const target = store.rememberTarget("local", { session }, randomUUID());
		const notices: string[] = [];
		const native = new NativeThreads(machines, id => notices.push(id));
		native.start(ctx);
		t.after(() => native.close());
		state.busy = true;
		const ctl = new AbortController();
		const waiting = native.send(target, "review", ctx.cwd, undefined, ctl.signal);
		ctl.abort(new Error("stopped waiting"));
		await assert.rejects(waiting, /stopped waiting/);
		const task = await eventually(() => store.claim(session, owner));
		store.finish(session, task.id, owner, "completed", "reviewed");
		const result = await native.observe(task.id);
		assert.equal(result.reply, "reviewed");
		assert.equal(store.notifications(source).length, 1, "returning a tool result is not yet persisted");
		state.branch.push({ type: "message", message: { role: "toolResult", toolName: "remote_thread", details: { terminalReceipt: task.id } } });
		state.busy = false;
		native.wake();
		assert.deepEqual(notices, []);
		assert.deepEqual(store.notifications(source), []);
	});

	await t.test("worker settles only the matching started request, not an unrelated abort or a tool preamble", async t => {
		const source = randomUUID(), session = randomUUID(), id = randomUUID();
		const { state, ctx } = piContext(session);
		const calls: { customType: string; details: { id: string } }[] = [];
		const inbox = new NativeInbox({ sendMessage: (value: typeof calls[number]) => calls.push(value) } as unknown as ConstructorParameters<typeof NativeInbox>[0]);
		await inbox.start(ctx);
		t.after(() => inbox.close());
		store.accept({ session, source, id, text: "review" });
		const call = await eventually(() => calls[0]);
		assert.equal(call.details.id, id);
		inbox.begin(randomUUID());
		inbox.finish(true, ctx);
		assert.equal(store.incoming(session, id, source)?.status, "working");
		inbox.begin(id);
		state.branch.push({ type: "custom_message", ...call },
			{ type: "message", message: { role: "assistant", stopReason: "toolUse", content: [{ type: "text", text: "Starting review" }] } });
		inbox.finish(false, ctx);
		assert.equal(store.incoming(session, id, source)?.status, "failed");
	});
});

test("Herdr waits past the initial idle snapshot for a complete tagged reply", async t => {
	const root = await mkdtemp(join(tmpdir(), "pi-pane-wait."));
	t.after(() => rm(root, { recursive: true }));
	const path = process.env.PATH;
	const herdr = process.env.HERDR_ENV;
	process.env.PATH = `${root}:${path}`;
	process.env.HERDR_ENV = "1";
	t.after(() => {
		if (path === undefined) delete process.env.PATH; else process.env.PATH = path;
		if (herdr === undefined) delete process.env.HERDR_ENV; else process.env.HERDR_ENV = herdr;
	});
	await writeFile(join(root, "herdr"), `#!${process.execPath}
const fs = require('node:fs');
const state = ${JSON.stringify(join(root, "prompt"))};
const [group, op, pane, text, ...rest] = process.argv.slice(2);
const agent = { pane_id: 'w1:p2', terminal_id: 'xyz', agent: 'pi', agent_status: 'idle', agent_session: { kind: 'file', value: 'peer.jsonl' } };
if (group !== 'agent' || op === 'wait') process.exit(2);
if (op === 'list' || op === 'get') console.log(JSON.stringify({ result: { agent, agents: [agent] } }));
if (op === 'prompt') {
  if (rest.length) process.exit(2);
  fs.writeFileSync(state, text.match(/REPLY-([a-f0-9-]{36})/)[1]);
}
if (op === 'read') {
  const id = fs.readFileSync(state, 'utf8');
  if (!fs.existsSync(state + '.read')) fs.writeFileSync(state + '.read', '1');
  else console.log('REPLY-' + id + '\\nreviewed\\nEND-' + id);
}
`, { mode: 0o700 });
	const handoffs = new Handoffs([{ name: "local" }], {});
	const hosts = await handoffs.list();
	const target = hosts[0].threads?.[0].target;
	assert.ok(target);
	const result = await handoffs.send(target, "review", root, undefined);
	assert.equal(result.status, "completed");
	assert.ok("peerReply" in result && result.peerReply === "reviewed");
});

test("attachment reads one bounded workspace artifact and rejects escapes and private paths", async () => {
	const tmp = await mkdtemp(join(tmpdir(), "pi-thread-test."));
	try {
		const cwd = join(tmp, "workspace");
		await mkdir(join(cwd, ".ssh"), { recursive: true });
		await writeFile(join(cwd, "test.diff"), "sample");
		await writeFile(join(cwd, ".ssh", "private.txt"), "synthetic placeholder");
		await writeFile(join(tmp, "outside.txt"), "outside");
		await writeFile(join(cwd, "large.txt"), "");
		await truncate(join(cwd, "large.txt"), 1024 * 1024 + 1);
		await symlink(join(tmp, "outside.txt"), join(cwd, "escape.txt"));
		assert.equal((await attachmentBytes(cwd, "@test.diff")).bytes.toString(), "sample");
		await assert.rejects(attachmentBytes(cwd, "escape.txt"), /inside/);
		await assert.rejects(attachmentBytes(cwd, ".ssh/private.txt"), /non-sensitive/);
		await assert.rejects(attachmentBytes(cwd, "large.txt"), /1 MiB/);
	} finally {
		await rm(tmp, { recursive: true });
	}
});

test("orchestrator cache warming overrides idle stop only for active peer handoffs when warming pays for itself", async t => {
	assert.deepEqual(
		decideOrchestratorCacheWarming({ action: "stop", warmCost: 0.005, missCost: 0.12 }, true),
		{ action: "warm" },
	);
	assert.deepEqual(
		decideOrchestratorCacheWarming({ action: "stop", warmCost: 0.01, missCost: 0.01 + ORCHESTRATOR_WARM_MIN_SAVINGS }, true),
		{ action: "warm" },
	);
	assert.equal(decideOrchestratorCacheWarming({ action: "stop", warmCost: 0.005, missCost: 0.12 }, false), undefined);
	assert.equal(decideOrchestratorCacheWarming({ action: "warm", warmCost: 0.005, missCost: 0.12 }, true), undefined);
	assert.equal(decideOrchestratorCacheWarming({ action: "stop", warmCost: 0.01, missCost: 0.03 }, true), undefined);
	assert.equal(decideOrchestratorCacheWarming({ action: "stop", warmCost: 0, missCost: 0 }, true), undefined);

	const root = await mkdtemp(join(tmpdir(), "pi-thread-warm-state."));
	t.after(() => rm(root, { recursive: true, force: true }));
	const store = new Mailbox(root);
	t.after(() => store.close());
	const source = randomUUID();
	const peerSession = randomUUID();
	const id = randomUUID();
	const target = store.rememberTarget("local", { session: peerSession, title: "worker" }, randomUUID());

	assert.equal(store.hasActiveOutgoing(source), false);
	store.enqueue(source, id, target, "run build", null, null);
	// Pending handoffs have not been accepted by the peer yet and do not keep warming alive.
	assert.equal(store.hasActiveOutgoing(source), false);
	store.updateOutgoing(source, id, "pending", "queued", null, Date.now());
	assert.equal(store.hasActiveOutgoing(source), true);
	store.updateOutgoing(source, id, "queued", "working", null, Date.now());
	assert.equal(store.hasActiveOutgoing(source), true);
	store.updateOutgoing(source, id, "working", "completed", "done", Date.now());
	assert.equal(store.hasActiveOutgoing(source), false);
});
