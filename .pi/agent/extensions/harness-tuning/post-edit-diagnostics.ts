import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { basename, dirname, extname, relative, resolve } from "node:path";
import { promisify } from "node:util";
import { findNodeBin, findOnPath, findUp, isInsideDirectory } from "./auto-format.ts";
import { stripAnsi } from "./bash-hygiene.ts";
import { findGitRoot } from "./prompt-tuning.ts";

const execFileAsync = promisify(execFile);

export const DIAGNOSTICS_DISABLE_ENV = "PI_HARNESS_DIAGNOSTICS";
const DEFAULT_TIMEOUT_MS = 3_000;
const DEFAULT_MAX_FILES = 6;
const DEFAULT_MAX_LINES = 12;
const DEFAULT_MAX_CHARS = 1_800;

interface DiagnosticRule {
	readonly name: string;
	readonly extensions: ReadonlySet<string>;
	readonly resolve: (startDir: string, stopDir: string) => Promise<string[] | undefined>;
}

const JS_TS_EXTENSIONS = new Set([".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"]);
const NODE_CHECK_EXTENSIONS = new Set([".js", ".mjs", ".cjs"]);
const PYTHON_EXTENSIONS = new Set([".py", ".pyi"]);
const SHELL_EXTENSIONS = new Set([".sh", ".bash"]);
const GO_EXTENSIONS = new Set([".go"]);

const JSONC_BASENAMES = new Set([
	"tsconfig.json",
	"jsconfig.json",
	"biome.json",
	"deno.json",
	".eslintrc.json",
	"devcontainer.json",
]);

function isLikelyJsonc(absPath: string): boolean {
	const name = basename(absPath).toLowerCase();
	if (JSONC_BASENAMES.has(name)) return true;
	if (/^(?:ts|js)config\.[^.]+\.json$/.test(name)) return true;
	const normalized = absPath.replace(/\\/g, "/");
	return normalized.includes("/.vscode/") || normalized.includes("/.devcontainer/");
}

const DIAGNOSTIC_RULES: readonly DiagnosticRule[] = [
	{
		name: "oxlint",
		extensions: JS_TS_EXTENSIONS,
		async resolve(startDir, stopDir) {
			const bin = await findNodeBin("oxlint", startDir, stopDir);
			return bin ? [bin, "--quiet", "$FILE"] : undefined;
		},
	},
	{
		name: "biome",
		extensions: JS_TS_EXTENSIONS,
		async resolve(startDir, stopDir) {
			if (!(await findUp(["biome.json", "biome.jsonc"], startDir, stopDir))) return undefined;
			const bin = (await findNodeBin("biome", startDir, stopDir)) ?? (await findOnPath("biome"));
			return bin ? [bin, "lint", "--diagnostic-level=error", "--colors=off", "$FILE"] : undefined;
		},
	},
	{
		name: "node-check",
		extensions: NODE_CHECK_EXTENSIONS,
		async resolve() {
			return [process.execPath, "--check", "$FILE"];
		},
	},
	{
		name: "ruff",
		extensions: PYTHON_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("ruff");
			return bin
				? [bin, "check", "--output-format=concise", "--no-fix", "--no-cache", "--select=E9,F63,F7,F82", "$FILE"]
				: undefined;
		},
	},
	{
		name: "python-ast",
		extensions: PYTHON_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("python3");
			return bin
				? [bin, "-c", "import ast, sys; ast.parse(open(sys.argv[1], 'rb').read(), sys.argv[1])", "$FILE"]
				: undefined;
		},
	},
	{
		name: "bash-syntax",
		extensions: SHELL_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("bash");
			return bin ? [bin, "-n", "$FILE"] : undefined;
		},
	},
	{
		name: "gofmt-syntax",
		extensions: GO_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("gofmt");
			return bin ? [bin, "-l", "-e", "$FILE"] : undefined;
		},
	},
];

function compactDiagnosticOutput(
	raw: string,
	workspaceCwd: string,
	absPath: string,
	maxLines: number,
	maxChars: number,
): string | undefined {
	const cleaned = stripAnsi(raw).replace(/\r\n?/g, "\n").trim();
	if (!cleaned) return undefined;

	const relPath = relative(resolve(workspaceCwd), absPath);
	const displayPath = relPath && !relPath.startsWith("..") ? relPath : absPath;
	const normalized = cleaned.split(absPath).join(displayPath);

	const lines = normalized
		.split("\n")
		.map((line) => line.trimEnd())
		.filter((line) => line.length > 0);
	if (lines.length === 0) return undefined;

	let limited = lines.slice(0, maxLines).join("\n");
	if (lines.length > maxLines) {
		limited += `\n[... ${lines.length - maxLines} more diagnostic lines omitted]`;
	}
	if (limited.length > maxChars) {
		limited = `${limited.slice(0, maxChars)}... [truncated]`;
	}
	return limited;
}

async function checkJsonFile(workspaceCwd: string, absPath: string): Promise<string | undefined> {
	if (isLikelyJsonc(absPath)) return undefined;
	try {
		const raw = await readFile(absPath, "utf-8");
		JSON.parse(raw);
		return undefined;
	} catch (error) {
		const relPath = relative(resolve(workspaceCwd), absPath);
		const displayPath = relPath && !relPath.startsWith("..") ? relPath : absPath;
		const message = error instanceof Error ? error.message : String(error);
		return `${displayPath}: Invalid JSON (${message})`;
	}
}

export function createPostEditDiagnostics(options?: {
	readonly timeoutMs?: number;
	readonly maxFiles?: number;
	readonly maxLines?: number;
	readonly maxChars?: number;
}) {
	const timeoutMs = options?.timeoutMs ?? DEFAULT_TIMEOUT_MS;
	const maxFiles = options?.maxFiles ?? DEFAULT_MAX_FILES;
	const maxLines = options?.maxLines ?? DEFAULT_MAX_LINES;
	const maxChars = options?.maxChars ?? DEFAULT_MAX_CHARS;

	const stopDirCache = new Map<string, string>();
	const commandCache = new Map<string, string[] | null>();

	const getStopDir = async (cwd: string): Promise<string> => {
		const normalized = resolve(cwd);
		const cached = stopDirCache.get(normalized);
		if (cached) return cached;
		const stopDir = (await findGitRoot(normalized)) ?? normalized;
		stopDirCache.set(normalized, stopDir);
		return stopDir;
	};

	const checkSingleFile = async (workspaceCwd: string, rawPath: string): Promise<string | undefined> => {
		if (process.env[DIAGNOSTICS_DISABLE_ENV] === "0") return undefined;
		const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
		const absPath = resolve(workspaceCwd, cleaned);
		if (!isInsideDirectory(workspaceCwd, absPath)) return undefined;

		const ext = extname(absPath).toLowerCase();
		if (!ext) return undefined;
		if (ext === ".json") {
			return checkJsonFile(workspaceCwd, absPath);
		}

		const stopDir = await getStopDir(workspaceCwd);
		const startDir = dirname(absPath);

		let resolvedCmd: string[] | undefined;
		for (const rule of DIAGNOSTIC_RULES) {
			if (!rule.extensions.has(ext)) continue;
			const cacheKey = `${stopDir}::${startDir}::${rule.name}`;
			if (commandCache.has(cacheKey)) {
				const cached = commandCache.get(cacheKey);
				if (cached) {
					resolvedCmd = cached;
					break;
				}
				continue;
			}
			const cmd = await rule.resolve(startDir, stopDir);
			commandCache.set(cacheKey, cmd ?? null);
			if (cmd) {
				resolvedCmd = cmd;
				break;
			}
		}

		if (!resolvedCmd) return undefined;
		const [bin, ...rawArgs] = resolvedCmd;
		if (!bin) return undefined;
		const args = rawArgs.map((arg) => (arg === "$FILE" ? absPath : arg));

		try {
			await execFileAsync(bin, args, {
				cwd: workspaceCwd,
				timeout: timeoutMs,
				maxBuffer: 256 * 1024,
				windowsHide: true,
			});
			return undefined;
		} catch (error) {
			const err = error as NodeJS.ErrnoException & {
				killed?: boolean;
				signal?: string | null;
				stdout?: string;
				stderr?: string;
			};
			// Ignore timeouts or missing binaries so diagnostics stay strictly best-effort.
			if (err.killed || err.signal === "SIGTERM" || err.code === "ENOENT") {
				return undefined;
			}
			const combined = [err.stderr, err.stdout].filter((part): part is string => Boolean(part?.trim())).join("\n");
			return compactDiagnosticOutput(combined, workspaceCwd, absPath, maxLines, maxChars);
		}
	};

	return {
		clear(): void {
			stopDirCache.clear();
			commandCache.clear();
		},

		checkFile: checkSingleFile,

		async checkFiles(workspaceCwd: string, rawPaths: readonly string[]): Promise<string | undefined> {
			if (process.env[DIAGNOSTICS_DISABLE_ENV] === "0") return undefined;
			const unique = [...new Set(rawPaths.map((p) => (p.startsWith("@") ? p.slice(1) : p)))].slice(0, maxFiles);
			if (unique.length === 0) return undefined;

			const findings = (await Promise.all(unique.map((path) => checkSingleFile(workspaceCwd, path)))).filter(
				(item): item is string => Boolean(item),
			);
			if (findings.length === 0) return undefined;
			return `[Diagnostics]\n${findings.join("\n\n")}`;
		},
	};
}
