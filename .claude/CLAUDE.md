# Commits and pull requests

- Do not write in the first person ("I", "we", "my") in commit messages, PR titles, or PR descriptions.
- Do not add any Claude or AI attribution to commits or PRs: no `Co-Authored-By: Claude ...` trailer, no "Generated with Claude Code" footer, no "built by Claude" or similar wording.

## Architecture and feature development

- Do not preserve backward compatibility unless explicitly asked to do so.
- Before designing a feature, study how established projects solve comparable problems. Use that research to inform the design.
- Build clean, modular code with a clear architecture and separation of concerns. Keep components focused and responsibilities explicit.
- Integrate features into the architecture; never bolt them on. If a feature requires a refactor, stop and explain why the refactor is necessary before proceeding.
- Build features in layers. Start with the smallest working end-to-end version, validate it, and build each new capability on top of the already working foundation.
- Make architectural decisions with long-term maintainability in mind. If the architecture requires a rewrite, stop and explain why, including the trade-offs, before proceeding.
