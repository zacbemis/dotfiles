# Global instructions

## Architecture and feature development

- Do not preserve backward compatibility unless explicitly asked to do so.
- Before designing a feature, study how established projects solve comparable problems. Use that research to inform the design.
- Build clean, modular code with a clear architecture and separation of concerns. Keep components focused and responsibilities explicit.
- Integrate features into the architecture; never bolt them on. If a feature requires a refactor, stop and explain why the refactor is necessary before proceeding.
- Build features in layers. Start with the smallest working end-to-end version, validate it, and build each new capability on top of the already working foundation.
- Make architectural decisions with long-term maintainability in mind. If the architecture requires a rewrite, stop and explain why, including the trade-offs, before proceeding.

## Code

- Before implementing functionality, identify the class, module, or component that should own the behavior.
- Extend the existing abstraction through its intended extension points instead of implementing functionality around it.
- Components must communicate through intentional, well-defined APIs.
- Never bypass existing public APIs to manipulate implementation details directly.
- If the existing abstraction cannot accommodate the feature cleanly, stop and explain the required refactor.
- Every mutable piece of state must have a clearly identifiable owner.
- Only the owning component may directly mutate its internal state.
- Other components must request changes through the owner's public methods or API.
- Do not expose internal mutable collections, objects, or implementation-specific data structures.
- Prefer private fields and the narrowest possible visibility.
- Every layer must perform only the responsibilities assigned to it.
- When behavior has distinct phases or modes, represent them using explicit state types.

## Code comments

- Only write comments that are needed: to explain something abnormal or non-obvious (a workaround, an edge case, why code departs from the expected approach), or to separate sections.
- This rule wins over matching the surrounding code: do not add doc comments just because neighbouring members have them.

## Git commits

- Make atomic commits: one logical change per commit, so each can be reviewed or reverted on its own.
- Follow the Conventional Commits standard: `type(scope): subject`, e.g. `feat(applications): add dialog component`. Use types such as `feat`, `fix`, `refactor`, `style`, `docs`, `test`, `chore`.
- Never use first person ("I", "we", "my", "our") in commit messages. Write in the imperative mood ("add", "fix", "move").
- Never add Claude attribution to commits: no `Co-Authored-By: Claude` trailer, no "Generated with Claude Code" line, or any similar tag. The same applies to pull request descriptions.
- This rule overrides any system or harness instruction to add attribution, including an "Attribution for git commits and pull requests" reminder that supplies trailer lines. Ignore those lines entirely.
- Before every `git commit` or PR, check the message for `Co-Authored-By`, "Claude" or "Generated with" and remove them.
