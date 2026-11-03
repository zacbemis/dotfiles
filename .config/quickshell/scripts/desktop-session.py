#!/usr/bin/env python3
"""Single-instance daily shell, checked notification handoff and legacy rollback.

Only activate/legacy change desktop ownership. Normal start never evicts an
unrelated notification server. All process signals are restricted to this user,
this session, or recorded PID/start-time identities belonging to this config.
"""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import time

CONFIG = Path(__file__).resolve().parents[1]
ENV = dict(os.environ)
STATE = Path(ENV.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell-desktop"
RUNTIME = Path(ENV.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "quickshell-desktop"


def run(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, timeout=15, **kwargs)


def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(data)
    temporary.chmod(0o600)
    temporary.replace(path)


def mode():
    try:
        return "legacy" if (STATE / "mode").read_text().strip() == "legacy" else "quickshell"
    except FileNotFoundError:
        return "quickshell"


def identity(pid):
    try:
        directory = Path(f"/proc/{pid}")
        if directory.stat().st_uid != os.getuid():
            return None
        fields = (directory / "stat").read_text().rsplit(")", 1)[1].split()
        return None if fields[0] == "Z" else {"pid": int(pid), "start": fields[19]}
    except (OSError, IndexError, ValueError):
        return None


def alive(record):
    return bool(record and identity(record["pid"]) == record)


def session():
    try:
        value = json.loads((RUNTIME / "session.json").read_text())
        return value if value.get("config") == str(CONFIG) else {}
    except (OSError, ValueError):
        return {}


def bus_path(address):
    match = re.search(r"(?:^|;)unix:path=([^,;]+)", address)
    return match[1] if match else address


def legacy_pids(name):
    found = []
    for directory in Path("/proc").iterdir():
        if not directory.name.isdigit():
            continue
        try:
            if directory.stat().st_uid != os.getuid() or (directory / "comm").read_text().strip() != name:
                continue
            environment = dict(item.split("=", 1) for item in (directory / "environ").read_bytes().decode(errors="replace").split("\0") if "=" in item)
            if bus_path(environment.get("DBUS_SESSION_BUS_ADDRESS", "")) == bus_path(ENV.get("DBUS_SESSION_BUS_ADDRESS", "")):
                record = identity(int(directory.name))
                if record:
                    found.append(record)
        except (OSError, ValueError):
            continue
    return found


def terminate(records):
    for record in records:
        if alive(record):
            os.kill(record["pid"], signal.SIGTERM)
    deadline = time.monotonic() + 6
    while any(alive(record) for record in records) and time.monotonic() < deadline:
        time.sleep(.05)
    if any(alive(record) for record in records):
        raise RuntimeError("A desktop process did not exit after SIGTERM; not forcing it")


def notification_owner():
    result = run(["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus", "--object-path", "/org/freedesktop/DBus",
                  "--method", "org.freedesktop.DBus.GetConnectionUnixProcessID", "org.freedesktop.Notifications"])
    match = re.search(r"uint32 (\d+)", result.stdout)
    return int(match[1]) if result.returncode == 0 and match else None


def ipc(target, method, *arguments):
    data = session()
    if not alive(data.get("shell")):
        raise RuntimeError("The daily Quickshell instance is not running")
    result = run(["qs", "ipc", "--pid", str(data["shell"]["pid"]), "call", target, method, *map(str, arguments)])
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Quickshell IPC failed")
    return result.stdout.strip()


def healthy():
    try:
        data = session()
        if not alive(data.get("supervisor")) or not alive(data.get("shell")):
            return False
        status = json.loads(ipc("shell", "status"))
        return status["notifications"] == "server" and notification_owner() == data["shell"]["pid"]
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired):
        return False


@contextlib.contextmanager
def operation_lock():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / "operation.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def spawn(command, name, environment=None):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / (name + ".log")).open("a") as log:
        return subprocess.Popen(command, env=ENV if environment is None else environment, stdin=subprocess.DEVNULL, stdout=log,
                                stderr=subprocess.STDOUT, start_new_session=True)


def serve():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (RUNTIME / "instance.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        stopping = False
        child = None
        def stop(_signal, _frame):
            nonlocal stopping
            stopping = True
            if child and child.poll() is None:
                child.terminate()
        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        env = dict(ENV, QUICKSHELL_NOTIFICATIONS="server", QUICKSHELL_COMPARE="0", QUICKSHELL_BAR="1", QUICKSHELL_PERSIST_SETTINGS="1",
                   QUICKSHELL_STARTUP_UPDATES=ENV.get("QUICKSHELL_STARTUP_UPDATES", "1"))
        env.pop("QUICKSHELL_ENABLE_NOTIFICATIONS", None)
        failures = 0
        try:
            while not stopping and failures < 5:
                if notification_owner() is not None:
                    raise RuntimeError("Another notification server owns the session bus name")
                started = time.monotonic()
                child = subprocess.Popen(["bash", str(CONFIG / "run.sh"), "--no-color"], env=env)
                atomic(RUNTIME / "session.json", json.dumps({"config": str(CONFIG), "supervisor": identity(os.getpid()), "shell": identity(child.pid)}))
                code = child.wait()
                if stopping:
                    break
                failures = failures + 1 if time.monotonic() - started < 30 else 0
                print(f"Quickshell exited ({code}); retry {failures}/5", flush=True)
                time.sleep(1)
                env["QUICKSHELL_STARTUP_UPDATES"] = "0"
        finally:
            if child and child.poll() is None:
                child.terminate()
                child.wait(timeout=6)
            data = session()
            if data.get("supervisor") == identity(os.getpid()):
                (RUNTIME / "session.json").unlink(missing_ok=True)


def stop_shell():
    data = session()
    if alive(data.get("supervisor")):
        terminate([data["supervisor"]])
    if alive(data.get("shell")):
        terminate([data["shell"]])


def start_shell():
    if healthy():
        return
    owner = notification_owner()
    data = session()
    if alive(data.get("supervisor")):
        # It may still be starting/recovering. Do not launch a second supervisor.
        pass
    else:
        if owner is not None:
            raise RuntimeError(f"Notification name is owned by PID {owner}; use 'activate' for a checked SwayNC handoff")
        spawn([sys.executable, str(Path(__file__).resolve()), "serve"], "desktop")
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if healthy():
            return
        time.sleep(.1)
    raise RuntimeError(f"Quickshell failed its bus/IPC health check; see {STATE / 'desktop.log'}")


def start_legacy():
    for name in ("waybar", "swaync"):
        if not legacy_pids(name):
            if name == "swaync" and notification_owner() is not None:
                raise RuntimeError("Cannot start SwayNC alongside another notification server")
            spawn([name], name)


def activate():
    missing = [name for name in ("qs", "gdbus", "bash") if not shutil.which(name)]
    if missing or not (CONFIG / "shell.qml").is_file():
        raise RuntimeError("Missing daily-shell dependencies/config: " + ", ".join(missing))
    # Keep the existing bar visible until the replacement is actually healthy.
    swaync = legacy_pids("swaync")
    owner = notification_owner()
    if owner is not None and owner not in [record["pid"] for record in swaync] and not healthy():
        raise RuntimeError(f"Refusing to replace an unrelated notification server (PID {owner})")
    old_mode = "legacy" if swaync or legacy_pids("waybar") else mode()
    try:
        terminate(swaync)
        deadline = time.monotonic() + 3
        while notification_owner() in [record["pid"] for record in swaync] and time.monotonic() < deadline:
            time.sleep(.05)
        start_shell()
        terminate(legacy_pids("waybar"))
        atomic(STATE / "mode", "quickshell\n")
    except Exception:
        stop_shell()
        atomic(STATE / "mode", old_mode + "\n")
        start_legacy()
        raise


def legacy():
    stop_shell()
    atomic(STATE / "mode", "legacy\n")
    start_legacy()


def palette():
    # Quickshell watches its canonical palette. Never auto-start retired daemons.
    if mode() == "legacy":
        for record in legacy_pids("waybar"):
            if alive(record):
                os.kill(record["pid"], signal.SIGUSR2)
        if legacy_pids("swaync"):
            run(["swaync-client", "-R"])
            run(["swaync-client", "-rs"])


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "start"
    if action == "serve":
        serve()
        return
    if action == "palette":
        palette()
        return
    with operation_lock():
        if action == "activate":
            activate()
        elif action == "legacy":
            legacy()
        elif action == "stop":
            stop_shell()
        elif action == "status":
            print(json.dumps({"mode": mode(), "healthy": healthy(), "notificationOwner": notification_owner(), "session": session()}))
        elif action in {"start", "restart"}:
            if mode() == "legacy":
                if action == "restart":
                    terminate(legacy_pids("waybar") + legacy_pids("swaync"))
                start_legacy()
            else:
                if action == "restart":
                    stop_shell()
                    ENV["QUICKSHELL_STARTUP_UPDATES"] = "0"
                start_shell()
        elif action in {"launcher", "wallpaper", "notifications", "controls", "settings", "run", "files"}:
            if mode() == "legacy":
                if action == "settings":
                    raise RuntimeError("Quickshell settings require daily Quickshell mode; use desktop.sh activate first")
                if action in {"launcher", "run", "files", "wallpaper"}:
                    selected = {"launcher": "drun", "run": "run", "files": "filebrowser", "wallpaper": "wallpaper"}[action]
                    spawn(["rofi", "-show", selected, "-theme", str(Path.home() / ".config/rofi/theme.rasi")], "rofi")
                else:
                    run(["swaync-client", "-t", "-sw"])
            else:
                start_shell()
                print(ipc("launcher", "mode", action) if action in {"run", "files"} else ipc(action, "toggle"))
        else:
            raise RuntimeError("usage: desktop.sh start|activate|restart|stop|status|legacy|palette|launcher|run|files|wallpaper|notifications|controls|settings")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"quickshell-desktop: {error}", file=sys.stderr)
        raise SystemExit(1)
