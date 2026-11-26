import { access } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";
import type { ModelLike } from "./apply-patch.ts";

export type ModelFamily = "gpt" | "claude" | "gemini" | "other";

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
	if (id.includes("gemini")) return "gemini";
	return "other";
}

export function buildPromptGuidelines(options: {
	readonly model?: ModelLike;
	readonly activeTools: readonly string[];
	readonly hasSkills?: boolean;
}): string[] {
	const rules: string[] = [
		"Prefer parallelizing independent tool calls.",
		"Keep changes consistent with surrounding code structure, naming, and style.",
		"Treat unfamiliar files or uncommitted changes as potential user work; investigate before modifying or deleting them.",
		"Never run destructive git or filesystem commands (git reset --hard, git checkout --, broad recursive deletes) unless explicitly requested.",
	];

	if (options.activeTools.includes("bash")) {
		rules.push(
			"Do not chain shell commands with visual separator echoes like echo '====' or printf '---'; run separate commands or print only needed values.",
		);
	}

	if (options.activeTools.includes("remote_thread") && options.activeTools.includes("explore")) {
		rules.push(
			"When orchestrating work via remote_thread (implementor/reviewer), keep the main thread lean: check plan/git status briefly and delegate broad repo inspection to explore rather than reading dozens of source files directly.",
		);
	}

	if (options.model?.provider === "antigravity-acp" && options.activeTools.includes("explore")) {
		rules.push(
			"Never chain more than ~5 view_file calls in the main thread to understand a project or gather context; call Pi's explore tool (pi_explore via pi-bridge, or parallel explore calls by area) instead of bulk view_file calls.",
		);
	}

	const family = classifyModelFamily(options.model);
	if (family === "gpt") {
		rules.push(
			"Do not narrate routine reads, searches, or edits; share brief updates only for meaningful discoveries, tradeoffs, or blockers.",
			"Lead the final response with the outcome rather than a step-by-step log.",
			"Run targeted verification; stop expanding tests once checks pass.",
			"Bias toward action when asked to do something; continue until the goal is fulfilled.",
		);
		if (options.hasSkills) {
			rules.push("Avoid invoking or re-reading skills based solely on superficial keyword overlap.");
		}
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
