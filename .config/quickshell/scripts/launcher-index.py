#!/usr/bin/env python3
"""Read-only, bounded Run/PATH and single-directory file-browser indexes."""
import json
import os
from pathlib import Path
import sys
import unicodedata


def normalized(text):
    return "".join(c for c in unicodedata.normalize("NFKD", text).casefold() if not unicodedata.combining(c))


def commands():
    found = set()
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        if not directory:
            continue
        try:
            for entry in os.scandir(directory):
                if entry.is_file() and os.access(entry.path, os.X_OK):
                    found.add(entry.name)
                    if len(found) >= 20000:
                        return sorted(found, key=normalized)
        except OSError:
            continue
    return sorted(found, key=normalized)


def files(query):
    expanded = os.path.expanduser(query)
    path = Path(expanded)
    directory = path if expanded.endswith(os.sep) else path.parent
    prefix = "" if expanded.endswith(os.sep) else path.name
    result = []
    try:
        if directory.parent != directory:
            result.append({"key": "parent:" + str(directory.parent), "kind": "directory", "name": "..",
                           "detail": "Parent folder", "value": str(directory.parent), "icon": "go-up"})
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.name.startswith(".") or not normalized(entry.name).startswith(normalized(prefix)):
                    continue
                folder = entry.is_dir()
                result.append({"key": "file:" + entry.path, "kind": "directory" if folder else "file",
                               "name": entry.name, "detail": str(directory), "value": entry.path,
                               "icon": "folder" if folder else "text-x-generic"})
                if len(result) >= 2000:
                    break
        result.sort(key=lambda row: (row["name"] != "..", row["kind"] != "directory", normalized(row["name"])))
        return {"query": query, "rows": result, "error": ""}
    except OSError as error:
        return {"query": query, "rows": [], "error": str(error)}


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "commands":
        print(json.dumps(commands()))
    elif len(sys.argv) == 3 and sys.argv[1] == "files":
        print(json.dumps(files(sys.argv[2])))
    else:
        raise SystemExit("usage: launcher-index.py commands | files QUERY")
