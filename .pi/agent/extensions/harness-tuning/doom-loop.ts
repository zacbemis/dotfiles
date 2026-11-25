import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { stripAnsi } from "./bash-hygiene.ts";

const DEFAULT_CONSECUTIVE_LIMIT = 3;
const DEFAULT_EDIT_FAILURE_LIMIT = 3;
const DEFAULT_BASH_ERROR_LIMIT = 3;
const ERROR_SIGNATURE_TAIL_CHARS = 800;

export interface DoomLoopOptions {
	readonly consecutiveLimit?: number;
	readonly editFailureLimit?: number;
	readonly bashErrorLimit?: number;
}

export interface DoomLoopToolEvent {
	readonly cwd: string;
	readonly toolName: string;
	readonly input: Record<string, unknown>;
	readonly isError: boolean;
	readonly resultText: string;
}

function canonicalizeValue(value: unknown): unknown {
	if (Array.isArray(value)) {
		return value.map(canonicalizeValue);
	}
	if (value !== null && typeof value === "object") {
		const record = value as Record<string, unknown>;
		const sorted: Record<string, unknown> = {};
		for (const key of Object.keys(record).sort()) {
			sorted[key] = canonicalizeValue(record[key]);
		}
		return sorted;
	}
	return value;
}

export function canonicalToolCallKey(toolName: string, input: Record<string, unknown>): string {
	return `${toolName}:${JSON.stringify(canonicalizeValue(input))}`;
}

export function normalizeBashErrorSignature(text: string): string {
	const cleaned = stripAnsi(text)
		.replace(/\r\n?/g, "\n")
		// Strip ISO timestamps, epoch-like numbers, temp output paths, and wall durations so identical failures hash identically.
		.replace(/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?/g, "<TS>")
		.replace(/\/tmp\/pi-[^\s\]]+/g, "<TMP>")
		.replace(/\b\d+(?:\.\d+)?\s*(?:ms|s|sec|seconds)\b/gi, "<DUR>")
		.trim();
	const tail = cleaned.length > ERROR_SIGNATURE_TAIL_CHARS ? cleaned.slice(-ERROR_SIGNATURE_TAIL_CHARS) : cleaned;
	return createHash("sha256").update(tail).digest("hex").slice(0, 16);
}

function normalizePath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

function extractPatchTargets(cwd: string, patchText: string): string[] {
	const targets: string[] = [];
	for (const line of patchText.split(/\r?\n/)) {
		const trimmed = line.trim();
		for (const prefix of ["*** Update File: ", "*** Delete File: ", "*** Add File: "]) {
			if (trimmed.startsWith(prefix)) {
				const raw = trimmed.slice(prefix.length).trim();
				if (raw) targets.push(normalizePath(cwd, raw));
			}
		}
	}
	return [...new Set(targets)];
}

function extractTargetPaths(cwd: string, toolName: string, input: Record<string, unknown>): string[] {
	if (toolName === "patch" && typeof input.patch === "string") {
		return extractPatchTargets(cwd, input.patch);
	}
	if (typeof input.path === "string" && input.path.trim()) {
		return [normalizePath(cwd, input.path.trim())];
	}
	return [];
}

export function createDoomLoopTracker(options?: DoomLoopOptions) {
	const consecutiveLimit = options?.consecutiveLimit ?? DEFAULT_CONSECUTIVE_LIMIT;
	const editFailureLimit = options?.editFailureLimit ?? DEFAULT_EDIT_FAILURE_LIMIT;
	const bashErrorLimit = options?.bashErrorLimit ?? DEFAULT_BASH_ERROR_LIMIT;

	let lastCallKey: string | undefined;
	let consecutiveCount = 0;
	const editFailures = new Map<string, number>();
	const bashErrors = new Map<string, { signature: string; count: number }>();

	return {
		reset(): void {
			lastCallKey = undefined;
			consecutiveCount = 0;
			editFailures.clear();
			bashErrors.clear();
		},

		recordToolResult(event: DoomLoopToolEvent): string | undefined {
			const callKey = canonicalToolCallKey(event.toolName, event.input);
			if (callKey === lastCallKey) {
				consecutiveCount++;
			} else {
				lastCallKey = callKey;
				consecutiveCount = 1;
			}

			let editNotice: string | undefined;
			if (event.toolName === "read" && !event.isError) {
				for (const target of extractTargetPaths(event.cwd, event.toolName, event.input)) {
					editFailures.delete(target);
				}
			} else if (event.toolName === "edit" || event.toolName === "patch" || event.toolName === "write") {
				const targets = extractTargetPaths(event.cwd, event.toolName, event.input);
				if (!event.isError) {
					for (const target of targets) {
						editFailures.delete(target);
					}
				} else {
					for (const target of targets) {
						const count = (editFailures.get(target) ?? 0) + 1;
						editFailures.set(target, count);
						if (count >= editFailureLimit && !editNotice) {
							editNotice = `[Harness notice: ${event.toolName} has failed ${count} times on ${target} without a fresh read. Re-read the surrounding lines before attempting another edit.]`;
						}
					}
				}
			}

			let bashNotice: string | undefined;
			if (event.toolName === "bash" && typeof event.input.command === "string") {
				const command = event.input.command.trim();
				if (!event.isError) {
					bashErrors.delete(command);
				} else if (command) {
					const signature = normalizeBashErrorSignature(event.resultText);
					const prev = bashErrors.get(command);
					const count = prev && prev.signature === signature ? prev.count + 1 : 1;
					bashErrors.set(command, { signature, count });
					if (count >= bashErrorLimit) {
						bashNotice = `[Harness notice: This command has failed with the same error ${count} times in a row. Step back, verify your assumptions against the actual files and error trace, and change strategy before retrying.]`;
					}
				}
			}

			if (consecutiveCount >= consecutiveLimit) {
				return `[Harness notice: You have run this exact ${event.toolName} call ${consecutiveCount} times consecutively. Stop repeating the same call—inspect the output carefully, try a different approach, or ask the user if blocked.]`;
			}
			return editNotice ?? bashNotice;
		},
	};
}
