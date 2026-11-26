export const PATCH_GRAMMAR = `start: begin_patch hunk+ end_patch
begin_patch: "*** Begin Patch" LF
end_patch: "*** End Patch" LF?

hunk: add_hunk | delete_hunk | update_hunk
add_hunk: "*** Add File: " filename LF add_line+
delete_hunk: "*** Delete File: " filename LF
update_hunk: "*** Update File: " filename LF change_move? change?

filename: /(.+)/
add_line: "+" /(.*)/ LF -> line

change_move: "*** Move to: " filename LF
change: (change_context | change_line)+ eof_line?
change_context: ("@@" | "@@ " /(.+)/) LF
change_line: ("+" | "-" | " ") /(.*)/ LF
eof_line: "*** End of File" LF

%import common.LF
`;

export const PATCH_DESCRIPTION = `Use the \`patch\` tool to create, edit, move, or delete one or more files in a single call.

Envelope format:
*** Begin Patch
[ one or more file sections ]
*** End Patch

Each file section starts with one of three headers:
*** Add File: <path> - create a new file. Prefix every line with \`+\`.
*** Delete File: <path> - remove an existing file.
*** Update File: <path> - edit an existing file (optionally followed by \`*** Move to: <new_path>\`).

Inside \`*** Update File:\`, use \`@@ <context>\` markers (or \`@@\`) followed by context lines (\` \`), removed lines (\`-\`), and added lines (\`+\`). Add \`*** End of File\` when anchoring at the end of the file.`;

export interface UpdateFileChunk {
	oldLines: string[];
	newLines: string[];
	changeContext?: string;
	endOfFile?: boolean;
}

export type PatchHunk =
	| { type: "add"; path: string; contents: string }
	| { type: "delete"; path: string }
	| { type: "update"; path: string; movePath?: string; chunks: UpdateFileChunk[] };

const BEGIN_PATCH = "*** Begin Patch";
const END_PATCH = "*** End Patch";
const ADD_FILE = "*** Add File: ";
const DELETE_FILE = "*** Delete File: ";
const UPDATE_FILE = "*** Update File: ";
const MOVE_TO = "*** Move to: ";
const END_OF_FILE = "*** End of File";

const HINT_MAX_LINES = 12;
const HINT_MAX_LINE_CHARS = 200;

export function normalizeTypographic(value: string): string {
	return value
		.replace(/[\u2018\u2019\u201A\u201B]/g, "'")
		.replace(/[\u201C\u201D\u201E\u201F]/g, '"')
		.replace(/[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]/g, "-")
		.replace(/[\u00A0\u2002-\u200A\u202F\u205F\u3000]/g, " ");
}

function stripHeredoc(input: string): string {
	return input.match(/^(?:cat\s+)?<<(['"]?)(\w+)\1\s*\n([\s\S]*?)\n\2\s*$/)?.[3] ?? input;
}

function isBoundary(line: string): boolean {
	return (
		line === END_PATCH ||
		line.startsWith(ADD_FILE) ||
		line.startsWith(DELETE_FILE) ||
		line.startsWith(UPDATE_FILE)
	);
}

export function parsePatch(rawInput: string): PatchHunk[] {
	const cleaned = stripHeredoc(rawInput.trim()).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
	const lines = cleaned.split("\n");

	let start = 0;
	while (start < lines.length && lines[start]!.trim() === "") start++;
	if (start >= lines.length || lines[start]!.trim() !== BEGIN_PATCH) {
		throw new Error("Invalid patch: must start with '*** Begin Patch'");
	}

	let end = lines.length - 1;
	while (end > start && lines[end]!.trim() === "") end--;
	if (end <= start || lines[end]!.trim() !== END_PATCH) {
		throw new Error("Invalid patch: must end with '*** End Patch'");
	}

	const hunks: PatchHunk[] = [];
	let index = start + 1;

	while (index < end) {
		const trimmed = lines[index]!.trim();
		if (trimmed === "") {
			index++;
			continue;
		}

		if (trimmed.startsWith(ADD_FILE)) {
			const path = trimmed.slice(ADD_FILE.length).trim();
			if (!path) throw new Error(`Line ${index + 1}: missing path after '${ADD_FILE}'`);
			index++;
			const added: string[] = [];
			while (index < end && !isBoundary(lines[index]!.trim())) {
				const line = lines[index]!;
				if (!line.startsWith("+")) {
					throw new Error(`Line ${index + 1}: expected '+' line in Add File '${path}', got '${line}'`);
				}
				added.push(line.slice(1));
				index++;
			}
			hunks.push({ type: "add", path, contents: added.join("\n") });
			continue;
		}

		if (trimmed.startsWith(DELETE_FILE)) {
			const path = trimmed.slice(DELETE_FILE.length).trim();
			if (!path) throw new Error(`Line ${index + 1}: missing path after '${DELETE_FILE}'`);
			hunks.push({ type: "delete", path });
			index++;
			continue;
		}

		if (trimmed.startsWith(UPDATE_FILE)) {
			const path = trimmed.slice(UPDATE_FILE.length).trim();
			if (!path) throw new Error(`Line ${index + 1}: missing path after '${UPDATE_FILE}'`);
			const hunkLine = index;
			index++;

			let movePath: string | undefined;
			if (index < end && lines[index]!.trim().startsWith(MOVE_TO)) {
				movePath = lines[index]!.trim().slice(MOVE_TO.length).trim();
				if (!movePath) throw new Error(`Line ${index + 1}: missing path after '${MOVE_TO}'`);
				index++;
			}

			const { chunks, next } = parseUpdateChunks(lines, index, end, path, hunkLine);
			hunks.push({ type: "update", path, movePath, chunks });
			index = next;
			continue;
		}

		throw new Error(`Line ${index + 1}: unexpected patch header '${trimmed}'`);
	}

	if (hunks.length === 0) {
		throw new Error("Invalid patch: contains no file hunks");
	}
	return hunks;
}

function parseUpdateChunks(
	lines: readonly string[],
	start: number,
	end: number,
	path: string,
	hunkLine: number,
): { chunks: UpdateFileChunk[]; next: number } {
	const chunks: UpdateFileChunk[] = [];
	let index = start;
	let afterEndOfFile = false;

	while (index < end) {
		const line = lines[index]!;
		const trimmedEnd = line.trimEnd();

		if (afterEndOfFile) {
			if (trimmedEnd === "") {
				index++;
				continue;
			}
			if (trimmedEnd === "@@" || trimmedEnd.startsWith("@@ ")) {
				afterEndOfFile = false;
			} else if (isBoundary(trimmedEnd)) {
				break;
			} else {
				throw new Error(`Line ${index + 1}: expected @@ context marker after '${END_OF_FILE}', got '${line}'`);
			}
		}

		if (trimmedEnd === END_OF_FILE) {
			const current = chunks.at(-1);
			if (!current || (current.oldLines.length === 0 && current.newLines.length === 0)) {
				throw new Error(`Line ${index + 1}: update hunk for '${path}' does not contain any lines`);
			}
			current.endOfFile = true;
			afterEndOfFile = true;
			index++;
			continue;
		}

		if (isBoundary(trimmedEnd)) break;

		if (trimmedEnd === "@@" || trimmedEnd.startsWith("@@ ")) {
			const previous = chunks.at(-1);
			if (previous && previous.oldLines.length === 0 && previous.newLines.length === 0) {
				throw new Error(`Line ${index + 1}: empty @@ hunk in '${path}'`);
			}
			chunks.push({
				oldLines: [],
				newLines: [],
				changeContext: trimmedEnd === "@@" ? undefined : trimmedEnd.slice("@@ ".length),
			});
			index++;
			continue;
		}

		if (chunks.length === 0) {
			chunks.push({ oldLines: [], newLines: [] });
		}
		const chunk = chunks.at(-1)!;

		if (line === "") {
			chunk.oldLines.push("");
			chunk.newLines.push("");
		} else if (line.startsWith(" ")) {
			chunk.oldLines.push(line.slice(1));
			chunk.newLines.push(line.slice(1));
		} else if (line.startsWith("-")) {
			chunk.oldLines.push(line.slice(1));
		} else if (line.startsWith("+")) {
			chunk.newLines.push(line.slice(1));
		} else {
			throw new Error(
				`Line ${index + 1}: unexpected line in update hunk for '${path}': '${line}'. Lines must start with ' ', '+', or '-'.`,
			);
		}
		index++;
	}

	if (chunks.length === 0) {
		throw new Error(`Line ${hunkLine + 1}: update hunk for '${path}' is empty`);
	}
	const last = chunks.at(-1)!;
	if (last.oldLines.length === 0 && last.newLines.length === 0) {
		throw new Error(`Update hunk for '${path}' ends with an empty @@ section`);
	}

	return { chunks, next: index };
}

const exactEq = (a: string, b: string) => a === b;
const rstripEq = (a: string, b: string) => a.trimEnd() === b.trimEnd();
const trimEq = (a: string, b: string) => a.trim() === b.trim();
const normalizedEq = (a: string, b: string) => normalizeTypographic(a.trim()) === normalizeTypographic(b.trim());
const COMPARATORS = [exactEq, rstripEq, trimEq, normalizedEq] as const;

function matchesAt(
	lines: readonly string[],
	pattern: readonly string[],
	offset: number,
	compare: (a: string, b: string) => boolean,
): boolean {
	for (let i = 0; i < pattern.length; i++) {
		if (!compare(lines[offset + i]!, pattern[i]!)) return false;
	}
	return true;
}

function seek(lines: readonly string[], pattern: readonly string[], start: number, eof = false): number {
	if (pattern.length === 0) return -1;
	if (eof) {
		const offset = lines.length - pattern.length;
		if (offset < start) return -1;
		for (const compare of COMPARATORS) {
			if (matchesAt(lines, pattern, offset, compare)) return offset;
		}
		return -1;
	}
	for (const compare of COMPARATORS) {
		for (let offset = start; offset <= lines.length - pattern.length; offset++) {
			if (matchesAt(lines, pattern, offset, compare)) return offset;
		}
	}
	return -1;
}

function normalizeForHint(line: string): string {
	return normalizeTypographic(line).trim().replace(/\s+/g, " ");
}

function clampHintLine(line: string): string {
	return line.length <= HINT_MAX_LINE_CHARS ? line : `${line.slice(0, HINT_MAX_LINE_CHARS)}...`;
}

export function formatMissHint(
	fileLines: readonly string[],
	oldLines: readonly string[],
	newLines?: readonly string[],
): string {
	if (newLines && newLines.length > 0 && newLines.some((line) => line.trim() !== "")) {
		if (seek(fileLines, newLines, 0) !== -1) {
			return "Hint: the replacement text is already present in the file.";
		}
	}

	const anchors = oldLines
		.map((line, index) => ({ norm: normalizeForHint(line), index }))
		.filter((entry) => entry.norm.length >= 3);
	if (anchors.length === 0) return "";

	const lineMap = new Map<string, number[]>();
	for (let i = 0; i < fileLines.length; i++) {
		const norm = normalizeForHint(fileLines[i]!);
		if (norm.length < 3) continue;
		let positions = lineMap.get(norm);
		if (!positions) {
			positions = [];
			lineMap.set(norm, positions);
		}
		positions.push(i);
	}

	const votes = new Map<number, number>();
	for (const anchor of anchors) {
		const positions = lineMap.get(anchor.norm);
		if (!positions || positions.length > 20) continue;
		for (const pos of positions) {
			const candidateStart = Math.max(0, pos - anchor.index);
			votes.set(candidateStart, (votes.get(candidateStart) ?? 0) + 1);
		}
	}

	let bestStart = -1;
	let bestVotes = 0;
	for (const [candidateStart, count] of votes) {
		if (count > bestVotes) {
			bestVotes = count;
			bestStart = candidateStart;
		}
	}
	if (bestStart === -1) return "";

	const windowStart = Math.max(0, bestStart - 1);
	const windowEnd = Math.min(fileLines.length, windowStart + Math.min(HINT_MAX_LINES, Math.max(oldLines.length + 2, 6)));
	const snippet = fileLines
		.slice(windowStart, windowEnd)
		.map((line, i) => `${windowStart + i + 1}: ${clampHintLine(line)}`)
		.join("\n");

	return `Closest matching lines in file:\n${snippet}`;
}

export function applyUpdateChunks(originalContent: string, path: string, chunks: readonly UpdateFileChunk[]): string {
	const hasBom = originalContent.startsWith("\uFEFF");
	const withoutBom = hasBom ? originalContent.slice(1) : originalContent;
	const lineEnding = withoutBom.includes("\r\n") ? "\r\n" : "\n";
	const normalized = withoutBom.replace(/\r\n/g, "\n");
	const hadTrailingNewline = normalized.endsWith("\n");

	const lines = normalized.split("\n");
	if (hadTrailingNewline) {
		lines.pop();
	}

	const replacements: Array<readonly [start: number, removeCount: number, insert: readonly string[]]> = [];
	let cursor = 0;

	for (const chunk of chunks) {
		if (chunk.changeContext) {
			let contextIdx = seek(lines, [chunk.changeContext], cursor);
			if (contextIdx === -1) {
				const ctxNorm = normalizeTypographic(chunk.changeContext.trim());
				contextIdx = lines.findIndex(
					(line, idx) => idx >= cursor && normalizeTypographic(line.trim()).startsWith(ctxNorm),
				);
			}
			if (contextIdx === -1) {
				const hint = formatMissHint(lines, [chunk.changeContext]);
				throw new Error(`Failed to find context '${chunk.changeContext}' in ${path}${hint ? `\n\n${hint}` : ""}`);
			}
			cursor = contextIdx + 1;
		}

		if (chunk.oldLines.length === 0) {
			replacements.push([lines.length, 0, chunk.newLines]);
			continue;
		}

		let oldLines = chunk.oldLines;
		let newLines = chunk.newLines;
		let found = seek(lines, oldLines, cursor, chunk.endOfFile);

		if (found === -1 && oldLines.at(-1) === "") {
			oldLines = oldLines.slice(0, -1);
			if (newLines.at(-1) === "") newLines = newLines.slice(0, -1);
			found = seek(lines, oldLines, cursor, chunk.endOfFile);
		}

		if (found === -1) {
			const hint = formatMissHint(lines, chunk.oldLines, chunk.newLines);
			throw new Error(
				`Failed to find expected lines in ${path}:\n${chunk.oldLines.join("\n")}${hint ? `\n\n${hint}` : ""}`,
			);
		}

		replacements.push([found, oldLines.length, newLines]);
		cursor = found + oldLines.length;
	}

	replacements.sort((a, b) => a[0] - b[0]);

	const result = [...lines];
	for (let i = replacements.length - 1; i >= 0; i--) {
		const [startIdx, removeCount, insert] = replacements[i]!;
		result.splice(startIdx, removeCount, ...insert);
	}

	let output = result.join("\n");
	if (hadTrailingNewline || (result.length > 0 && !output.endsWith("\n"))) {
		output += "\n";
	}
	if (lineEnding === "\r\n") {
		output = output.replace(/\n/g, "\r\n");
	}
	return hasBom ? `\uFEFF${output}` : output;
}
