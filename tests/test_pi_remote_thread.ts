import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, mkdtemp, rm, symlink, truncate, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { launchModelArgs, register, request } from "../.pi/agent/extensions/remote-thread/bridge.mjs";
import { coordinateBash } from "../.pi/agent/extensions/remote-thread/coordination.ts";
import { attachmentBytes, replyFrom } from "../.pi/agent/extensions/remote-thread/handoff.ts";
import { Mailbox } from "../.pi/agent/extensions/remote-thread/mailbox.mjs";
import { parseMachines, shellArgument } from "../.pi/agent/extensions/remote-thread/transport.ts";

test("Pi delegation cannot use the nohup/PID polling recipe", () => {
	for (const command of [
		'cd "$project" && nohup pi -p "review" > report.md &',
		'P=$(cat "$D/pid"); while kill -0 $P 2>/dev/null; do sleep 30; done; wc -c "$D/report.md"',
	]) {
		assert.match(coordinateBash({ command }, false)?.reason ?? "", /remote_thread.*wait:false/);
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

test("an idle background worker is woken once for queued work, and an interactive session never is", async () => {
	const root = await mkdtemp(join(tmpdir(), "pi-mailbox-wake."));
	const worker = randomUUID(), person = randomUUID(), source = randomUUID();
	const store = new Mailbox(root);
	try {
		const thread = { title: "slice", cwd: "/home/someone/project", mode: "standalone" };
		store.rememberThread({ ...thread, session: worker, file: "/sessions/worker.jsonl", worker: true });
		store.rememberThread({ ...thread, session: person, file: "/sessions/person.jsonl", worker: false });
		assert.equal(store.claimWake(worker, 1_000_000), undefined, "nothing queued");
		for (const session of [worker, person]) store.accept({ session, source, id: randomUUID(), text: "next task" });
		assert.equal(store.claimWake(person, 1_000_000), undefined);
		assert.deepEqual({ ...store.claimWake(worker, 1_000_000) }, { title: "slice", cwd: "/home/someone/project", file: "/sessions/worker.jsonl" });
		assert.equal(store.claimWake(worker, 1_059_999), undefined, "a second sender within the lease does not start another process");
		assert.ok(store.claimWake(worker, 1_060_000), "a wake that never registered is retried after the lease");
		assert.ok(store.claim(worker, randomUUID()));
		assert.equal(store.claimWake(worker, 2_000_000), undefined, "claimed work is not queued");
	} finally { store.close(); await rm(root, { recursive: true }); }
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
