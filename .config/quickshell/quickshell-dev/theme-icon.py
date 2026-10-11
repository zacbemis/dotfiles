#!/usr/bin/env python3
"""Resolve GTK's logical-size icon variant; never rasterize or modify the theme."""
import json
import sys

name = sys.argv[1]
result = {"name": name, "path": ""}
try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    icon = Gtk.IconTheme.get_default().lookup_icon_for_scale(
        name, int(sys.argv[2]), max(1, round(float(sys.argv[3]))), Gtk.IconLookupFlags.FORCE_SIZE
    )
    if icon:
        result["path"] = icon.get_filename() or ""
except (ImportError, ValueError, AttributeError):
    # Quickshell's native icon source remains the fallback without PyGObject.
    pass
print(json.dumps(result))
