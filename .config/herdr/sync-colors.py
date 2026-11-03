#!/usr/bin/env python3
"""Keep Herdr on the terminal background with visible wallpaper-accent selections."""

import argparse
import math
import os
from pathlib import Path
import re
import tempfile
import tomllib

BEGIN = "# BEGIN managed wallpaper surfaces"
END = "# END managed wallpaper surfaces"


def luminance(rgb):
    channels = [c / 255 for c in rgb]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
              for c in channels]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(first, second):
    light, dark = sorted((luminance(first), luminance(second)), reverse=True)
    return (light + 0.05) / (dark + 0.05)


def selection_color(palette):
    background = palette["background"]
    fallback = (255, 255, 255) if luminance(background) < 0.179 else (0, 0, 0)
    foreground = palette.get("foreground", fallback)
    # Matugen puts its wallpaper primary in color4; Pywal derives it from the image.
    accent = palette.get("color4", palette.get("selection_background", foreground))
    endpoint = (255, 255, 255) if luminance(foreground) > luminance(background) else (0, 0, 0)
    # Tint the terminal background first. If the accent is too subdued, brighten
    # or darken that same hue until the selection is visible and text is readable.
    for start, end in ((background, accent), (accent, endpoint)):
        for step in range(101):
            rgb = tuple(math.floor(a + (b - a) * step / 100 + 0.5)
                        for a, b in zip(start, end))
            if contrast(rgb, background) >= 2.2 and contrast(rgb, foreground) >= 4.5:
                return "#" + "".join(f"{c:02x}" for c in rgb)
    raise ValueError("Palette cannot provide readable selections; keeping existing colors")


def sync_colors(config_path: Path, palette_path: Path) -> bool:
    palette = {
        key: tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))
        for key, value in re.findall(
            r"^\s*(\w+)\s+(#[0-9a-fA-F]{6})\s*(?:#.*)?$", palette_path.read_text(), re.M
        )
    }
    if "background" not in palette:
        raise ValueError(f"No valid background in {palette_path}; keeping existing colors")
    surface = selection_color(palette)
    colors = {
        "panel_bg": "reset",
        "sidebar_bg": "reset",
        "surface0": "reset",
        # Herdr uses this as the active tab foreground when panel_bg is reset.
        # Reset both to inherit the host foreground, checked against the tint.
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
