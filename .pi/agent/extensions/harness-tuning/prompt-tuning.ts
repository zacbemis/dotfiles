import { access } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import type { ModelLike } from "./apply-patch.ts";

export type ModelFamily = "gpt" | "claude" | "other";

export interface EnvSnapshot {
	readonly dateString: string;
	readonly platform: string;
	readonly arch: string;
	readonly shell?: string;
	readonly cwd: string;
	readonly gitRoot?: string;
}

export function classifyModelFamily(model: ModelLike | undefined): ModelFamily {
	const id = model?.id?.toLowerCase();
	if (!id) return "other";
	if (id.includes("gpt-") && !id.includes("gpt-4") && !id.includes("oss")) return "gpt";
	if (id.includes("claude")) return "claude";
	return "other";
}

export function buildPromptGuidelines(options: {
	readonly model?: ModelLike;
	readonly activeTools: readonly string[];
}): string[] {
	const rules: string[] = [
		"Prefer parallelizing independent tool calls.",
		"Keep changes consistent with the structure, naming, style, and patterns of the surrounding code.",
		"Treat unfamiliar files or uncommitted changes as potential user work and investigate before deleting or overwriting them.",
		"Never run destructive git or filesystem commands (such as git reset --hard, git checkout --, or recursive deletes on broad paths) unless the user explicitly asked for them.",
	];

	if (options.activeTools.includes("bash")) {
		rules.push(
			"Do not chain shell commands with visual separator echoes like echo '====' or printf '---'; run separate commands or print only needed values.",
		);
	}

	const family = classifyModelFamily(options.model);
	if (family === "gpt") {
		rules.push(
			"Do not narrate routine reads, searches, or edits; send brief progress updates only for meaningful discoveries, tradeoffs, or blockers.",
			"Make the final response self-contained and lead with the outcome rather than a play-by-play of steps.",
			"Run targeted verification appropriate to the change; once checks pass, stop expanding or repeating tests unless new changes or failures justify it.",
			"Bias toward action when the user asks to do something rather than stopping to propose a plan, and continue until the goal is fulfilled.",
			"Avoid invoking or re-reading skills based solely on superficial keyword overlap when they are not needed.",
		);
	} else if (family === "claude") {
		rules.push(
			"Match the surrounding comment density when editing code; add comments only for non-obvious behavior unless project instructions require otherwise.",
		);
	}

	return rules;
}

export async function findGitRoot(cwd: string): Promise<string | undefined> {
	let current = resolve(cwd);
	while (true) {
		try {
			await access(join(current, ".git"));
			return current;
		} catch {
			const parent = dirname(current);
			if (parent === current) return undefined;
			current = parent;
		}
	}
}

export function buildEnvSection(info: EnvSnapshot): string {
	const lines = [
		`Date: ${info.dateString}`,
		`Platform: ${info.platform} (${info.arch})`,
	];
	if (info.shell) {
		lines.push(`Shell: ${info.shell}`);
	}
	lines.push(`Git repo: ${info.gitRoot ? "yes" : "no"}`);
	if (info.gitRoot && resolve(info.gitRoot) !== resolve(info.cwd)) {
		lines.push(`Workspace root: ${info.gitRoot}`);
	}
	return lines.join("\n");
}

export function createEnvCache() {
	const gitRootByCwd = new Map<string, string | undefined>();

	return {
		clear(): void {
			gitRootByCwd.clear();
		},
		async resolveEnvSection(cwd: string, now = new Date()): Promise<string> {
			const normalized = resolve(cwd);
			let gitRoot: string | undefined;
			if (gitRootByCwd.has(normalized)) {
				gitRoot = gitRootByCwd.get(normalized);
			} else {
				gitRoot = await findGitRoot(normalized);
				gitRootByCwd.set(normalized, gitRoot);
			}
			const shellPath = process.env.SHELL;
			return buildEnvSection({
				dateString: now.toDateString(),
				platform: process.platform,
				arch: process.arch,
				shell: shellPath ? basename(shellPath) : undefined,
				cwd: normalized,
				gitRoot,
			});
		},
	};
}
