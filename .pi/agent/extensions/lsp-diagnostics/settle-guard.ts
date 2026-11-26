import { resolve } from "node:path";
import { LSP_DIAGNOSTICS_DISABLE_ENV } from "./manager.ts";

export const LSP_SETTLE_GUARD_DISABLE_ENV = "PI_LSP_SETTLE_GUARD";
export const LSP_SETTLE_CONTINUATION_TYPE = "lsp-settle-guard";

export interface RecheckResult {
	readonly block?: string;
	readonly errorsByFile: ReadonlyMap<string, readonly string[]>;
}

function normalizePath(cwd: string, rawPath: string): string {
	const cleaned = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
	return resolve(cwd, cleaned);
}

export function createLspSettleGuard() {
	const unresolvedFiles = new Set<string>();
	let nudgedThisTurn = false;

	return {
		resetTurn(): void {
			unresolvedFiles.clear();
			nudgedThisTurn = false;
		},

		get unresolvedCount(): number {
			return unresolvedFiles.size;
		},

		recordCheckResult(
			cwd: string,
			checkedPaths: readonly string[],
			deletedPaths: readonly string[],
			errorsByFile: ReadonlyMap<string, readonly string[]>,
		): void {
			for (const raw of deletedPaths) {
				unresolvedFiles.delete(normalizePath(cwd, raw));
			}
			for (const raw of checkedPaths) {
				const abs = normalizePath(cwd, raw);
				const errors = errorsByFile.get(abs);
				if (errors && errors.length > 0) {
					unresolvedFiles.add(abs);
				} else {
					unresolvedFiles.delete(abs);
				}
			}
		},

		async buildSettleNudge(
			cwd: string,
			recheckFiles: (workspaceCwd: string, paths: readonly string[]) => Promise<RecheckResult>,
		): Promise<string | undefined> {
			if (process.env[LSP_DIAGNOSTICS_DISABLE_ENV] === "0") return undefined;
			if (process.env[LSP_SETTLE_GUARD_DISABLE_ENV] === "0") return undefined;
			if (nudgedThisTurn || unresolvedFiles.size === 0) return undefined;

			const candidates = [...unresolvedFiles];
			const fresh = await recheckFiles(cwd, candidates);

			for (const absPath of candidates) {
				const errs = fresh.errorsByFile.get(absPath);
				if (!errs || errs.length === 0) {
					unresolvedFiles.delete(absPath);
				}
			}

			if (unresolvedFiles.size === 0 || !fresh.block) {
				return undefined;
			}

			nudgedThisTurn = true;
			return `Before finishing, resolve the remaining LSP error(s) in files edited during this turn:\n\n${fresh.block}`;
		},
	};
}
