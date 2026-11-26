import { addAbortListener } from "node:events";
import { setTimeout as pause } from "node:timers/promises";

const PEER_BASH_TIMEOUT_SECONDS = 300;
export const REPLY_WAIT_MS = 38_000;
export const ORCHESTRATOR_WARM_MIN_SAVINGS = 0.05;

export function decideOrchestratorCacheWarming(
	event: { action: "warm" | "stop"; warmCost: number; missCost: number },
	awaitingPeer: boolean,
): { action: "warm" } | undefined {
	if (event.action !== "stop" || !awaitingPeer) return undefined;
	// Pi's idle policy assumes a 15% continuation probability; an orchestrator awaiting
	// an active peer wake is effectively certain to resume once the peer settles.
	return event.missCost - event.warmCost >= ORCHESTRATOR_WARM_MIN_SAVINGS ? { action: "warm" } : undefined;
}

export function coordinateBash(input: { command: string; timeout?: number }, peerTurn: boolean) {
	if (/(?:^|[\n;&|])\s*(?:nohup\s+)(?:[^\s;&|]+\/)?pi(?=\s|$)|\b(?:while|until)\s+!?\s*kill\s+(?:-0|-s\s+0)\s/u.test(input.command)) {
		return { block: true, reason: "Do not launch a Pi peer with nohup or wait in a PID polling loop. Use remote_thread launch/send. Send waits for the peer's result; use receipts to recover a pending handoff without resending." };
	}
	if (peerTurn && (input.timeout === undefined || input.timeout > PEER_BASH_TIMEOUT_SECONDS)) input.timeout = PEER_BASH_TIMEOUT_SECONDS;
}

export async function waitForReceipt<T>(initial: T, refresh: (signal: AbortSignal) => Promise<T>, settled: (result: T) => boolean,
	timeoutMs: number, signal?: AbortSignal) {
	const timeout = AbortSignal.timeout(timeoutMs);
	const budget = signal ? AbortSignal.any([signal, timeout]) : timeout;
	let result = initial;
	try {
		while (!settled(result)) {
			budget.throwIfAborted();
			// A native refresh can be shared with the outbox. Stop waiting without cancelling it.
			let listener: ReturnType<typeof addAbortListener> | undefined;
			try {
				result = await Promise.race([refresh(budget), new Promise<never>((_, reject) => {
					listener = addAbortListener(budget, () => reject(budget.reason));
				})]);
			} finally {
				listener?.[Symbol.dispose]();
			}
			if (!settled(result)) await pause(1200, undefined, { signal: budget });
		}
	} catch (error) {
		signal?.throwIfAborted();
		if (!timeout.aborted || (error !== timeout.reason && (error as Error | undefined)?.cause !== timeout.reason)) throw error;
		return { result, waitTimedOut: true };
	}
	signal?.throwIfAborted();
	return { result, waitTimedOut: false };
}
