import { access, open, readdir, readFile, stat } from "node:fs/promises";
import { basename, dirname, extname, isAbsolute, join, relative, resolve } from "node:path";
import { formatMissHint } from "./patch-parser.ts";

export const MAX_READ_LINE_CHARS = 2_000;
const BINARY_SNIFF_BYTES = 8_192;
const PAST_EOF_TAIL_LINES = 100;
const PAST_EOF_MAX_BYTES = 50 * 1024;
const DIR_LIST_MAX_ENTRIES = 200;

export function clampLongLines(text: string, maxChars = MAX_READ_LINE_CHARS): { text: string; changed: boolean } {
	let changed = false;
	const lines = text.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i]!;
		if (line.length > maxChars) {
			lines[i] = `${line.slice(0, maxChars)}... (line truncated to ${maxChars} chars)`;
			changed = true;
		}
	}
	return changed ? { text: lines.join("\n"), changed: true } : { text, changed: false };
}

export function resolveNegativeOffset(totalLines: number, offset: number): number {
	if (offset >= 0) return offset;
	return Math.max(1, totalLines + offset + 1);
}

export function countLines(content: string): number {
	if (content.length === 0) return 0;
	let lines = 1;
	for (let i = 0; i < content.length; i++) {
		if (content.charCodeAt(i) === 10) lines++;
	}
	return content.endsWith("\n") ? lines - 1 : lines;
}

function resolveUserPath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

export async function resolveReadOffsetFromDisk(cwd: string, rawPath: string, offset: number): Promise<number | undefined> {
	if (offset >= 0) return undefined;
	try {
		const content = await readFile(resolveUserPath(cwd, rawPath), "utf-8");
		return resolveNegativeOffset(countLines(content), offset);
	} catch {
		return undefined;
	}
}

export function hasImageMagic(bytes: Uint8Array): boolean {
	if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
		return true;
	}
	if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
		return true;
	}
	if (
		bytes.length >= 6 &&
		bytes[0] === 0x47 &&
		bytes[1] === 0x49 &&
		bytes[2] === 0x46 &&
		bytes[3] === 0x38 &&
		(bytes[4] === 0x37 || bytes[4] === 0x39) &&
		bytes[5] === 0x61
	) {
		return true;
	}
	if (
		bytes.length >= 12 &&
		bytes[0] === 0x52 &&
		bytes[1] === 0x49 &&
		bytes[2] === 0x46 &&
		bytes[3] === 0x46 &&
		bytes[8] === 0x57 &&
		bytes[9] === 0x45 &&
		bytes[10] === 0x42 &&
		bytes[11] === 0x50
	) {
		return true;
	}
	if (bytes.length >= 2 && bytes[0] === 0x42 && bytes[1] === 0x4d) {
		return true;
	}
	return false;
}

export async function detectBinaryFile(cwd: string, rawPath: string): Promise<boolean> {
	const absPath = resolveUserPath(cwd, rawPath);
	let handle;
	try {
		const info = await stat(absPath);
		if (!info.isFile() || info.size === 0) return false;
		handle = await open(absPath, "r");
		const size = Math.min(info.size, BINARY_SNIFF_BYTES);
		const buffer = Buffer.allocUnsafe(size);
		const { bytesRead } = await handle.read(buffer, 0, size, 0);
		const slice = buffer.subarray(0, bytesRead);
		if (hasImageMagic(slice)) return false;
		return slice.includes(0);
	} catch {
		return false;
	} finally {
		await handle?.close();
	}
}

export function canonicalFilename(name: string): string {
	return name
		.normalize("NFC")
		.replace(/[\u00a0\u202f]/g, " ")
		.replace(/[\u2018\u2019]/g, "'");
}

export async function resolveCanonicalSibling(cwd: string, rawPath: string): Promise<string | undefined> {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	const absPath = resolve(cwd, cleaned);
	try {
		await access(absPath);
		return undefined;
	} catch {
		// fall through to sibling lookup
	}

	const parentDir = dirname(absPath);
	const wanted = canonicalFilename(basename(absPath));
	try {
		const entries = await readdir(parentDir, { withFileTypes: true });
		const matches = entries.filter((entry) => entry.isFile() && canonicalFilename(entry.name) === wanted);
		if (matches.length !== 1) return undefined;
		const matchedName = matches[0]!.name;
		if (matchedName === basename(absPath)) return undefined;
		const prefix = rawPath.startsWith("@") ? "@" : "";
		return `${prefix}${join(dirname(cleaned), matchedName)}`;
	} catch {
		return undefined;
	}
}

function stemOf(name: string): string {
	return name.slice(0, name.length - extname(name).length) || name;
}

function editDistance(a: string, b: string): number {
	let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
	for (let i = 1; i <= a.length; i++) {
		const current = [i];
		for (let j = 1; j <= b.length; j++) {
			current[j] = Math.min(
				previous[j]! + 1,
				current[j - 1]! + 1,
				previous[j - 1]! + (a[i - 1] === b[j - 1] ? 0 : 1),
			);
		}
		previous = current;
	}
	return previous[b.length]!;
}

export function rankSimilarNames(names: readonly string[], requested: string): string[] {
	const lowerReq = requested.toLowerCase();
	const wantedStem = stemOf(lowerReq);
	const maxTypos = wantedStem.length < 3 ? 0 : wantedStem.length < 5 ? 1 : 2;

	const tier = (candidate: string): number | undefined => {
		if (candidate === lowerReq) return 1;
		if (canonicalFilename(candidate) === canonicalFilename(lowerReq)) return undefined;
		const foundStem = stemOf(candidate);
		if (foundStem === wantedStem) return 2;
		if (
			Math.min(foundStem.length, wantedStem.length) >= 3 &&
			(candidate.includes(lowerReq) ||
				lowerReq.includes(candidate) ||
				foundStem.includes(wantedStem) ||
				wantedStem.includes(foundStem))
		) {
			return 3;
		}
		if (
			maxTypos > 0 &&
			Math.abs(foundStem.length - wantedStem.length) <= maxTypos &&
			editDistance(foundStem, wantedStem) <= maxTypos
		) {
			return 4;
		}
		return undefined;
	};

	return names
		.filter((entry) => entry !== requested)
		.flatMap((entry) => {
			const rank = tier(entry.toLowerCase());
			return rank === undefined ? [] : [{ entry, rank, distance: editDistance(entry.toLowerCase(), lowerReq) }];
		})
		.sort((a, b) => a.rank - b.rank || a.distance - b.distance || a.entry.localeCompare(b.entry))
		.slice(0, 3)
		.map((match) => match.entry);
}

function isContainedIn(root: string, target: string): boolean {
	const rel = relative(resolve(root), resolve(target));
	return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

async function tryRerootSuggestion(cwd: string, rawPath: string, absPath: string): Promise<string[]> {
	const root = resolve(cwd);
	const rootParent = dirname(root);
	if (rootParent === root) return [];
	if (isContainedIn(root, absPath) || !isContainedIn(rootParent, absPath)) return [];
	const relFromParent = relative(rootParent, absPath);
	const candidate = join(root, relFromParent);
	try {
		await access(candidate);
		const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
		return [isAbsolute(cleaned) || cleaned.startsWith("~/") ? candidate : relative(root, candidate)];
	} catch {
		return [];
	}
}

function formatDidYouMean(suggestions: readonly string[]): string[] {
	const unique = [...new Set(suggestions)].slice(0, 3);
	return unique.length === 0 ? [] : [`Did you mean one of these?\n${unique.join("\n")}`];
}

export async function buildReadMissingPathHint(cwd: string, rawPath: string): Promise<string> {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	const absPath = resolve(cwd, cleaned);
	const rerooted = await tryRerootSuggestion(cwd, rawPath, absPath);
	const folder = dirname(absPath);

	try {
		const entries = await readdir(folder);
		const inputDir = dirname(cleaned);
		const suggestions = [
			...rerooted,
			...rankSimilarNames(entries, basename(cleaned)).map((entry) =>
				inputDir === "." ? entry : join(inputDir, entry),
			),
		];
		return formatDidYouMean(suggestions).join("\n\n");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
			return formatDidYouMean(rerooted).join("\n\n");
		}
	}

	let child = folder;
	let parent = dirname(folder);
	while (parent !== child) {
		try {
			const entries = await readdir(parent);
			const suggestions = [
				...rerooted,
				...rankSimilarNames(entries, basename(child)).map((entry) => join(parent, entry)),
			];
			return [
				`The folder ${child} does not exist. The nearest existing folder is ${parent}.`,
				...formatDidYouMean(suggestions),
			].join("\n\n");
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") break;
			child = parent;
			parent = dirname(parent);
		}
	}

	return formatDidYouMean(rerooted).join("\n\n");
}

export function parsePastEofError(errorText: string): { offset: number; totalLines: number } | undefined {
	const match = errorText.match(/Offset\s+(\d+)\s+is beyond end of file\s+\((\d+)\s+lines?\s+total\)/);
	if (!match) return undefined;
	return { offset: Number(match[1]), totalLines: Number(match[2]) };
}

export async function recoverPastEofRead(
	cwd: string,
	rawPath: string,
	offset: number,
	limit?: number,
): Promise<string | undefined> {
	try {
		const raw = await readFile(resolveUserPath(cwd, rawPath), "utf-8");
		const split = raw.split("\n");
		const totalLines = raw.endsWith("\n") ? split.length - 1 : split.length;
		if (totalLines <= 0) return undefined;

		const tailCount = Math.min(limit && limit > 0 ? limit : PAST_EOF_TAIL_LINES, PAST_EOF_TAIL_LINES, totalLines);
		let startIdx = Math.max(0, totalLines - tailCount);
		const lines = split.slice(startIdx, totalLines).map((line) => clampLongLines(line).text);

		let byteSize = Buffer.byteLength(lines.join("\n"), "utf-8");
		while (lines.length > 1 && byteSize > PAST_EOF_MAX_BYTES) {
			const dropped = lines.shift() ?? "";
			byteSize -= Buffer.byteLength(dropped, "utf-8") + 1;
			startIdx++;
		}

		const startLine = startIdx + 1;
		const header = `[Offset ${offset} is beyond end of file (${totalLines} ${totalLines === 1 ? "line" : "lines"} total). Showing lines ${startLine}-${totalLines}:]`;
		return `${header}\n${lines.join("\n")}`;
	} catch {
		return undefined;
	}
}

export async function recoverDirectoryRead(
	cwd: string,
	rawPath: string,
	offset?: number,
	limit?: number,
): Promise<string | undefined> {
	try {
		const absPath = resolveUserPath(cwd, rawPath);
		const entries = await readdir(absPath, { withFileTypes: true });
		const visible = entries
			.map((entry) => ({
				name: entry.isDirectory() ? `${entry.name}/` : entry.name,
				isDir: entry.isDirectory(),
			}))
			.sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name));

		const start = Math.max(1, offset && offset > 0 ? Math.floor(offset) : 1);
		const pageSize = Math.min(limit && limit > 0 ? Math.floor(limit) : DIR_LIST_MAX_ENTRIES, DIR_LIST_MAX_ENTRIES);
		const selected = visible.slice(start - 1, start - 1 + pageSize);
		const header =
			selected.length === 0
				? `Read directory ${rawPath}, 0 entries`
				: `Read directory ${rawPath}, entries ${start}-${start + selected.length - 1} of ${visible.length}`;
		const lines = [header, ...selected.map((entry) => entry.name)];
		if (start - 1 + selected.length < visible.length) {
			lines.push(`[Output truncated. Continue reading with offset=${start + selected.length}]`);
		}
		return lines.join("\n");
	} catch {
		return undefined;
	}
}

export function extractFailedEditBlock(
	input: Record<string, unknown>,
	errorText: string,
): { path: string; oldText: string; newText?: string } | undefined {
	const path = typeof input.path === "string" ? input.path : undefined;
	if (!path) return undefined;

	const indexedMatch = errorText.match(/Could not find edits\[(\d+)\]/);
	if (Array.isArray(input.edits) && input.edits.length > 0) {
		const idx = indexedMatch ? Number(indexedMatch[1]) : 0;
		const entry = input.edits[idx];
		if (entry && typeof entry === "object") {
			const record = entry as Record<string, unknown>;
			if (typeof record.oldText === "string") {
				return {
					path,
					oldText: record.oldText,
					newText: typeof record.newText === "string" ? record.newText : undefined,
				};
			}
		}
	}

	if (typeof input.oldText === "string") {
		return {
			path,
			oldText: input.oldText,
			newText: typeof input.newText === "string" ? input.newText : undefined,
		};
	}

	return undefined;
}

export async function buildEditMissHint(
	cwd: string,
	input: Record<string, unknown>,
	errorText: string,
): Promise<string> {
	if (!errorText.includes("Could not find")) return "";
	const failed = extractFailedEditBlock(input, errorText);
	if (!failed) return "";

	try {
		const fileContent = await readFile(resolveUserPath(cwd, failed.path), "utf-8");
		const fileLines = fileContent.replace(/\r\n/g, "\n").split("\n");
		const oldLines = failed.oldText.replace(/\r\n/g, "\n").split("\n");
		const newLines = failed.newText?.replace(/\r\n/g, "\n").split("\n");
		return formatMissHint(fileLines, oldLines, newLines);
	} catch {
		return "";
	}
}
