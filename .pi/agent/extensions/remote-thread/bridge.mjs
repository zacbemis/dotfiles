import { execFile, spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { lstat, mkdir, mkdtemp, open, readdir, realpath, stat, unlink, writeFile } from 'node:fs/promises';
import { createConnection, createServer } from 'node:net';
import { homedir } from 'node:os';
import { isAbsolute, join, relative } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { mailbox, validId } from './mailbox.mjs';

const idPattern = /^[a-f0-9-]{36}$/;
const limit = 1500 * 1024;
const validAlias = alias => typeof alias === 'string' && /^[a-z0-9][a-z0-9-]{0,39}$/.test(alias);
const cli = fileURLToPath(import.meta.url);
const exec = promisify(execFile);
const root = `/tmp/pi-threads-v1-${process.getuid?.()}`;
const WORKER_START_MS = 30_000;
const WORKER_LOCK_FD = 3;

async function registry() {
	if (process.getuid?.() === undefined) throw new Error('Thread sockets require a Unix account.');
	await mkdir(root, { mode: 0o700 }).catch(error => { if (error.code !== 'EEXIST') throw error; });
	const info = await lstat(root);
	if (!info.isDirectory() || info.uid !== process.getuid() || (info.mode & 0o777) !== 0o700) throw new Error('Unsafe Pi thread registry.');
	return root;
}

const pathFor = (directory, id) => {
	if (typeof id !== 'string' || !idPattern.test(id)) throw new Error('Invalid thread endpoint.');
	return join(directory, `${id}.sock`);
};

function receive(stream, callback, timeout = 3000) {
	let bytes = 0;
	const chunks = [];
	stream.setTimeout(timeout, () => stream.destroy());
	stream.on('data', chunk => {
		bytes += chunk.length;
		if (bytes > limit) { stream.destroy(); return; }
		chunks.push(chunk);
	});
	stream.on('end', () => {
		try { callback(JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
		catch { stream.destroy(); }
	});
}

async function serve(path, handler) {
	const server = createServer({ allowHalfOpen: true }, socket => {
		socket.on('error', () => {});
		receive(socket, request => {
			socket.setTimeout(0);
			Promise.resolve().then(() => handler(request)).then(
				result => socket.end(JSON.stringify({ result })),
				error => socket.end(JSON.stringify({ error: String(error.message).slice(0, 512) })),
			);
		});
	});
	await new Promise((resolve, reject) => {
		server.once('error', reject);
		server.listen(path, () => { server.off('error', reject); resolve(); });
	});
	server.unref();
	return () => { server.close(); void unlink(path).catch(() => {}); };
}

export async function register(endpoint, handler) {
	return serve(pathFor(await registry(), endpoint), handler);
}

export async function endpointAlive(id) {
	const path = pathFor(await registry(), id);
	return new Promise((resolve, reject) => {
		const socket = createConnection(path);
		const done = (alive) => { socket.destroy(); resolve(alive); };
		socket.once('connect', () => done(true));
		socket.once('error', error => {
			if (['ENOENT', 'ECONNREFUSED'].includes(error.code)) done(false);
			else reject(error);
		});
		socket.setTimeout(1500, () => done(true));
	});
}

async function call(path, request) {
	return new Promise((resolve, reject) => {
		const socket = createConnection(path);
		socket.on('error', reject);
		socket.on('close', () => reject(new Error('Thread closed without responding.')));
		socket.on('connect', () => socket.end(JSON.stringify(request)));
		receive(socket, response => response.error ? reject(new Error(response.error)) : resolve(response.result), request.op === 'launch' ? 59_000 : 6000);
	});
}

export async function request(input) {
	// A Pi session or SSH relay can outlive an extension update. Build worker
	// arguments in a fresh bridge process, not in the long-lived caller.
	if ((input.op === 'launch' && input.mode === 'standalone') || input.op === 'mail_accept' || input.op === 'mail_status') {
		return new Promise((resolve, reject) => {
			const child = execFile(process.execPath, [cli, 'rpc'], {
				timeout: input.op === 'launch' ? 60_000 : 8000, killSignal: 'SIGKILL',
			}, (error, stdout) => {
				if (error) { reject(new Error(`Local Pi thread bridge did not complete (${error.code ?? error.signal ?? 'unknown error'}).`)); return; }
				try {
					const response = JSON.parse(stdout);
					if (response.error) throw new Error(response.error);
					resolve(response.result);
				} catch (error) { reject(error); }
			});
			child.stdin.on('error', () => {});
			child.stdin.end(JSON.stringify(input));
		});
	}
	return dispatch(input);
}

async function dispatch(input) {
	const directory = await registry();
	if (input.op === 'list') {
		const sockets = (await readdir(directory)).filter(name => name.endsWith('.sock') && idPattern.test(name.slice(0, -5)));
		const threads = await Promise.all(sockets.slice(0, 128).map(async name => {
			try { return await call(join(directory, name), { op: 'info' }); }
			catch (error) {
				if (error.code === 'ECONNREFUSED') await unlink(join(directory, name)).catch(() => {});
				return undefined;
			}
		}));
		return threads.filter(Boolean);
	}
	if (input.op === 'mail_list') {
		const known = mailbox().threads();
		const live = new Map((await request({ op: 'list' })).map(thread => [thread.session, thread]));
		return known.map(thread => live.get(thread.session) ?? { ...thread, status: 'offline' });
	}
	if (input.op === 'mail_accept') return wake(mailbox().accept(input), input.session);
	if (input.op === 'mail_status') return wake(mailbox().incoming(input.session, input.id, input.source), input.session);
	if (input.op === 'mail_cancel') return mailbox().cancel(input.session, input.id, input.source);
	if (input.op === 'launch') return launch(input);
	if (input.op === 'stage') {
		if (typeof input.bytes !== 'string' || input.bytes.length > 1_398_104) throw new Error('Invalid attachment.');
		const bytes = Buffer.from(input.bytes, 'base64');
		if (bytes.length > 1024 * 1024) throw new Error('Attachment exceeds 1 MiB.');
		const dir = await mkdtemp('/tmp/pi-thread.');
		const path = join(dir, 'attachment');
		await writeFile(path, bytes, { mode: 0o600, flag: 'wx' });
		return path;
	}
	return call(pathFor(directory, input.endpoint), input);
}

export async function linkedRequest(alias, input) {
	if (!validAlias(alias)) throw new Error('Invalid thread link.');
	return call(join(await registry(), `route-${alias}.sock`), input);
}

export function ensureLink(target, alias) {
	if (!validAlias(alias) || typeof target !== 'string' || !/^(?:[\w][\w.-]*@)?[a-zA-Z0-9][a-zA-Z0-9.-]*$/.test(target)) throw new Error('Invalid thread link configuration.');
	const helper = spawn(process.execPath, [cli, 'link', target, alias], { detached: true, stdio: 'ignore' });
	helper.on('error', () => {});
	helper.unref();
}

async function link(target, alias) {
	if (!validAlias(alias)) throw new Error('Invalid thread link.');
	const source = join(await registry(), `relay-${alias}.sock`);
	let close;
	try { close = await serve(source, request); }
	catch (error) { if (error.code === 'EADDRINUSE') return; throw error; }
	const options = ['-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5', '-o', 'ForwardAgent=no'];
	let tunnel;
	const stop = () => { tunnel?.kill(); close(); process.exit(0); };
	process.once('SIGTERM', stop);
	process.once('SIGINT', stop);
	for (;;) {
		try {
			const { stdout } = await exec('ssh', [...options, '--', target, 'node "$HOME/.pi/agent/extensions/remote-thread/bridge.mjs" registry'], { timeout: 8000 });
			const dest = stdout.trim();
			if (!/^\/tmp\/pi-threads-v1-\d+$/.test(dest)) throw new Error('Invalid remote registry.');
			tunnel = spawn('ssh', [...options, '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=2', '-N', '-R', `${dest}/route-${alias}.sock:${source}`, '--', target], { stdio: 'ignore' });
			await new Promise(resolve => { tunnel.once('exit', resolve); tunnel.once('error', resolve); });
		} catch { /* Retry after a connection or authentication interruption. */ }
		await pause(15_000);
	}
}

async function wake(status, session) {
	if (status?.status !== 'queued') return status;
	const store = mailbox();
	const thread = store.wakeCandidate(session, Date.now());
	if (!thread || (thread.endpoint ? await endpointAlive(thread.endpoint) :
		(await request({ op: 'list' })).some(candidate => candidate.session === session))) return status;
	try {
		await startWorker(session, thread.title ?? 'Pi thread', 'resume');
	} catch {
		const attempt = store.beginWake(session, Date.now());
		if (attempt) store.wakeFailed(session, attempt.attempts, Date.now());
	}
	return status;
}

async function startWorker(session, title, mode, ...args) {
	if (!validId(session)) throw new Error('Invalid worker session ID.');
	const lock = await open(join(await registry(), `${session}.lock`), 'a', 0o600);
	try {
		// flock applies to the open file description. Both worker and Pi inherit it,
		// so even a worker crash cannot start another Pi before the first one exits.
		const stdio = ['ignore', 'ignore', 'ignore', lock.fd];
		const code = await exited(spawn('flock', ['-n', '-E', '75', String(WORKER_LOCK_FD)], { stdio }));
		if (code === 75) return;
		if (code !== 0) throw new Error('Could not lock the standalone worker.');
		const child = spawn(process.execPath, [cli, 'worker', session, title, mode, ...args], { detached: true, stdio });
		await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
		child.unref();
		return child;
	} finally { await lock.close(); }
}

function exited(child) {
	return new Promise((resolve, reject) => { child.once('exit', resolve); child.once('error', reject); });
}

async function worker(session, title, mode, cwd, ...modelArgs) {
	if (!validId(session) || !['launch', 'resume'].includes(mode)) throw new Error('Invalid standalone worker arguments.');
	const store = mailbox();
	let attempt;
	try {
		let expectedModel, expectedThinking;
		let sessionArgs = ['--session-id', session, '--name', title, ...modelArgs];
		if (mode === 'resume') {
			attempt = store.beginWake(session, Date.now());
			if (!attempt) return;
			cwd = attempt.cwd;
			const file = attempt.file;
			const exists = file && await stat(file).then(info => info.isFile(), error => {
				if (error.code === 'ENOENT') return false;
				throw error;
			});
			if (exists) sessionArgs = ['--session', file];
			else {
				if (!attempt.model || !attempt.thinking) throw new Error('The unsaved thread has no recorded model or thinking level.');
				expectedModel = attempt.model;
				expectedThinking = attempt.thinking;
				sessionArgs = ['--session-id', session, '--name', title, ...launchModelArgs(expectedModel, expectedThinking)];
			}
		}
		const work = await workingDirectory(cwd);
		const token = randomUUID();
		const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('HERDR_') && !['PI_SESSION_FILE', 'PI_SESSION_ID'].includes(name)));
		const managedPi = join(homedir(), '.pi', 'agent', 'bin', 'pi');
		const pi = await stat(managedPi).then(file => file.isFile() ? managedPi : 'pi', () => 'pi');
		const child = spawn(pi, ['--mode', 'rpc', ...sessionArgs], { cwd: work,
			env: { ...env, PI_THREAD_LAUNCH: session, PI_THREAD_WORKER: '1', PI_THREAD_WORKER_TOKEN: token,
				PI_THREAD_EXPECTED_MODEL: expectedModel, PI_THREAD_EXPECTED_THINKING: expectedThinking },
			stdio: ['pipe', 'ignore', 'ignore', WORKER_LOCK_FD] });
		child.stdin.on('error', () => {});
		let stopped = false;
		const exit = exited(child).catch(() => 1).finally(() => { stopped = true; });
		process.once('SIGTERM', () => child.stdin.end());
		const deadline = Date.now() + WORKER_START_MS;
		let ready = false;
		try {
			while (!(ready = store.workerReady(session, token)) && !stopped && Date.now() < deadline) await pause(250);
		} finally {
			if (!ready && !stopped) {
				child.stdin.end();
				const forceExit = setTimeout(() => child.kill('SIGKILL'), 5000);
				await exit;
				clearTimeout(forceExit);
			}
		}
		if (!ready) throw new Error('Pi did not register its inbox.');
		process.exitCode = (await exit) ?? 1;
	} finally {
		// Registering is not proof of successful startup: Pi may exit before claiming its first request.
		if (attempt) store.wakeFailed(session, attempt.attempts, Date.now());
	}
}

async function workingDirectory(cwd) {
	const home = await realpath(homedir());
	const work = await realpath(cwd || home);
	const within = relative(home, work);
	if (isAbsolute(within) || within === '..' || within.startsWith('../') || !(await stat(work)).isDirectory()) throw new Error('Choose a working directory on the target machine under the home directory.');
	return work;
}

async function launch({ mode, title, cwd, model, thinking }) {
	if (!['standalone', 'herdr'].includes(mode) || typeof title !== 'string' || !title.trim() || title.length > 90 || /^[\s-]/u.test(title) || /[\u0000-\u001f\u007f-\u009f]/u.test(title)) throw new Error('Invalid thread launch options.');
	const modelArgs = launchModelArgs(model, thinking);
	const work = await workingDirectory(cwd);
	const launchId = randomUUID();
	let child;
	if (mode === 'standalone') {
		child = await startWorker(launchId, title, 'launch', work, ...modelArgs);
		if (!child) throw new Error('Could not start the standalone worker.');
	} else {
		const herdr = async (args, timeout = 8000) => JSON.parse((await exec('herdr', args, { timeout })).stdout).result;
		const { workspaces } = await herdr(['workspace', 'list']);
		const workspace = workspaces.find(w => w.focused) ?? workspaces[0];
		if (!workspace) throw new Error('No running Herdr workspace; use standalone or open Herdr separately.');
		const { root_pane } = await herdr(['tab', 'create', '--workspace', workspace.workspace_id, '--cwd', work, '--label', title, '--env', `PI_THREAD_LAUNCH=${launchId}`, '--no-focus']);
		try { await herdr(['agent', 'start', `pi-${launchId.slice(0, 8)}`, '--kind', 'pi', '--pane', root_pane.pane_id, '--', '--name', title, ...modelArgs], 32_000); }
		catch { throw new Error(`Created Herdr pane ${root_pane.pane_id}, but Pi did not start cleanly. Check the pane rather than launching again.`); }
	}
	const deadline = Date.now() + (mode === 'standalone' ? WORKER_START_MS + 1000 : 15_000);
	while (Date.now() < deadline) {
		if (child && (child.exitCode !== null || child.signalCode !== null)) {
			throw new Error(`Standalone Pi worker exited before registration (${child.signalCode ?? `exit code ${child.exitCode}`}).`);
		}
		const thread = (await request({ op: 'list' })).find(candidate => candidate.launchId === launchId);
		if (thread) return thread;
		await pause(250);
	}
	throw new Error(`${mode === 'standalone' ? 'Standalone Pi worker' : 'Herdr Pi'} registration timed out. Check discovery before starting another thread.`);
}

export function launchModelArgs(model, thinking) {
	if (model !== undefined && (typeof model !== 'string' || model.length > 200 || !/^[a-z0-9][a-z0-9._-]*\/[a-z0-9][a-z0-9._/:-]*$/i.test(model))) throw new Error('Choose an exact Pi provider/model ID.');
	if (thinking !== undefined && !['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'].includes(thinking)) throw new Error('Choose a Pi thinking level.');
	return [...(model ? ['--model', model] : []), ...(thinking ? ['--thinking', thinking] : [])];
}

async function main() {
	if (process.argv[2] === 'registry') {
		console.log(await registry());
	} else if (process.argv[2] === 'link') {
		await link(process.argv[3], process.argv[4]);
	} else if (process.argv[2] === 'rpc') {
		try {
			const chunks = [];
			let size = 0;
			for await (const chunk of process.stdin) {
				size += chunk.length;
				if (size > limit) throw new Error('Request is too large.');
				chunks.push(chunk);
			}
			console.log(JSON.stringify({ result: await dispatch(JSON.parse(Buffer.concat(chunks).toString('utf8'))) }));
		} catch (error) {
			console.log(JSON.stringify({ error: String(error.message).slice(0, 512) }));
		}
	} else if (process.argv[2] === 'worker') {
		await worker(...process.argv.slice(3));
	}
}

function isMain() {
	try { return !!process.argv[1] && realpathSync(process.argv[1]) === realpathSync(cli); }
	catch { return false; }
}
if (isMain()) void main().catch(error => { console.error(error.message); process.exitCode = 1; });
