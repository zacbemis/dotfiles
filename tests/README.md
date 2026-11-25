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

Pi harness-tuning, LSP diagnostics, and explore unit checks:

```bash
node --experimental-transform-types --test tests/test_pi_harness_tuning.ts tests/test_pi_lsp_diagnostics.ts tests/test_pi_explore.ts
```

Live Pi harness end-to-end functional verification and Base vs Tuned A/B benchmark (requires provider login; defaults to `openai-codex/gpt-6-luna` at `low` thinking, overridable via `PI_VERIFY_MODEL` and `PI_VERIFY_THINKING`):

```bash
node --experimental-transform-types --test tests/verify_pi_harness.ts
```

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
