import { chmodSync, lstatSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const validId = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);
const isName = value => typeof value === 'string' && /^[a-z0-9][a-z0-9-]{0,39}$/.test(value);
export const isFinal = state => ['completed', 'failed', 'interrupted', 'cancelled'].includes(state);
const MAX_ATTACHMENT = 1024 * 1024;
const MAX_WAKE_ATTEMPTS = 3;
const WAKE_BACKOFF_MS = 5000;
const WAKE_FAILED = 'The receiving Pi could not restart after three attempts. Open it manually or launch a new thread.';

export function validateEnvelope({ id, session, source, text, attachment, filename }) {
	if (!validId(id) || !validId(session) || !validId(source) || source === session || typeof text !== 'string' ||
		!text.trim() || Buffer.byteLength(text) > 12_000 || /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/u.test(text)) throw new Error('Invalid peer request.');
	if (attachment == null && filename == null) return;
	if (typeof attachment !== 'string' || attachment.length > 1_398_104 || Buffer.from(attachment, 'base64').length > MAX_ATTACHMENT ||
		typeof filename !== 'string' || !/^[\w.-]{1,255}$/.test(filename) || filename === '.' || filename === '..') throw new Error('Invalid attachment.');
}

export class Mailbox {
	#db;

	constructor(directory) {
		mkdirSync(directory, { recursive: true, mode: 0o700 });
		const stat = lstatSync(directory);
		if (!stat.isDirectory() || stat.uid !== process.getuid?.() || (stat.mode & 0o777) !== 0o700) throw new Error('Unsafe Pi mailbox directory; expected a private directory owned by this account.');
		const file = join(directory, 'mail.sqlite3');
		this.#db = new DatabaseSync(file);
		chmodSync(file, 0o600);
		this.#db.exec(`
			PRAGMA busy_timeout = 3000;
			PRAGMA journal_mode = WAL;
			PRAGMA synchronous = FULL;
			CREATE TABLE IF NOT EXISTS threads (
				session TEXT PRIMARY KEY, title TEXT, cwd TEXT, mode TEXT, seen INTEGER NOT NULL
			);
			CREATE TABLE IF NOT EXISTS targets (
				target TEXT PRIMARY KEY, machine TEXT NOT NULL, session TEXT NOT NULL, title TEXT, cwd TEXT, mode TEXT, seen INTEGER NOT NULL,
				UNIQUE(machine, session)
			);
			CREATE TABLE IF NOT EXISTS inbox (
				session TEXT NOT NULL, id TEXT NOT NULL, source TEXT NOT NULL, text TEXT NOT NULL, attachment TEXT, filename TEXT,
				state TEXT NOT NULL DEFAULT 'queued', owner TEXT, reply TEXT, created INTEGER NOT NULL,
				PRIMARY KEY(session, id)
			);
			CREATE UNIQUE INDEX IF NOT EXISTS inbox_running ON inbox(session) WHERE state = 'working';
			CREATE INDEX IF NOT EXISTS inbox_order ON inbox(session, state, created);
			CREATE TABLE IF NOT EXISTS outbox (
				source TEXT NOT NULL, id TEXT NOT NULL, target TEXT NOT NULL REFERENCES targets(target), text TEXT NOT NULL, attachment TEXT, filename TEXT,
				state TEXT NOT NULL DEFAULT 'pending', reply TEXT, created INTEGER NOT NULL, next_at INTEGER NOT NULL DEFAULT 0,
				failures INTEGER NOT NULL DEFAULT 0, notified INTEGER NOT NULL DEFAULT 0,
				PRIMARY KEY(source, id)
			);
			CREATE INDEX IF NOT EXISTS outbox_due ON outbox(source, state, next_at);
		`);
		const additions = [
			['file', 'TEXT'], ['worker', 'INTEGER NOT NULL DEFAULT 0'],
			['model', 'TEXT'], ['thinking', 'TEXT'], ['endpoint', 'TEXT'], ['worker_token', 'TEXT'],
			['wake_attempts', 'INTEGER NOT NULL DEFAULT 0'], ['wake_after', 'INTEGER NOT NULL DEFAULT 0'],
		];
		const columns = () => new Set(this.#sql('PRAGMA table_info(threads)').all().map(column => column.name));
		const existing = columns();
		if (additions.some(([name]) => !existing.has(name))) this.#transaction(() => {
			const current = columns();
			for (const [name, type] of additions) {
				if (!current.has(name)) this.#db.exec(`ALTER TABLE threads ADD COLUMN ${name} ${type}`);
			}
		});
		this.#db.exec(`CREATE TRIGGER IF NOT EXISTS reset_wake_after_claim
			AFTER UPDATE OF state ON inbox WHEN NEW.state='working'
			BEGIN UPDATE threads SET wake_attempts=0,wake_after=0 WHERE session=NEW.session AND wake_attempts>0; END;`);
	}

	#sql(sql) { return this.#db.prepare(sql); }
	#transaction(fn) {
		this.#db.exec('BEGIN IMMEDIATE');
		try {
			const result = fn();
			this.#db.exec('COMMIT');
			return result;
		} catch (error) {
			this.#db.exec('ROLLBACK');
			throw error;
		}
	}
	close() { this.#db.close(); }

	rememberThread(thread) {
		if (!validId(thread.session)) throw new Error('Invalid Pi session ID.');
		this.#sql(`INSERT INTO threads (session,title,cwd,mode,seen,file,worker,model,thinking,endpoint,worker_token)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT(session) DO UPDATE SET title=excluded.title,cwd=excluded.cwd,mode=excluded.mode,seen=excluded.seen,
				file=excluded.file,worker=excluded.worker,model=excluded.model,thinking=excluded.thinking,
				endpoint=excluded.endpoint,worker_token=excluded.worker_token`)
			.run(thread.session, thread.title ?? null, thread.cwd ?? null, thread.mode ?? null, Date.now(), thread.file ?? null, thread.worker ? 1 : 0,
				thread.model ?? null, thread.thinking ?? null, thread.endpoint ?? null, thread.workerToken ?? null);
	}

	wakeCandidate(session, now) {
		return this.#sql(`SELECT title,cwd,file,model,thinking,endpoint,wake_attempts AS attempts FROM threads
			WHERE session=? AND worker=1 AND wake_after<=?
			AND EXISTS(SELECT 1 FROM inbox WHERE inbox.session=threads.session AND state='queued')`).get(session, now);
	}

	beginWake(session, now) {
		return this.#transaction(() => {
			const thread = this.wakeCandidate(session, now);
			if (!thread) return;
			if (thread.attempts >= MAX_WAKE_ATTEMPTS) {
				this.#failQueuedWake(session);
				return;
			}
			const attempts = thread.attempts + 1;
			this.#sql('UPDATE threads SET wake_attempts=?,wake_after=? WHERE session=?')
				.run(attempts, now + WAKE_BACKOFF_MS * 2 ** (attempts - 1), session);
			return { ...thread, attempts };
		});
	}

	wakeFailed(session, attempts, now) {
		this.#transaction(() => {
			const row = this.#sql('SELECT wake_attempts FROM threads WHERE session=?').get(session);
			if (row?.wake_attempts !== attempts) return;
			if (attempts >= MAX_WAKE_ATTEMPTS) this.#failQueuedWake(session);
			else this.#sql('UPDATE threads SET wake_after=? WHERE session=?').run(now + WAKE_BACKOFF_MS * 2 ** (attempts - 1), session);
		});
	}

	#failQueuedWake(session) {
		this.#sql(`UPDATE inbox SET state='failed',reply=?,attachment=NULL WHERE session=? AND state='queued'`).run(WAKE_FAILED, session);
		this.#sql('UPDATE threads SET wake_attempts=0,wake_after=0 WHERE session=?').run(session);
	}

	workerReady(session, token) {
		return !!this.#sql('SELECT 1 FROM threads WHERE session=? AND worker_token=?').get(session, token);
	}

	threads() { return this.#sql('SELECT session,title,cwd,mode FROM threads ORDER BY seen DESC,session LIMIT 128').all(); }

	rememberTarget(machine, thread, target) {
		if (!validId(thread.session) || !validId(target) || !isName(machine)) throw new Error('Invalid native Pi target.');
		return this.#sql(`INSERT INTO targets VALUES (?, ?, ?, ?, ?, ?, ?)
			ON CONFLICT(machine,session) DO UPDATE SET title=excluded.title,cwd=excluded.cwd,mode=excluded.mode,seen=excluded.seen
			RETURNING target`).get(target, machine, thread.session, thread.title ?? null, thread.cwd ?? null, thread.mode ?? null, Date.now()).target;
	}

	targets(machine) { return this.#sql('SELECT target,session,title,cwd,mode FROM targets WHERE machine=? ORDER BY seen DESC,target LIMIT 128').all(machine); }
	target(id) { return this.#sql('SELECT target,machine,session,title,cwd,mode FROM targets WHERE target=?').get(id); }

	accept(envelope) {
		validateEnvelope(envelope);
		const { session, id, source, text, attachment, filename } = envelope;
		if (!this.#sql('SELECT 1 FROM threads WHERE session=?').get(session)) throw new Error('The native Pi session is unknown on this machine. Open or resume it once to register it.');
		this.#sql(`INSERT INTO inbox (session,id,source,text,attachment,filename,created) VALUES (?,?,?,?,?,?,?) ON CONFLICT(session,id) DO NOTHING`)
			.run(session, id, source, text, attachment ?? null, filename ?? null, Date.now());
		return this.incoming(session, id, source);
	}

	incoming(session, id, source) {
		if (!validId(session) || !validId(id) || !validId(source)) throw new Error('Invalid receipt.');
		return this.#sql('SELECT state AS status,reply FROM inbox WHERE session=? AND id=? AND source=?').get(session, id, source) ?? null;
	}

	cancel(session, id, source) {
		if (!validId(session) || !validId(id) || !validId(source)) throw new Error('Invalid receipt.');
		this.#sql(`UPDATE inbox SET state='cancelled',reply='Cancelled before delivery.',attachment=NULL
			WHERE session=? AND id=? AND source=? AND state='queued'`).run(session, id, source);
		return this.incoming(session, id, source);
	}

	running(session) { return this.#sql(`SELECT id,owner FROM inbox WHERE session=? AND state='working'`).get(session); }

	claim(session, owner) {
		return this.#sql(`UPDATE inbox SET state='working', owner=?
			WHERE rowid=(SELECT rowid FROM inbox WHERE session=? AND state='queued' ORDER BY created,rowid LIMIT 1)
			AND NOT EXISTS(SELECT 1 FROM inbox WHERE session=? AND state='working')
			RETURNING id,source,text,attachment,filename`).get(owner, session, session);
	}

	finish(session, id, owner, state, reply) {
		if (!isFinal(state)) throw new Error('Invalid terminal inbox state.');
		return this.#sql(`UPDATE inbox SET state=?,reply=?,attachment=NULL WHERE session=? AND id=? AND owner=? AND state='working'`)
			.run(state, reply, session, id, owner).changes === 1;
	}

	enqueue(source, id, target, text, attachment, filename) {
		const dest = this.target(target);
		if (!dest) throw new Error('Unknown native Pi target. List threads again.');
		validateEnvelope({ id, session: dest.session, source, text, attachment, filename });
		this.#sql('INSERT INTO outbox (source,id,target,text,attachment,filename,created) VALUES (?,?,?,?,?,?,?)')
			.run(source, id, target, text, attachment ?? null, filename ?? null, Date.now());
	}

	outgoing(source, id) {
		return this.#sql(`SELECT o.id,o.state AS status,o.text,o.attachment,o.filename,o.reply,o.failures,o.next_at AS nextAt,t.machine,t.session,t.title
			FROM outbox o JOIN targets t USING(target) WHERE o.source=? AND o.id=?`).get(source, id);
	}

	due(source, now) {
		return this.#sql(`SELECT id FROM outbox WHERE source=? AND state IN ('pending','queued','working') AND next_at<=?
			ORDER BY next_at,created LIMIT 8`).all(source, now).map(row => row.id);
	}

	defer(source, id, nextAt) {
		this.#sql(`UPDATE outbox SET failures=failures+1,next_at=? WHERE source=? AND id=? AND state IN ('pending','queued','working')`).run(nextAt, source, id);
	}

	updateOutgoing(source, id, expected, state, reply, nextAt) {
		if (!['queued', 'working'].includes(state) && !isFinal(state)) throw new Error('Invalid peer status.');
		this.#sql(`UPDATE outbox SET state=?, reply=?, attachment=NULL, failures=0, next_at=? WHERE source=? AND id=? AND state=?`)
			.run(state, reply ?? null, nextAt, source, id, expected);
	}

	notifications(source) {
		return this.#sql(`SELECT o.id,o.state AS status,o.reply,t.machine,t.title FROM outbox o JOIN targets t USING(target)
			WHERE o.source=? AND o.notified=0 AND o.state IN ('completed','failed','interrupted','cancelled') ORDER BY o.created LIMIT 16`).all(source);
	}

	acknowledge(source, id) { this.#sql('UPDATE outbox SET notified=1 WHERE source=? AND id=?').run(source, id); }

	receipts(source) {
		return this.#sql(`SELECT o.id AS receipt,o.state AS status,t.machine,t.title FROM outbox o JOIN targets t USING(target)
			WHERE o.source=? ORDER BY o.created DESC,o.rowid DESC LIMIT 24`).all(source);
	}

	hasActiveOutgoing(source) {
		return !!this.#sql(`SELECT 1 FROM outbox WHERE source=? AND state IN ('queued','working') LIMIT 1`).get(source);
	}
}

let shared;
export function mailbox() {
	return shared ??= new Mailbox(process.env.PI_THREAD_MAILBOX_DIR || join(homedir(), '.pi', 'agent', 'remote-thread-state'));
}
