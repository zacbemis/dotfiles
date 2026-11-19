import { execFile } from "node:child_process";
import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import { linkedRequest, request } from "./bridge.mjs";

export interface Machine {
	name: string;
	ssh?: string;
	via?: string;
	offer?: string;
}

export const isLocal = (machine: Machine) => !machine.ssh && !machine.via;
const isAlias = (value: unknown): value is string => typeof value === "string" && /^[a-z0-9][a-z0-9-]{0,39}$/.test(value);
const isAddress = (value: unknown): value is string => typeof value === "string" && /^(?:[\w][\w.-]*@)?[a-zA-Z0-9][a-zA-Z0-9.-]*$/.test(value);

interface Result {
	stdout: string;
	stderr: string;
	code: number;
}

export const shellArgument = (arg: string) => `'${arg.replaceAll("'", "'\\''")}'`;

export function parseMachines(value: unknown): Machine[] {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Expected a map of machine names to SSH addresses or null (local).");
	return [{ name: "local" }, ...Object.entries(value).map(([name, ssh]) => {
		if (name === "local" || !isAlias(name)) throw new Error(`Invalid remote-thread machine name: ${name}`);
		if (ssh === null) return { name, ssh: undefined };
		if (isAddress(ssh)) return { name, ssh };
		if (ssh && typeof ssh === "object") {
			const link = ssh as Record<string, unknown>;
			if (isAlias(link.via) && Object.keys(link).length === 1) return { name, via: link.via };
			if (isAddress(link.ssh) && isAlias(link.offer) && Object.keys(link).length === 2) return { name, ssh: link.ssh, offer: link.offer };
		}
		throw new Error(`Invalid SSH address or link configuration for ${name}.`);
	})];
}

function run(command: string, args: string[], timeout: number, signal?: AbortSignal, input?: Buffer): Promise<Result> {
	signal?.throwIfAborted();
	return new Promise((resolve) => {
		const child = execFile(command, args, { timeout, maxBuffer: 384 * 1024, signal, killSignal: "SIGKILL" }, (error, stdout, stderr) => {
			const fallback = error ? `${command} did not complete (${error.code ?? error.signal ?? error.name})` : "";
			resolve({ stdout, stderr: stderr || fallback, code: typeof error?.code === "number" ? error.code : error ? 1 : 0 });
		});
		child.stdin?.on("error", () => {});
		child.stdin?.end(input);
	});
}

function ssh(machine: string, command: string, timeout: number, signal?: AbortSignal, input?: Buffer) {
	return run("ssh", ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5", "-o", "ClearAllForwardings=yes", "-o", "ForwardAgent=no", "--", machine, command], timeout, signal, input);
}

export function herdr(machine: Machine, args: string[], signal?: AbortSignal, timeout = 10_000) {
	if (machine.via) throw new Error("Herdr terminal fallback is unavailable over a native return link.");
	if (machine.ssh) return ssh(machine.ssh, ["herdr", ...args].map(shellArgument).join(" "), timeout, signal);
	if (process.env.HERDR_ENV !== "1") throw new Error("This Pi isn't inside a local Herdr session.");
	return run("herdr", args, timeout, signal);
}

export async function callBridge<T>(machine: Machine, payload: object, signal?: AbortSignal, timeout = 8_000): Promise<T> {
	signal?.throwIfAborted();
	if (machine.via) return await linkedRequest(machine.via, payload) as T;
	if (!machine.ssh) return await request(payload) as T;
	const output = await ssh(machine.ssh, 'node "$HOME/.pi/agent/extensions/remote-thread/bridge.mjs" rpc', timeout, signal, Buffer.from(JSON.stringify(payload)));
	if (output.code !== 0) throw new Error(`Native transport: ${failure(output)}`);
	const response = JSON.parse(output.stdout);
	if (response.error) throw new Error(response.error);
	return response.result as T;
}

export function failure(result: Result): string {
	try {
		const error = JSON.parse(result.stderr)?.error;
		if (typeof error?.code === "string") return `${error.code}: ${error.message ?? ""}`.slice(0, 320);
	} catch { /* Not every SSH/Herdr error is JSON. */ }
	return result.stderr.split("\n", 1)[0].slice(0, 320) || `Exited with code ${result.code}`;
}

export async function stage(machine: Machine, bytes: Buffer, signal?: AbortSignal): Promise<string> {
	if (machine.via) return callBridge<string>(machine, { op: "stage", bytes: bytes.toString("base64") }, signal);
	if (!machine.ssh) {
		const dir = await mkdtemp("/tmp/pi-thread.");
		await chmod(dir, 0o700);
		await writeFile(`${dir}/attachment`, bytes, { mode: 0o600, flag: "wx", signal });
		return `${dir}/attachment`;
	}
	const result = await ssh(machine.ssh, 'umask 077; dir=$(mktemp -d /tmp/pi-thread.XXXXXXXX) && tee "$dir/attachment" >/dev/null && printf "%s\\n" "$dir/attachment"', 15_000, signal, bytes);
	if (result.code !== 0) throw new Error(`Attachment upload failed: ${failure(result)}`);
	const path = result.stdout.trim();
	if (!/^\/tmp\/pi-thread\.[A-Za-z0-9]+\/attachment$/.test(path)) throw new Error("Attachment upload returned an unexpected path; no message was sent.");
	return path;
}
