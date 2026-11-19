const PEER_BASH_TIMEOUT_SECONDS = 300;

export function coordinateBash(input: { command: string; timeout?: number }, peerTurn: boolean) {
	if (/(?:^|[\n;&|])\s*(?:nohup\s+)(?:[^\s;&|]+\/)?pi(?=\s|$)|\b(?:while|until)\s+!?\s*kill\s+(?:-0|-s\s+0)\s/u.test(input.command)) {
		return { block: true, reason: "Do not launch a Pi peer with nohup or wait in a PID polling loop. Use remote_thread launch/send, send with wait:false, and end the turn. To check progress, use reply with the existing receipt." };
	}
	if (peerTurn && (input.timeout === undefined || input.timeout > PEER_BASH_TIMEOUT_SECONDS)) input.timeout = PEER_BASH_TIMEOUT_SECONDS;
}
