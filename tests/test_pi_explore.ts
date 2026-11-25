import { strict as assert } from "node:assert";
import { test } from "node:test";
import { buildExploreArgs, parseExploreJsonLine, selectExploreModel } from "../.pi/agent/extensions/explore/runner.ts";

test("explore model routing, CLI flags, and JSONL parsing behave deterministically", () => {
	const available = [
		{ provider: "openai-codex", id: "gpt-6.2-sol" },
		{ provider: "openai-codex", id: "gpt-6.2-astra" },
		{ provider: "claude-bridge", id: "claude-opus-5-5" },
		{ provider: "claude-bridge", id: "claude-sonnet-5-5" },
	];

	const codexChoice = selectExploreModel({ provider: "openai-codex", id: "gpt-6.2-sol" }, available);
	assert.deepEqual(codexChoice, { provider: "openai-codex", id: "gpt-6.2-astra" });

	const codexArgs = buildExploreArgs("Find auth entrypoints", codexChoice);
	assert.ok(codexArgs.includes("--no-extensions"));
	assert.ok(codexArgs.includes("--no-session"));
	assert.ok(codexArgs.includes("read,grep,find,ls"));
	assert.equal(codexArgs[codexArgs.indexOf("--model") + 1], "openai-codex/gpt-6.2-astra");

	const bridgeChoice = selectExploreModel({ provider: "claude-bridge", id: "claude-opus-5-5" }, available);
	assert.deepEqual(bridgeChoice, { provider: "claude-bridge", id: "claude-sonnet-5-5" });
	const bridgeArgs = buildExploreArgs("Trace router", bridgeChoice);
	assert.equal(bridgeArgs.includes("--no-extensions"), false);

	assert.deepEqual(parseExploreJsonLine('{"type":"tool_execution_start","toolName":"grep"}'), {
		toolCallName: "grep",
	});
	assert.deepEqual(
		parseExploreJsonLine(
			JSON.stringify({
				type: "message_end",
				message: { role: "assistant", stopReason: "stop", content: [{ type: "text", text: "Found in src/a.ts:12" }] },
			}),
		),
		{ assistantText: "Found in src/a.ts:12", errorMessage: undefined },
	);
});
