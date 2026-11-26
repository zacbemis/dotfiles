# Tests

## Coverage

- Installer reruns, backups, failure handling and shell setup.
- Stow deployment, private-state preservation and filtered tool preferences.
- Hyprland rules, idle brightness, fonts and wallpaper colors.
- Neovim explorer, tabs, quitting, syntax and Git review.
- Quickshell services, notifications, connectivity, audio, preferences, themes and layout.

Run unit/headless checks from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

Optional dependencies are skipped when unavailable. Installer and hardware actions use fixtures/mocks.

Pi remote-thread mailbox, wait, cancellation, and standalone restart checks (Node 24 and `flock` from util-linux; no provider login required):

```bash
node --experimental-transform-types --test tests/test_pi_remote_thread.ts
```

Pi harness-tuning, LSP diagnostics, explore, and mocked-stream full-session integration checks (no provider login or network calls required):

```bash
node --experimental-transform-types --test \
  tests/test_pi_harness_tuning.ts \
  tests/test_pi_lsp_diagnostics.ts \
  tests/test_pi_explore.ts \
  tests/test_pi_harness_integration.ts
```

Live Pi harness end-to-end functional verification and multi-trial Base vs Tuned A/B benchmark with held-out anti-tampering checks and prompt-cache hit-rate assertions (requires provider login; defaults to `openai-codex/gpt-6-luna` at `low` thinking and `k=3` trials per benchmark, overridable via `PI_VERIFY_MODEL`, `PI_VERIFY_THINKING`, and `PI_VERIFY_TRIALS`):

```bash
node --experimental-transform-types --test tests/verify_pi_harness.ts
# Quick single-trial smoke run:
PI_VERIFY_TRIALS=1 node --experimental-transform-types --test tests/verify_pi_harness.ts
```

For larger external containerized benchmarks across real repositories, Docker is available to run a subset of Terminal-Bench via [Harbor](https://github.com/harbor-framework/harbor) (`harbor run -d terminal-bench@2.1 -a pi ...`) to compare Base vs Tuned Pi on third-party tasks.

Herdr's Rust shortcut helper has its own unit and mock-socket integration tests:

```bash
cargo test --manifest-path tools/herdr-control/Cargo.toml --locked
```

## Desktop checks

Run on an unlocked Hyprland session:

```bash
python3 tests/verify_quickshell.py
python3 tests/verify_quickshell_features.py
python3 tests/verify_quickshell_profiles.py
python3 tests/verify_quickshell_settings.py
python3 tests/verify_hyprland_windows.py
```

These use isolated shell instances, preview/private-bus notifications and temporary browser profiles.
Runtime warnings fail Quickshell checks. Screenshot options capture open apps and require manual review.
