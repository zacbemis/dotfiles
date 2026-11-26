import { appendFileSync, existsSync, writeFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { setTimeout as pause } from 'node:timers/promises';
import { register } from '../../.pi/agent/extensions/remote-thread/bridge.mjs';
import { mailbox } from '../../.pi/agent/extensions/remote-thread/mailbox.mjs';

const [, , ...args] = process.argv;
const { PI_THREAD_LAUNCH: session, PI_THREAD_WORKER_TOKEN: token, PI_THREAD_MAILBOX_DIR: root } = process.env;
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
const file = join(root, `${session}.jsonl`);
const stop = join(root, `stop-${token}`);
let eof = false;
process.stdin.resume();
process.stdin.once('end', () => { eof = true; });
appendFileSync(join(root, 'boots'), `${JSON.stringify({ session, token, args })}\n`);
while (!eof && existsSync(join(root, 'hold-registration'))) await pause(25);
if (!eof) {
	const endpoint = randomUUID();
	const saved = option('--session') && existsSync(file);
	const info = { session, launchId: session, endpoint, cwd: process.cwd(), file, title: 'Worker test',
		worker: true, workerToken: token, model: saved ? 'test/persisted' : option('--model'), thinking: saved ? 'low' : option('--thinking') };
	const close = await register(endpoint, () => info);
	const store = mailbox();
	store.rememberThread(info);
	while (!eof && !existsSync(stop)) {
		const task = store.claim(session, endpoint);
		if (task) {
			writeFileSync(file, 'fake persisted session');
			store.finish(session, task.id, endpoint, 'completed', `${info.model}/${info.thinking}`);
		}
		await pause(25);
	}
	close();
	store.close();
}
process.stdin.destroy();
writeFileSync(join(root, `done-${token}`), '');
