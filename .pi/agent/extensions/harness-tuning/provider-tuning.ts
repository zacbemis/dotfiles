import { classifyModelFamily } from "./prompt-tuning.ts";

export interface ProviderModelLike {
	readonly id?: string;
	readonly provider?: string;
	readonly api?: string;
}

// Keep cache-warming probes (maxTokens: 1 -> clamped to 16 on OpenAI Responses) intact.
const MAX_OUTPUT_TOKEN_KEEP_THRESHOLD = 64;

function isPlainRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function tuneOpenAIResponsesPayload(payload: unknown, model: ProviderModelLike | undefined): unknown {
	if (model?.provider !== "openai" || model?.api !== "openai-responses") return undefined;
	if (!isPlainRecord(payload)) return undefined;

	let changed = false;
	const next: Record<string, unknown> = { ...payload };

	if (classifyModelFamily(model) === "gpt") {
		const existingText = isPlainRecord(next.text) ? next.text : undefined;
		if (existingText?.verbosity === undefined) {
			next.text = { ...(existingText ?? {}), verbosity: "low" };
			changed = true;
		}
	}

	if (typeof next.max_output_tokens === "number" && next.max_output_tokens > MAX_OUTPUT_TOKEN_KEEP_THRESHOLD) {
		delete next.max_output_tokens;
		changed = true;
	}

	return changed ? next : undefined;
}

export function applyProviderHeaders(
	headers: Record<string, string | null>,
	model: ProviderModelLike | undefined,
	sessionId: string | undefined,
): void {
	if (model?.provider === "xai" && sessionId && !headers["x-grok-conv-id"]) {
		headers["x-grok-conv-id"] = sessionId;
	}
}
