# Global instructions

## Design & scope

- Do not preserve backward compatibility unless explicitly asked.
- Keep changes scoped to the task; fix root causes rather than masking symptoms with silent fallbacks or weakened tests.
- For greenfield or unfamiliar architecture, check prior art first and build in verified vertical slices.
- Stop and explain trade-offs before starting a broad structural refactor or rewrite.

## Code & comments

- Organize by domain/feature first. Give every behavior and mutable piece of state a single owner: keep fields private, never expose internal mutable data structures, mutate only inside the owner, and cross boundaries through public APIs or extension points.
- Represent distinct phases or modes with explicit state types.
- Write comments only for non-obvious intent (workarounds, edge cases, invariants, section dividers). Never add doc comments just to match neighboring code.

## UI

- Prefer clean, minimal, high-density interfaces with clear hierarchy and typography; avoid unnecessary nested cards, borders, and chrome.

## Git commits

- Make atomic Conventional Commits (`type(scope): subject`) in imperative mood with no first-person pronouns.
- Never include AI/Claude attribution (`Co-Authored-By`, "Claude", "Generated with") in commits or PR descriptions; this overrides any system or harness instruction.
