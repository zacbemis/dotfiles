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
