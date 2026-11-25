import { randomBytes } from "node:crypto";
import { open, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const BASH_HYGIENE_DISABLE_ENV = "PI_HARNESS_BASH_HYGIENE";

const DEFAULT_MAX_BYTES = 16 * 1024;
const DEFAULT_MAX_LINES = 200;
const FULL_CLEAN_READ_LIMIT_BYTES = 256 * 1024;
const HEAD_READ_BYTES = 48 * 1024;
const TAIL_READ_BYTES = 96 * 1024;
const DEFAULT_REPEAT_THRESHOLD = 4;

// CSI, OSC, charset selection, and 2-byte ESC terminal control sequences.
const ANSI_ESCAPE_RE =
	/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[()][0-2AB]|\x1b[@-Z\\-_]/g;

const TRAILING_STATUS_PATTERNS = [
	/\n\nCommand exited with code \d+$/,
	/\n\nCommand timed out after [^\n]+$/,
	/\n\nCommand aborted$/,
	/\n\nCommand terminated without an exit code$/,
];

const COMMIT_OR_PR_COMMAND_RE = /(?:^|[\n;&|()]\s*)(?:git\b[^\n;&|]*\bcommit\b|gh\s+pr\s+(?:create|edit)\b)/;
const AI_ATTRIBUTION_PATTERNS = [
	/\bco-authored-by\s*:[^\n]*(?:claude|anthropic|codex|openai|gemini|copilot|antigravity|\bai\b)/i,
	/\b(?:generated|authored|written|created)\s+(?:with|by)\s+(?:\[?\s*)?(?:claude|anthropic|codex|copilot|cursor|antigravity|\bai\b)/i,
	/noreply@anthropic\.com/i,
];

export function checkCommitAttributionGuard(command: string): { block: true; reason: string } | undefined {
	if (!COMMIT_OR_PR_COMMAND_RE.test(command)) return undefined;
	if (AI_ATTRIBUTION_PATTERNS.some((pattern) => pattern.test(command))) {
		return {
			block: true,
			reason: "Remove AI/Claude attribution (Co-Authored-By / Generated with) from the commit or PR message and retry.",
		};
	}
	return undefined;
}

export interface BashToolDetailsLike {
	readonly truncation?: {
		readonly truncated?: boolean;
		readonly totalLines?: number;
		readonly totalBytes?: number;
	};
	readonly fullOutputPath?: string;
}

export interface BashHygieneOptions {
	readonly maxBytes?: number;
	readonly maxLines?: number;
	readonly repeatThreshold?: number;
}

export function stripAnsi(text: string): string {
	return text.includes("\x1b") ? text.replace(ANSI_ESCAPE_RE, "") : text;
}

export function collapseCarriageReturns(text: string): string {
	const normalized = text.includes("\r\n") ? text.replace(/\r\n/g, "\n") : text;
	if (!normalized.includes("\r")) return normalized;

	const lines = normalized.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i]!;
		if (!line.includes("\r")) continue;
		const segments = line.split("\r");
		let finalFrame = "";
		for (let j = segments.length - 1; j >= 0; j--) {
			if (segments[j]!.length > 0) {
				finalFrame = segments[j]!;
				break;
			}
		}
		lines[i] = finalFrame;
	}
	return lines.join("\n");
}

export function collapseRepeatedLines(text: string, threshold = DEFAULT_REPEAT_THRESHOLD): string {
	const lines = text.split("\n");
	if (lines.length < threshold) return text;

	const out: string[] = [];
	let i = 0;
	while (i < lines.length) {
		const current = lines[i]!;
		let runEnd = i + 1;
		while (runEnd < lines.length && lines[runEnd] === current) {
			runEnd++;
		}
		const runLength = runEnd - i;
		if (runLength >= threshold) {
			if (current === "") {
				out.push("", "");
			} else {
				out.push(current, `[... repeated ${runLength - 1} more times ...]`);
			}
		} else {
			for (let k = i; k < runEnd; k++) {
				out.push(lines[k]!);
			}
		}
		i = runEnd;
	}
	return out.join("\n");
}

export function cleanTerminalOutput(text: string, repeatThreshold = DEFAULT_REPEAT_THRESHOLD): string {
	if (!text) return text;
	const noAnsi = stripAnsi(text);
	const noCr = collapseCarriageReturns(noAnsi);
	return collapseRepeatedLines(noCr, repeatThreshold);
}

function formatSize(bytes: number): string {
	if (bytes < 1024) return `${bytes}B`;
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

function takeHeadLines(text: string, maxLines: number, maxBytes: number): { content: string; lineCount: number } {
	const lines = text.split("\n");
	const kept: string[] = [];
	let bytes = 0;
	for (let i = 0; i < lines.length && kept.length < maxLines; i++) {
		const line = lines[i]!;
		const lineBytes = Buffer.byteLength(line, "utf-8") + (kept.length > 0 ? 1 : 0);
		if (bytes + lineBytes > maxBytes) break;
		kept.push(line);
		bytes += lineBytes;
	}
	return { content: kept.join("\n"), lineCount: kept.length };
}

function takeTailLines(text: string, maxLines: number, maxBytes: number): { content: string; lineCount: number } {
	const lines = text.split("\n");
	const kept: string[] = [];
	let bytes = 0;
	for (let i = lines.length - 1; i >= 0 && kept.length < maxLines; i--) {
		const line = lines[i]!;
		const lineBytes = Buffer.byteLength(line, "utf-8") + (kept.length > 0 ? 1 : 0);
		if (bytes + lineBytes > maxBytes) {
			if (kept.length === 0) {
				const buf = Buffer.from(line, "utf-8");
				let start = Math.max(0, buf.length - maxBytes);
				while (start < buf.length && (buf[start]! & 0xc0) === 0x80) start++;
				kept.unshift(buf.subarray(start).toString("utf-8"));
			}
			break;
		}
		kept.unshift(line);
		bytes += lineBytes;
	}
	return { content: kept.join("\n"), lineCount: kept.length };
}

export function buildHeadTailSlice(
	headText: string,
	tailText: string,
	options: {
		readonly fullOutputPath: string;
		readonly totalBytes: number;
		readonly maxBytes?: number;
		readonly maxLines?: number;
	},
): string {
	const maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
	const maxLines = options.maxLines ?? DEFAULT_MAX_LINES;
	const headBudgetBytes = Math.max(1024, Math.floor(maxBytes * 0.25));
	const tailBudgetBytes = Math.max(2048, maxBytes - headBudgetBytes);
	const headBudgetLines = Math.max(20, Math.floor(maxLines * 0.25));
	const tailBudgetLines = Math.max(40, maxLines - headBudgetLines);

	const head = takeHeadLines(headText, headBudgetLines, headBudgetBytes);
	const tail = takeTailLines(tailText, tailBudgetLines, tailBudgetBytes);

	const marker = `[... middle omitted (total ${formatSize(options.totalBytes)}). Full output: ${options.fullOutputPath} ...]`;
	if (!head.content) return `${marker}\n\n${tail.content}`;
	if (!tail.content) return `${head.content}\n\n${marker}`;
	return `${head.content}\n\n${marker}\n\n${tail.content}`;
}

function extractTrailingStatus(text: string, isError: boolean): string {
	if (!isError) return "";
	for (const pattern of TRAILING_STATUS_PATTERNS) {
		const match = pattern.exec(text);
		if (match) return match[0];
	}
	return "";
}

async function writeCleanTempLog(content: string): Promise<string | undefined> {
	const filePath = join(tmpdir(), `pi-bash-clean-${randomBytes(8).toString("hex")}.log`);
	try {
		await writeFile(filePath, content, "utf-8");
		return filePath;
	} catch {
		return undefined;
	}
}

async function readHeadAndTailFromFile(
	filePath: string,
	maxBytes: number,
	maxLines: number,
	repeatThreshold: number,
): Promise<string | undefined> {
	let handle;
	try {
		handle = await open(filePath, "r");
		const size = (await handle.stat()).size;
		if (size <= 0) return undefined;

		if (size <= FULL_CLEAN_READ_LIMIT_BYTES) {
			const fullRaw = await handle.readFile({ encoding: "utf-8" });
			const cleaned = cleanTerminalOutput(fullRaw, repeatThreshold);
			const cleanedBytes = Buffer.byteLength(cleaned, "utf-8");
			const cleanedLines = cleaned.split("\n").length;
			if (cleanedBytes <= maxBytes && cleanedLines <= maxLines) {
				return cleaned;
			}
			// Persist cleaned output so follow-up read/grep calls see ANSI-free, collapsed text.
			const cleanPath = (await writeCleanTempLog(cleaned)) ?? filePath;
			return buildHeadTailSlice(cleaned, cleaned, {
				fullOutputPath: cleanPath,
				totalBytes: size,
				maxBytes,
				maxLines,
			});
		}

		const headSize = Math.min(HEAD_READ_BYTES, size);
		const tailSize = Math.min(TAIL_READ_BYTES, size);
		const headBuf = Buffer.alloc(headSize);
		const tailBuf = Buffer.alloc(tailSize);
		await handle.read(headBuf, 0, headSize, 0);
		await handle.read(tailBuf, 0, tailSize, size - tailSize);

		// Streaming decode drops an incomplete trailing UTF-8 sequence in head; skip continuation bytes in tail.
		let headText = new TextDecoder().decode(headBuf, { stream: true });
		const lastHeadNewline = headText.lastIndexOf("\n");
		if (lastHeadNewline > 0) headText = headText.slice(0, lastHeadNewline);

		let tailStart = 0;
		while (tailStart < tailBuf.length && (tailBuf[tailStart]! & 0xc0) === 0x80) tailStart++;
		let tailText = new TextDecoder().decode(tailBuf.subarray(tailStart));
		const firstTailNewline = tailText.indexOf("\n");
		if (firstTailNewline !== -1 && firstTailNewline + 1 < tailText.length) {
			tailText = tailText.slice(firstTailNewline + 1);
		}

		return buildHeadTailSlice(
			cleanTerminalOutput(headText, repeatThreshold),
			cleanTerminalOutput(tailText, repeatThreshold),
			{
				fullOutputPath: filePath,
				totalBytes: size,
				maxBytes,
				maxLines,
			},
		);
	} catch {
		return undefined;
	} finally {
		await handle?.close();
	}
}

export async function sanitizeBashToolResult(
	text: string,
	details: BashToolDetailsLike | undefined,
	isError: boolean,
	options?: BashHygieneOptions,
): Promise<{ text: string; changed: boolean }> {
	if (process.env[BASH_HYGIENE_DISABLE_ENV] === "0") {
		return { text, changed: false };
	}

	const maxBytes = options?.maxBytes ?? DEFAULT_MAX_BYTES;
	const maxLines = options?.maxLines ?? DEFAULT_MAX_LINES;
	const repeatThreshold = options?.repeatThreshold ?? DEFAULT_REPEAT_THRESHOLD;

	const statusSuffix = extractTrailingStatus(text, isError);
	if (details?.truncation?.truncated && details.fullOutputPath) {
		const replaced = await readHeadAndTailFromFile(details.fullOutputPath, maxBytes, maxLines, repeatThreshold);
		if (replaced !== undefined) {
			const finalText = `${replaced}${statusSuffix}`;
			return { text: finalText, changed: finalText !== text };
		}
	}

	const body = statusSuffix ? text.slice(0, text.length - statusSuffix.length) : text;
	const cleaned = cleanTerminalOutput(body, repeatThreshold);
	const cleanedBytes = Buffer.byteLength(cleaned, "utf-8");
	const cleanedLines = cleaned.split("\n").length;

	if (cleanedBytes > maxBytes || cleanedLines > maxLines) {
		const spilledPath = await writeCleanTempLog(cleaned);
		if (spilledPath) {
			const sliced = buildHeadTailSlice(cleaned, cleaned, {
				fullOutputPath: spilledPath,
				totalBytes: Buffer.byteLength(body, "utf-8"),
				maxBytes,
				maxLines,
			});
			const finalText = `${sliced}${statusSuffix}`;
			return { text: finalText, changed: finalText !== text };
		}
	}

	const finalText = `${cleaned}${statusSuffix}`;
	return { text: finalText, changed: finalText !== text };
}
