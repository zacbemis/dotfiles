#!/usr/bin/env python3
"""Read-only wallpaper discovery; JSON preserves spaces, Unicode and newlines."""
import json
import sys
from pathlib import Path


def scan(directory: Path, current: Path) -> list[dict]:
    selected = current.resolve()
    if not directory.is_dir():
        return []
    extensions = {".jpg", ".jpeg", ".png", ".webp"}
    return [
        {"path": str(path.absolute()), "name": path.name,
         "current": path.resolve() == selected}
        for path in sorted(directory.rglob("*"), key=lambda p: str(p).casefold())
        if path.is_file() and path.suffix.lower() in extensions
    ]


if __name__ == "__main__":
    try:
        print(json.dumps(scan(Path(sys.argv[1]), Path(sys.argv[2]))))
    except OSError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
