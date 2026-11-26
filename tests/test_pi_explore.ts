import { strict as assert } from "node:assert";
import { test } from "node:test";
import { buildExploreArgs, parseExploreJsonLine, selectExploreModel } from "../.pi/agent/extensions/explore/runner.ts";

test("explore model routing, CLI flags, and JSONL parsing behave deterministically", () => {
	const available = [
		{ provider: "openai-codex", id: "gpt-6.2-sol" },
		{ provider: "openai-codex", id: "gpt-6.2-astra" },
		{ provider: "openai-codex", id: "gpt-6-luna" },
		{ provider: "openai-codex", id: "gpt-5.4" },
		{ provider: "openai-codex", id: "gpt-5.4-mini" },
		{ provider: "claude-bridge", id: "claude-opus-5-5" },
		{ provider: "claude-bridge", id: "claude-sonnet-5-5" },
		{ provider: "antigravity-acp", id: "gemini-4-neon" },
		{ provider: "antigravity-acp", id: "gemini-4-hydrogen" },
		{ provider: "antigravity-acp", id: "gemini-3.8-flash" },
	];

	const codexChoice = selectExploreModel({ provider: "openai-codex", id: "gpt-6.2-sol" }, available);
	assert.deepEqual(codexChoice, { provider: "openai-codex", id: "gpt-6.2-astra" });

	const gpt5Choice = selectExploreModel({ provider: "openai-codex", id: "gpt-5.4" }, available);
	assert.deepEqual(gpt5Choice, { provider: "openai-codex", id: "gpt-5.4-mini" });

	const lunaChoice = selectExploreModel({ provider: "openai-codex", id: "gpt-6-luna" }, available);
	assert.deepEqual(lunaChoice, { provider: "openai-codex", id: "gpt-6-luna" });

	const codexArgs = buildExploreArgs("Find auth entrypoints", codexChoice);
	assert.ok(codexArgs.includes("--no-extensions"));
	assert.ok(codexArgs.includes("--no-session"));
	assert.ok(codexArgs.includes("read,grep,find,ls"));
	assert.equal(codexArgs[codexArgs.indexOf("--model") + 1], "openai-codex/gpt-6.2-astra");
	const sysPrompt = codexArgs[codexArgs.indexOf("--system-prompt") + 1] ?? "";
	assert.match(sysPrompt, /parallelizing independent/i);

	const bridgeChoice = selectExploreModel({ provider: "claude-bridge", id: "claude-opus-5-5" }, available);
	assert.deepEqual(bridgeChoice, { provider: "claude-bridge", id: "claude-sonnet-5-5" });
	const bridgeArgs = buildExploreArgs("Trace router", bridgeChoice);
	assert.equal(bridgeArgs.includes("--no-extensions"), false);

	const neonChoice = selectExploreModel({ provider: "antigravity-acp", id: "gemini-4-neon" }, available);
	assert.deepEqual(neonChoice, { provider: "openai-codex", id: "gpt-6-luna" });
	assert.ok(buildExploreArgs("Survey repo", neonChoice).includes("--no-extensions"));

	const neonNoBuiltin = selectExploreModel(
		{ provider: "antigravity-acp", id: "gemini-4-neon" },
		[
			{ provider: "antigravity-acp", id: "gemini-4-neon" },
			{ provider: "antigravity-acp", id: "gemini-3.8-flash" },
		],
	);
	assert.deepEqual(neonNoBuiltin, { provider: "antigravity-acp", id: "gemini-3.8-flash" });

	const neonFallback = selectExploreModel(
		{ provider: "antigravity-acp", id: "gemini-4-neon" },
		[
			{ provider: "antigravity-acp", id: "gemini-4-neon" },
			{ provider: "antigravity-acp", id: "gemini-4-hydrogen" },
		],
	);
	assert.deepEqual(neonFallback, { provider: "antigravity-acp", id: "gemini-4-hydrogen" });

	const flashChoice = selectExploreModel(
		{ provider: "google", id: "gemini-3.8-flash" },
		[{ provider: "google", id: "gemini-3.8-flash" }],
	);
	assert.deepEqual(flashChoice, { provider: "google", id: "gemini-3.8-flash" });

	assert.deepEqual(parseExploreJsonLine('{"type":"tool_execution_start","toolName":"grep"}'), {
		toolCallName: "grep",
	});
	assert.deepEqual(
		parseExploreJsonLine(
			JSON.stringify({
				type: "message_update",
				assistantMessageEvent: {
					type: "thinking_delta",
					delta: "\n[Antigravity tool: Running view_file — in_progress]\n",
				},
			}),
		),
		{ toolCallName: "view_file" },
	);
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
