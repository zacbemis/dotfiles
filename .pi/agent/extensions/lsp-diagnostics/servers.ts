import { constants } from "node:fs";
import { access, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { delimiter, dirname, extname, join, resolve } from "node:path";

export interface LspServerSpec {
	readonly id: string;
	readonly extensions: ReadonlySet<string>;
	readonly rootMarkers: readonly string[];
	readonly binary: string;
	readonly args: readonly string[];
	readonly languageIdForExtension: (ext: string) => string;
}

export const DEFAULT_LSP_SERVERS: readonly LspServerSpec[] = [
	{
		id: "typescript",
		extensions: new Set([".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"]),
		rootMarkers: ["tsconfig.json", "jsconfig.json"],
		binary: "typescript-language-server",
		args: ["--stdio"],
		languageIdForExtension(ext) {
			if (ext === ".tsx") return "typescriptreact";
			if (ext === ".jsx") return "javascriptreact";
			if (ext === ".js" || ext === ".mjs" || ext === ".cjs") return "javascript";
			return "typescript";
		},
	},
	{
		id: "pyright",
		extensions: new Set([".py", ".pyi"]),
		rootMarkers: ["pyrightconfig.json", "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"],
		binary: "pyright-langserver",
		args: ["--stdio"],
		languageIdForExtension() {
			return "python";
		},
	},
	{
		id: "rust",
		extensions: new Set([".rs"]),
		rootMarkers: ["Cargo.toml"],
		binary: "rust-analyzer",
		args: [],
		languageIdForExtension() {
			return "rust";
		},
	},
	{
		id: "go",
		extensions: new Set([".go"]),
		rootMarkers: ["go.mod"],
		binary: "gopls",
		args: [],
		languageIdForExtension() {
			return "go";
		},
	},
	{
		id: "clangd",
		extensions: new Set([".c", ".h", ".cc", ".cpp", ".cxx", ".hpp", ".hxx"]),
		rootMarkers: ["compile_commands.json", "CMakeLists.txt", ".clangd"],
		binary: "clangd",
		args: ["--background-index=false", "--log=error"],
		languageIdForExtension(ext) {
			return ext === ".c" ? "c" : "cpp";
		},
	},
	{
		id: "lua",
		extensions: new Set([".lua"]),
		rootMarkers: [".luarc.json", ".luarc.jsonc", "init.lua"],
		binary: "lua-language-server",
		args: [],
		languageIdForExtension() {
			return "lua";
		},
	},
];

async function isExecutable(filePath: string): Promise<boolean> {
	try {
		await access(filePath, constants.X_OK);
		return true;
	} catch {
		return false;
	}
}

async function fileExists(filePath: string): Promise<boolean> {
	try {
		await access(filePath, constants.F_OK);
		return true;
	} catch {
		return false;
	}
}

export function isInsideDirectory(rootDir: string, targetPath: string): boolean {
	const root = resolve(rootDir);
	const target = resolve(targetPath);
	if (target === root) return true;
	const prefix = root.endsWith("/") ? root : `${root}/`;
	return target.startsWith(prefix);
}

export async function findGitRoot(startDir: string): Promise<string | undefined> {
	let current = resolve(startDir);
	while (true) {
		if (await fileExists(join(current, ".git"))) {
			return current;
		}
		const parent = dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

export async function findProjectRoot(
	startDir: string,
	stopDir: string,
	markers: readonly string[],
): Promise<string | undefined> {
	let current = resolve(startDir);
	const stop = resolve(stopDir);
	while (true) {
		for (const marker of markers) {
			if (await fileExists(join(current, marker))) {
				return current;
			}
		}
		if (current === stop) return undefined;
		const parent = dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function getMasonBinDirs(): string[] {
	const dirs: string[] = [];
	if (process.env.XDG_DATA_HOME) {
		dirs.push(join(process.env.XDG_DATA_HOME, "nvim", "mason", "bin"));
	}
	dirs.push(join(homedir(), ".local", "share", "nvim", "mason", "bin"));
	return [...new Set(dirs)];
}

export async function resolveServerBinary(
	binary: string,
	startDir: string,
	stopDir: string,
	extraBinDirs: readonly string[] = [],
): Promise<string | undefined> {
	// 1. Project-local node_modules/.bin
	let current = resolve(startDir);
	const stop = resolve(stopDir);
	while (true) {
		const candidate = join(current, "node_modules", ".bin", binary);
		if (await isExecutable(candidate)) return candidate;
		if (current === stop) break;
		const parent = dirname(current);
		if (parent === current) break;
		current = parent;
	}

	// 2. PATH
	const pathDirs = (process.env.PATH ?? "").split(delimiter).filter(Boolean);
	for (const dir of pathDirs) {
		const candidate = join(dir, binary);
		if (await isExecutable(candidate)) return candidate;
	}

	// 3. Mason & caller-supplied fallback bin dirs
	for (const dir of [...extraBinDirs, ...getMasonBinDirs()]) {
		const candidate = join(dir, binary);
		if (await isExecutable(candidate)) return candidate;
	}

	return undefined;
}

export function matchServerSpec(
	absPath: string,
	servers: readonly LspServerSpec[] = DEFAULT_LSP_SERVERS,
): LspServerSpec | undefined {
	const ext = extname(absPath).toLowerCase();
	if (!ext) return undefined;
	return servers.find((spec) => spec.extensions.has(ext));
}

const SKIP_SCAN_DIRS = new Set([
	"node_modules",
	"dist",
	"build",
	"target",
	"vendor",
	"__pycache__",
	".git",
	".venv",
	"venv",
]);

async function hasAnyMarkerInDir(dir: string, markers: readonly string[]): Promise<boolean> {
	for (const marker of markers) {
		if (await fileExists(join(dir, marker))) return true;
	}
	return false;
}

/**
 * Checks whether cwd (walking up to gitRoot and scanning up to 2 shallow subdirectory levels
 * for monorepos) contains a configured LSP project whose server binary is installed.
 */
export async function hasConfiguredLspWorkspace(
	cwd: string,
	servers: readonly LspServerSpec[] = DEFAULT_LSP_SERVERS,
	extraBinDirs: readonly string[] = [],
): Promise<boolean> {
	const resolvedCwd = resolve(cwd);
	const gitRoot = await findGitRoot(resolvedCwd);
	const stopDir = gitRoot ?? resolvedCwd;

	// Collect candidate directories: cwd -> stopDir upward, plus bounded shallow subdirs.
	const candidateDirs: string[] = [];
	const seen = new Set<string>();
	const addDir = (dir: string) => {
		if (!seen.has(dir)) {
			seen.add(dir);
			candidateDirs.push(dir);
		}
	};

	let cursor = resolvedCwd;
	while (true) {
		addDir(cursor);
		if (cursor === stopDir) break;
		const parent = dirname(cursor);
		if (parent === cursor) break;
		cursor = parent;
	}

	const queue: Array<{ dir: string; depth: number }> = [{ dir: resolvedCwd, depth: 0 }];
	const maxShallowDirs = 40;
	let scannedShallow = 0;
	while (queue.length > 0 && scannedShallow < maxShallowDirs) {
		const { dir, depth } = queue.shift()!;
		if (depth >= 2) continue;
		let entries;
		try {
			entries = await readdir(dir, { withFileTypes: true });
		} catch {
			continue;
		}
		for (const entry of entries) {
			if (!entry.isDirectory()) continue;
			if (entry.name.startsWith(".") || SKIP_SCAN_DIRS.has(entry.name)) continue;
			const child = join(dir, entry.name);
			addDir(child);
			scannedShallow++;
			if (scannedShallow >= maxShallowDirs) break;
			if (depth + 1 < 2) {
				queue.push({ dir: child, depth: depth + 1 });
			}
		}
	}

	const binaryCache = new Map<string, boolean>();
	for (const dir of candidateDirs) {
		for (const spec of servers) {
			if (!(await hasAnyMarkerInDir(dir, spec.rootMarkers))) continue;
			let hasBinary = binaryCache.get(spec.binary);
			if (hasBinary === undefined) {
				hasBinary = (await resolveServerBinary(spec.binary, dir, stopDir, extraBinDirs)) !== undefined;
				binaryCache.set(spec.binary, hasBinary);
			}
			if (hasBinary) return true;
		}
	}

	return false;
}
