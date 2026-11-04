#!/usr/bin/env python3
"""Track explicit tool configs and filter preferences out of mixed private state.

No credentials, project trust, sessions or package caches are exported. Restoring
preferences preserves unrelated JSON state; an existing Codex TOML is never
rewritten. No tools, hooks, extensions or network installers are executed.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
CURSOR_KEYS = (
    "version", "permissions", "editor", "display", "notifications", "hints",
    "modelSlashCommands", "steering", "rewind", "model", "maxMode", "modelParameters",
    "selectedModel", "exploreSubagentModel", "network", "approvalMode",
    "autoAcceptWebSearch", "sandbox", "attribution",
)
CODEX_KEYS = ("model", "model_reasoning_effort", "model_reasoning_summary", "model_verbosity", "personality", "features")
JSON_PREFERENCES = (
    ("cursor-cli.json", ".config/cursor/cli-config.json", CURSOR_KEYS),
    ("cursor-argv.json", ".cursor/argv.json", ("enable-crash-reporter", "password-store", "disable-hardware-acceleration")),
    ("antigravity-cli.json", ".gemini/antigravity-cli/settings.json", ("model", "enableTelemetry")),
)
CREDENTIAL = re.compile(r"-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|\bsk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._-]{12,}")
PRIVATE_KEY = re.compile(r"^(?:auth|authInfo|oauth|api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|copilot_tokens|trustedWorkspaces|trusted_hash|projects)$", re.I)


def jsonc(text):
    # Preserve strings verbatim while removing comments and trailing commas.
    strings = r'("(?:\\.|[^"\\])*")'
    text = re.sub(strings + r'|//[^\r\n]*|/\*[\s\S]*?\*/', lambda m: m[1] or " ", text)
    text = re.sub(strings + r'|,(\s*[}\]])', lambda m: m[1] or m[2], text)
    return json.loads(text)


def check_preferences(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if PRIVATE_KEY.fullmatch(key):
                raise ValueError(f"Private state cannot be exported: {key}")
            check_preferences(item)
    elif isinstance(value, list):
        for item in value:
            check_preferences(item)
    elif isinstance(value, str) and CREDENTIAL.search(value):
        raise ValueError("Credential-shaped value cannot be exported")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".tool-settings-", delete=False) as temporary:
        temporary.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        name = Path(temporary.name)
    name.replace(path)


def preference_values(home):
    for name, relative, keys in JSON_PREFERENCES:
        path = home / relative
        if path.is_file():
            data = jsonc(path.read_text())
            selected = {key: data[key] for key in keys if key in data}
            check_preferences(selected)
            yield name, selected
    path = home / ".codex/config.toml"
    if path.is_file():
        data = tomllib.loads(path.read_text())
        selected = {key: data[key] for key in CODEX_KEYS if key in data}
        check_preferences(selected)
        yield "codex.json", selected


def capture(root, home):
    for name, selected in preference_values(home):
        write_json(root / "tool-settings" / name, selected)
        print(f"Captured filtered preferences: {name}")


def backup(path, home, directory):
    if path.exists() or path.is_symlink():
        target = directory / path.relative_to(home)
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copy2(path, target, follow_symlinks=False)


def apply(root, home, directory):
    for name, relative, keys in JSON_PREFERENCES:
        source = root / "tool-settings" / name
        if not source.is_file():
            continue
        selected = json.loads(source.read_text())
        check_preferences(selected)
        if not isinstance(selected, dict) or set(selected) - set(keys):
            raise ValueError(f"Unexpected preference keys in {name}")
        path = home / relative
        current = jsonc(path.read_text()) if path.is_file() else {}
        if not isinstance(current, dict):
            raise ValueError(f"Expected a JSON object in {relative}; leaving it untouched")
        # Replace only owned top-level preferences. Auth/cache/trust keys remain local.
        backup(path, home, directory)
        write_json(path, dict(current, **selected))
        print(f"Applied preferences: {relative}")
    path = home / ".codex/config.toml"
    source = root / "tool-settings/codex.json"
    if path.exists() or path.is_symlink():
        print("Kept existing .codex/config.toml; merge tool-settings/codex.json preferences manually if needed")
    elif source.is_file():
        data = json.loads(source.read_text())
        check_preferences(data)
        if set(data) - set(CODEX_KEYS):
            raise ValueError("Unexpected Codex preference keys")
        lines = []
        for key, value in data.items():
            if key == "features":
                continue
            if not isinstance(value, str):
                raise ValueError(f"Expected a string for Codex {key}")
            lines.append(f"{key} = {json.dumps(value)}")
        if data.get("features"):
            lines.extend(["", "[features]"])
            for key, value in data["features"].items():
                if not isinstance(value, bool):
                    raise ValueError(f"Expected a boolean for Codex feature {key}")
                lines.append(f"{json.dumps(key)} = {str(value).lower()}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines) + "\n")
        path.chmod(0o600)
        print("Created .codex/config.toml without importing trust decisions")


def managed_files(root):
    for name in json.loads((root / "tool-settings/manifest.json").read_text())["files"]:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Manifest paths must be relative to HOME")
        if not (root / relative).is_file():
            raise ValueError(f"Missing tracked config: {relative}")
        yield relative


def link_status(source, path):
    if path.resolve() == source.resolve():
        return "absolute" if path.is_symlink() and os.path.isabs(os.readlink(path)) else "linked"
    if not path.is_file():
        return "missing"
    return "matches" if path.read_bytes() == source.read_bytes() else "differs"


def link(root, home, directory):
    for relative in managed_files(root):
        source, path = root / relative, home / relative
        # A Stow-folded parent can expose the actual source file, not a leaf
        # symlink. Never replace that file with a link to itself.
        if not path.is_symlink() and path.resolve() == source.resolve():
            continue
        target = os.path.relpath(source.resolve(), path.parent.resolve())
        if path.is_symlink() and os.readlink(path) == target and path.resolve() == source.resolve():
            continue
        backup(path, home, directory)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + f".dotfiles-{os.getpid()}")
        temporary.symlink_to(target)
        temporary.replace(path)
        print(f"Linked: {relative}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "capture-preferences", "link", "apply-preferences"))
    args = parser.parse_args()
    home = Path.home()
    if args.action == "capture-preferences":
        capture(ROOT, home)
    elif args.action == "status":
        for relative in managed_files(ROOT):
            source, path = ROOT / relative, home / relative
            state = link_status(source, path)
            print(f"{state:8} {relative}")
        for name, selected in preference_values(home):
            path = ROOT / "tool-settings" / name
            state = "missing" if not path.is_file() else "matches" if json.loads(path.read_text()) == selected else "differs"
            print(f"{state:8} tool-settings/{name} (filtered preferences)")
    else:
        directory = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state"))) / "dotfiles-tool-settings" / (datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}")
        directory.mkdir(parents=True, mode=0o700)
        (link if args.action == "link" else apply)(ROOT, home, directory)
        print(f"Existing files backed up under {directory}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f"tool-settings: {error}")
