#!/usr/bin/env python3
"""Keep Herdr on the terminal background with darker wallpaper-derived selections."""

import argparse
import math
import os
from pathlib import Path
import re
import tempfile
import tomllib

BEGIN = "# BEGIN managed wallpaper surfaces"
END = "# END managed wallpaper surfaces"


def sync_colors(config_path: Path, palette_path: Path) -> bool:
    palette = palette_path.read_text()
    match = re.search(r"^\s*background\s+(#[0-9a-fA-F]{6})\s*(?:#.*)?$", palette, re.M)
    if not match:
        raise ValueError(f"No valid background in {palette_path}; keeping existing colors")
    base = match[1].lower()
    # Same rounded 16% darkening as nvim's wallpaper.lua crust surface.
    channels = [int(base[i:i + 2], 16) for i in (1, 3, 5)]
    surface = "#" + "".join(f"{math.floor(c * 0.84 + 0.5):02x}" for c in channels)
    colors = {
        "panel_bg": "reset",
        "sidebar_bg": "reset",
        "surface0": "reset",
        # Herdr uses this as the active tab foreground when panel_bg is reset.
        # Reset both to inherit the host foreground, not dark text on a dark tab.
        "surface_dim": "reset",
        "active_row_bg": surface,
        "selection_bg": surface,
        "accent": surface,  # Active tabs share Herdr's global accent token.
    }
    # Resolve the dotfiles symlink before replacing its target atomically.
    target = config_path.resolve(strict=True)
    original = target.read_text()
    tomllib.loads(original)
    if original.count(BEGIN) != 1 or original.count(END) != 1:
        raise ValueError("Missing or ambiguous managed wallpaper block; config left untouched")
    start = original.index(BEGIN) + len(BEGIN)
    end = original.index(END)
    if end < start:
        raise ValueError("Invalid managed wallpaper block; config left untouched")
    block = "\n" + "".join(f'{key} = "{value}"\n' for key, value in colors.items())
    updated = original[:start] + block + original[end:]
    parsed = tomllib.loads(updated)
    if any(parsed.get("theme", {}).get("custom", {}).get(k) != v for k, v in colors.items()):
        raise ValueError("Wallpaper block must be in [theme.custom]; config left untouched")
    if updated == original:
        return False
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as temp:
            temp_path = Path(temp.name)
            os.fchmod(temp.fileno(), target.stat().st_mode & 0o777)
            temp.write(updated)
        os.replace(temp_path, target)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    parser.add_argument("--config", type=Path, default=config_home / "herdr/config.toml")
    parser.add_argument("--palette", type=Path, default=config_home / "kitty/colors.conf")
    args = parser.parse_args()
    try:
        sync_colors(args.config, args.palette)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Herdr colors: {error}\n")


if __name__ == "__main__":
    main()
