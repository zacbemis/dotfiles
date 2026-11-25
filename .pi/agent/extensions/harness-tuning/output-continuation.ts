export const LENGTH_CONTINUATION_TYPE = "length-continuation";
export const MAX_LENGTH_CONTINUATIONS = 2;

export const LENGTH_CONTINUATION_PROMPT =
	"Your previous response was cut off at the output token limit. Continue directly from where you stopped without repeating what you already wrote.";

export interface ContextMessageLike {
	readonly role?: string;
	readonly stopReason?: string;
	readonly customType?: string;
}

export function countTrailingLengthTruncations(messages: readonly ContextMessageLike[]): number {
	let count = 0;
	let expectAssistant = true;

	for (let i = messages.length - 1; i >= 0; i--) {
		const msg = messages[i];
		if (!msg) continue;

		if (expectAssistant) {
			if (msg.role === "assistant" && msg.stopReason === "length") {
				count++;
				expectAssistant = false;
				continue;
			}
			break;
		}

		if (msg.role === "custom" && msg.customType === LENGTH_CONTINUATION_TYPE) {
			expectAssistant = true;
			continue;
		}
		break;
	}

	return count;
}
