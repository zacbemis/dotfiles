import { execFile } from "node:child_process";
import { access, readFile } from "node:fs/promises";
import { delimiter, dirname, extname, isAbsolute, join, relative, resolve } from "node:path";
import { promisify } from "node:util";
import type { FileLockFn } from "./apply-patch.ts";
import { findGitRoot } from "./prompt-tuning.ts";

const execFileAsync = promisify(execFile);

export const AUTO_FORMAT_DISABLE_ENV = "PI_HARNESS_AUTO_FORMAT";
const DEFAULT_FORMAT_TIMEOUT_MS = 5_000;

interface FormatterRule {
	readonly name: string;
	readonly extensions: ReadonlySet<string>;
	readonly resolve: (startDir: string, stopDir: string) => Promise<string[] | undefined>;
}

const passthroughLock: FileLockFn = (_path, fn) => fn();

const JS_TS_EXTENSIONS = new Set([".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"]);
const BIOME_EXTENSIONS = new Set([...JS_TS_EXTENSIONS, ".json", ".jsonc", ".css", ".html"]);
const PRETTIER_EXTENSIONS = new Set([
	...JS_TS_EXTENSIONS,
	".json",
	".jsonc",
	".css",
	".scss",
	".less",
	".html",
	".htm",
	".md",
	".mdx",
	".yaml",
	".yml",
	".vue",
	".svelte",
]);
const PYTHON_EXTENSIONS = new Set([".py", ".pyi"]);
const CLANG_EXTENSIONS = new Set([".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx"]);
const GO_EXTENSIONS = new Set([".go"]);
const RUST_EXTENSIONS = new Set([".rs"]);
const ZIG_EXTENSIONS = new Set([".zig", ".zon"]);

async function exists(filePath: string): Promise<boolean> {
	try {
		await access(filePath);
		return true;
	} catch {
		return false;
	}
}

function isInsideDirectory(root: string, target: string): boolean {
	const rel = relative(resolve(root), resolve(target));
	return rel !== "" && !rel.startsWith("..") && !isAbsolute(rel);
}

async function findUp(names: readonly string[], startDir: string, stopDir: string): Promise<string | undefined> {
	let current = resolve(startDir);
	const boundary = resolve(stopDir);
	while (true) {
		for (const name of names) {
			const candidate = join(current, name);
			if (await exists(candidate)) return candidate;
		}
		if (current === boundary) return undefined;
		const parent = dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

async function findNodeBin(binName: string, startDir: string, stopDir: string): Promise<string | undefined> {
	const binFile = process.platform === "win32" ? `${binName}.cmd` : binName;
	return findUp([join("node_modules", ".bin", binFile)], startDir, stopDir);
}

async function findOnPath(binName: string): Promise<string | undefined> {
	const pathValue = process.env.PATH;
	if (!pathValue) return undefined;
	const suffix = process.platform === "win32" ? ".exe" : "";
	for (const dir of pathValue.split(delimiter)) {
		if (!dir) continue;
		const candidate = join(dir, `${binName}${suffix}`);
		if (await exists(candidate)) return candidate;
	}
	return undefined;
}

async function packageHasDep(pkgPath: string, dep: string): Promise<boolean> {
	try {
		const parsed = JSON.parse(await readFile(pkgPath, "utf-8")) as {
			dependencies?: Record<string, unknown>;
			devDependencies?: Record<string, unknown>;
		};
		return Boolean(parsed.dependencies?.[dep] || parsed.devDependencies?.[dep]);
	} catch {
		return false;
	}
}

const FORMATTER_RULES: readonly FormatterRule[] = [
	{
		name: "biome",
		extensions: BIOME_EXTENSIONS,
		async resolve(startDir, stopDir) {
			const config = await findUp(["biome.json", "biome.jsonc"], startDir, stopDir);
			if (!config) return undefined;
			const bin = (await findNodeBin("biome", startDir, stopDir)) ?? (await findOnPath("biome"));
			return bin ? [bin, "format", "--write", "$FILE"] : undefined;
		},
	},
	{
		name: "oxfmt",
		extensions: JS_TS_EXTENSIONS,
		async resolve(startDir, stopDir) {
			const pkg = await findUp(["package.json"], startDir, stopDir);
			if (!pkg || !(await packageHasDep(pkg, "oxfmt"))) return undefined;
			const bin = await findNodeBin("oxfmt", startDir, stopDir);
			return bin ? [bin, "$FILE"] : undefined;
		},
	},
	{
		name: "prettier",
		extensions: PRETTIER_EXTENSIONS,
		async resolve(startDir, stopDir) {
			const pkg = await findUp(["package.json"], startDir, stopDir);
			if (!pkg || !(await packageHasDep(pkg, "prettier"))) return undefined;
			const bin = await findNodeBin("prettier", startDir, stopDir);
			return bin ? [bin, "--write", "$FILE"] : undefined;
		},
	},
	{
		name: "ruff",
		extensions: PYTHON_EXTENSIONS,
		async resolve(startDir, stopDir) {
			const bin = await findOnPath("ruff");
			if (!bin) return undefined;
			if (await findUp(["ruff.toml", ".ruff.toml"], startDir, stopDir)) {
				return [bin, "format", "$FILE"];
			}
			const pyproject = await findUp(["pyproject.toml"], startDir, stopDir);
			if (pyproject) {
				try {
					const text = await readFile(pyproject, "utf-8");
					if (text.includes("[tool.ruff]") || /\bruff\b/.test(text)) {
						return [bin, "format", "$FILE"];
					}
				} catch {
					// ignore unreadable config
				}
			}
			const reqs = await findUp(["requirements.txt", "requirements-dev.txt"], startDir, stopDir);
			if (reqs) {
				try {
					if (/\bruff\b/.test(await readFile(reqs, "utf-8"))) {
						return [bin, "format", "$FILE"];
					}
				} catch {
					// ignore unreadable requirements
				}
			}
			return undefined;
		},
	},
	{
		name: "clang-format",
		extensions: CLANG_EXTENSIONS,
		async resolve(startDir, stopDir) {
			if (!(await findUp([".clang-format"], startDir, stopDir))) return undefined;
			const bin = await findOnPath("clang-format");
			return bin ? [bin, "-i", "$FILE"] : undefined;
		},
	},
	{
		name: "gofmt",
		extensions: GO_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("gofmt");
			return bin ? [bin, "-w", "$FILE"] : undefined;
		},
	},
	{
		name: "rustfmt",
		extensions: RUST_EXTENSIONS,
		async resolve(startDir, stopDir) {
			if (!(await findUp(["Cargo.toml"], startDir, stopDir))) return undefined;
			const bin = await findOnPath("rustfmt");
			return bin ? [bin, "$FILE"] : undefined;
		},
	},
	{
		name: "zig",
		extensions: ZIG_EXTENSIONS,
		async resolve() {
			const bin = await findOnPath("zig");
			return bin ? [bin, "fmt", "$FILE"] : undefined;
		},
	},
];

export async function detectFormatterForFile(
	workspaceCwd: string,
	absFilePath: string,
): Promise<{ name: string; command: string[] } | undefined> {
	const ext = extname(absFilePath).toLowerCase();
	if (!ext) return undefined;
	const stopDir = (await findGitRoot(workspaceCwd)) ?? resolve(workspaceCwd);
	const startDir = dirname(absFilePath);

	for (const rule of FORMATTER_RULES) {
		if (!rule.extensions.has(ext)) continue;
		const command = await rule.resolve(startDir, stopDir);
		if (command) return { name: rule.name, command };
	}
	return undefined;
}

export function createProjectFormatter(options?: { timeoutMs?: number }) {
	const timeoutMs = options?.timeoutMs ?? DEFAULT_FORMAT_TIMEOUT_MS;
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

	return {
		clear(): void {
			stopDirCache.clear();
			commandCache.clear();
		},
		async formatFile(
			workspaceCwd: string,
			rawPath: string,
			lockFile: FileLockFn = passthroughLock,
		): Promise<boolean> {
			if (process.env[AUTO_FORMAT_DISABLE_ENV] === "0") return false;
			const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
			const absPath = resolve(workspaceCwd, cleaned);
			if (!isInsideDirectory(workspaceCwd, absPath)) return false;

			const ext = extname(absPath).toLowerCase();
			if (!ext) return false;

			const stopDir = await getStopDir(workspaceCwd);
			const startDir = dirname(absPath);

			let resolvedCmd: string[] | undefined;
			for (const rule of FORMATTER_RULES) {
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

			if (!resolvedCmd) return false;
			const [bin, ...rawArgs] = resolvedCmd;
			if (!bin) return false;
			const args = rawArgs.map((arg) => (arg === "$FILE" ? absPath : arg));

			return lockFile(absPath, async () => {
				try {
					await execFileAsync(bin, args, {
						cwd: workspaceCwd,
						timeout: timeoutMs,
						windowsHide: true,
					});
					return true;
				} catch {
					// Formatting is strictly best-effort and must never fail a completed edit.
					return false;
				}
			});
		},
	};
}
