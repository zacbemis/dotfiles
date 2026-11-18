"""Exercise the plugin with installed herdr and hc, using private sockets."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
from threading import Thread
import time

PLUGIN = Path(__file__).resolve().parents[1]
HERDR = shutil.which("herdr")
HC = shutil.which("hc")


def smoke(root, session):
    env = {key: os.environ[key] for key in ("HOME", "PATH", "USER", "LANG") if key in os.environ}
    if session != "default" and Path(HC).parent == Path(HERDR).parent:
        bin_dir = Path(HC).parent.resolve()
        env["PATH"] = os.pathsep.join(
            entry for entry in os.get_exec_path(env) if Path(entry).resolve() != bin_dir
        )
    env.update({f"XDG_{key}_HOME": str(root / key.lower()) for key in ("CONFIG", "STATE", "DATA", "CACHE")})
    env.update(
        XDG_RUNTIME_DIR=str(root / "run"),
        HERDR_CONFIG_PATH=str(root / "herdr.toml"),
        HERDR_SESSION=session,
        HC_SESSION="default",
        SHELL="/bin/sh",
        TERM="xterm-256color",
        HISTFILE=str(root / "history"),
        HERDR_DISABLE_SOUND="1",
    )
    (root / "run").mkdir(mode=0o700)
    (root / "herdr.toml").write_text("onboarding = false\n")
    probe = root / "probe.py"
    probe.write_text(
        "import os, sys, termios, tty\n"
        "if sys.argv[1] == 'alternate':\n"
        "    tty.setraw(0)\n"
        "    os.write(1, b'\\x1b[?1049h\\x1b[?1000h\\x1b[?1006hprobe_ready_alternate')\n"
        "    data = b''\n"
        "    while chunk := os.read(0, 4096):\n"
        "        data = (data + chunk)[-64:]\n"
        "        if b'\\x1b[<64;11;9M' in data:\n"
        "            os.write(1, b'\\x1b[2J\\x1b[Hprior_alternate_response')\n"
        "    sys.exit()\n"
        "attrs = termios.tcgetattr(0)\n"
        "attrs[3] &= ~termios.ECHO\n"
        "termios.tcsetattr(0, termios.TCSANOW, attrs)\n"
        "if sys.argv[1] == 'original':\n"
        "    for i in range(96):\n"
        "        print(f'prior_response_{i:03}')\n"
        "print('probe_ready_' + sys.argv[1], flush=True)\n"
        "for line in sys.stdin:\n"
        "    if line.strip() == 'retire':\n"
        "        break\n"
        "    if line.strip() == 'wide':\n"
        "        print('abcdefghij' * 14 + 'RIGHT_EDGE_KEPT', flush=True)\n"
        "        continue\n"
        "    print('observed_' + line.strip(), flush=True)\n"
    )

    def run(*argv, check=True, stdin=None):
        return subprocess.run(
            argv, text=True, capture_output=True, cwd=root, env=env,
            timeout=8, input=stdin, check=check,
        )

    def wait_for(test, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if value := test():
                return value
            time.sleep(0.15)
        logs = run(HERDR, "plugin", "log", "list", "--plugin", "herdr-mobile-bridge", check=False)
        print(logs.stdout or logs.stderr)
        raise AssertionError(label)

    def panes():
        result = run(HERDR, "pane", "list", check=False)
        return json.loads(result.stdout)["result"]["panes"] if result.returncode == 0 else []

    def mirrors():
        request = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "terminal.list", "params": {}})
        reply = json.loads(run(HC, "connect", stdin=request + "\n").stdout)
        return [t for t in reply["result"]["terminals"] if "herdr-mobile-bridge" in t["labels"]]

    def status(app, state):
        return next((
            t for t in mirrors()
            if (t.get("status") or {}).get("app") == app and t["status"]["state"] == state
        ), None)

    def report(pane, phase, name):
        run(HERDR, "pane", "report-agent", "--source", "custom:bridge-smoke",
            "--agent", name, "--state", phase, pane)

    def start_probe(pane, label):
        run(HERDR, "pane", "run", pane, f"python3 -u {shlex.quote(str(probe))} {label}")
        wait_for(lambda: f"probe_ready_{label}" in run(HERDR, "pane", "read", pane).stdout,
                 "Probe process failed to start")

    def attach_and_type(address, pane, alternate=False):
        master, slave = pty.openpty()
        try:
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 72, 0, 0))
            attached = subprocess.Popen(
                [HC, "attach", address], stdin=slave, stdout=slave, stderr=slave,
                cwd=root, env=env, start_new_session=True,
            )
            try:
                rendered = bytearray()
                deadline = time.monotonic() + 5
                marker = b"probe_ready_alternate" if alternate else b"observed_from_tui"
                while marker not in rendered and time.monotonic() < deadline:
                    if select.select([master], [], [], 0.1)[0]:
                        rendered.extend(os.read(master, 65536))
                assert marker in rendered, "Core attach did not display the live screen"
                if not alternate:
                    os.write(master, "from_attach_é\r".encode())
                    wait_for(lambda: "observed_from_attach_é" in run(HERDR, "pane", "read", pane).stdout,
                             "Attached Core client did not deliver UTF-8 input")
                    os.write(master, b"\x1b[200~compose_")
                    time.sleep(0.08)
                    os.write(master, "from_phone_é\x1b[201~\r".encode())
                    wait_for(lambda: "observed_compose_from_phone_é" in run(HERDR, "pane", "read", pane).stdout,
                             "Split Compose paste and Enter were not delivered")
                os.write(master, b"\x1b[<64;11;9M")
                if alternate:
                    wait_for(
                        lambda: "prior_alternate_response" in run(HC, "read", address).stdout,
                        "Wheel input did not reveal app-managed alternate history",
                    )
                else:
                    wait_for(
                        lambda: next(p["scroll"]["offset_from_bottom"] for p in panes() if p["pane_id"] == pane) > 0,
                        "A phone wheel packet did not scroll the source pane",
                    )
                os.write(master, b"\x1c")  # Ctrl+\\ detaches the Core client.
                assert attached.wait(timeout=5) == 0
            finally:
                if attached.poll() is None:
                    attached.terminate()
                    attached.wait(timeout=5)
        finally:
            os.close(slave)
            os.close(master)

    run(HERDR, "plugin", "link", str(PLUGIN))
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 90, 0, 0))
    client = subprocess.Popen(
        [HERDR, "session", "attach", session],
        stdin=slave, stdout=slave, stderr=slave, cwd=root, env=env, start_new_session=True,
    )
    os.close(slave)

    def drain():
        try:
            while os.read(master, 65536):
                pass
        except OSError:
            pass

    reader = Thread(target=drain, daemon=True)
    reader.start()
    try:
        pane = wait_for(panes, "No TUI pane")[0]["pane_id"]
        plugins = json.loads(run(HERDR, "plugin", "list", "--json").stdout)["result"]["plugins"]
        assert plugins[0]["enabled"] and not plugins[0].get("warnings"), plugins[0].get("warnings")
        def startup_ran():
            response = run(HERDR, "plugin", "log", "list", "--plugin", "herdr-mobile-bridge")
            return any(log.get("event") == "startup" and log["status"] == "succeeded"
                       for log in json.loads(response.stdout)["result"]["logs"])

        wait_for(startup_ran, "Plugin startup hook did not run")
        print("Herdr ran the plugin startup hook automatically.")

        run(HERDR, "plugin", "disable", "herdr-mobile-bridge")
        start_probe(pane, "original")
        report(pane, "working", "existing")
        run(HC, "server", "start")
        assert not mirrors()
        run(HERDR, "plugin", "enable", "herdr-mobile-bridge")
        run(HERDR, "plugin", "action", "invoke", "sync", "--plugin", "herdr-mobile-bridge")
        existing = wait_for(lambda: status("existing", "working"), "Existing agent failed to sync")
        print("Existing agent appeared in the Core API.")
        assert (existing["cols"], existing["rows"]) == (42, 30)
        wait_for(lambda: "prior_response_000" in run(HC, "read", "--lines", "500", existing["address"]).stdout,
                 "Preexisting source scrollback was not imported into Core")
        run(HERDR, "pane", "send-text", pane, "wide")
        run(HERDR, "pane", "send-keys", pane, "Enter")
        wait_for(lambda: "RIGHT_EDGE_KEPT" in run(HC, "read", existing["address"]).stdout,
                 "Phone-sized relay clipped the right edge of the response")
        print("Core imported preexisting history and showed the end of a wide response at phone width.")

        run(HERDR, "pane", "split", pane, "--direction", "right", "--no-focus")
        other = next(p["pane_id"] for p in panes() if p["pane_id"] != pane)
        start_probe(other, "secondary")
        report(other, "working", "new-agent")
        wait_for(lambda: status("new-agent", "working"), "New agent did not sync automatically")
        report(other, "blocked", "new-agent")
        wait_for(lambda: status("new-agent", "blocked"), "Blocked state did not reach Core")
        assert len(mirrors()) == 2
        print("New agent and blocked status synced without another action or duplicate entry.")

        run(HERDR, "pane", "send-text", pane, "from_tui")
        run(HERDR, "pane", "send-keys", pane, "Enter")
        wait_for(lambda: "observed_from_tui" in run(HC, "read", existing["address"]).stdout,
                 "Live screen did not reach Core")
        run(HC, "send", existing["address"], "from_core")
        wait_for(lambda: "observed_from_core" in run(HERDR, "pane", "read", pane).stdout,
                 "Core input did not reach TUI")
        attach_and_type(existing["address"], pane)
        print("A Core client scrolled the source and delivered UTF-8 keys and split Compose paste.")

        # Hold a separate controller on the second pane and check that the
        # relayed input cannot displace it. The bridge does not replay keys
        # that arrived during the conflict.
        terminal = next(p["terminal_id"] for p in panes() if p["pane_id"] == other)
        rival = subprocess.Popen(
            [HERDR, "terminal", "session", "control", terminal, "--cols", "60", "--rows", "20"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, cwd=root, env=env,
        )
        try:
            assert select.select([rival.stdout], [], [], 5)[0], "Second controller not ready"
            assert json.loads(rival.stdout.readline())["type"] == "terminal.frame"
            report(other, "working", "new-agent")
            other_core = wait_for(lambda: status("new-agent", "working"), "Second agent not working")
            run(HC, "send", other_core["address"], "radio_conflict")
            rival.stdin.write('{"type":"terminal.input","text":"from_rival\\r"}\n')
            rival.stdin.flush()
            wait_for(lambda: "observed_from_rival" in run(HERDR, "pane", "read", other).stdout,
                     "The competing controller lost input ownership")
        finally:
            rival.terminate()
            rival.wait(timeout=5)
        run(HC, "send", other_core["address"], "after_rival")
        text = wait_for(
            lambda: (output if "observed_after_rival" in
                     (output := run(HERDR, "pane", "read", other).stdout) else None),
            "Bridge failed to recover after controller released",
        )
        assert "observed_radio_conflict" not in text, "Conflicting keys were applied or replayed"
        print("An existing controller kept ownership and conflicting input was not replayed.")

        run(HERDR, "pane", "close", other)
        wait_for(lambda: len(mirrors()) == 1, "Closed pane still advertised")
        run(HERDR, "pane", "split", pane, "--direction", "right", "--no-focus")
        alternate = next(p["pane_id"] for p in panes() if p["pane_id"] != pane)
        start_probe(alternate, "alternate")
        report(alternate, "working", "alternate")
        alt_core = wait_for(lambda: status("alternate", "working"), "Alternate agent not published")
        attach_and_type(alt_core["address"], alternate, alternate=True)
        print("Wheel input exposed app-managed alternate-screen history at the correct coordinates.")
        run(HERDR, "pane", "close", alternate)
        wait_for(lambda: len(mirrors()) == 1, "Closed alternate pane still advertised")
        run(HERDR, "pane", "send-text", pane, "retire")
        run(HERDR, "pane", "send-keys", pane, "Enter")
        wait_for(lambda: not mirrors(), "Retired agent still advertised")
        assert any(p["pane_id"] == pane for p in panes())
        start_probe(pane, "reused")
        report(pane, "working", "existing")
        replacement = wait_for(lambda: status("existing", "working"), "New agent in reused pane not published")
        assert replacement["address"] != existing["address"], "Old Core terminal address was reused"
        print("Reusing a TUI pane created a fresh Core terminal address.")

        run(HERDR, "plugin", "disable", "herdr-mobile-bridge")
        wait_for(lambda: not mirrors(), "Disabled plugin still advertising")
        assert any(p["pane_id"] == pane for p in panes())
        print("Pane close and plugin disable removed mirrors while preserving the original pane.")
    finally:
        try:
            run(HERDR, "server", "stop", check=False)
            run(HC, "server", "stop", check=False)
        finally:
            if client.poll() is None:
                client.terminate()
                client.wait(timeout=6)
            os.close(master)
            reader.join(timeout=1)


if __name__ == "__main__":
    if not HERDR or not HC or not (PLUGIN / "target/release/herdr-mobile-bridge").is_file():
        raise SystemExit("Build the plugin in release mode and put herdr and hc on PATH.")
    for session in ("default", "mobile-test"):
        print(f"Testing Herdr session {session}")
        with tempfile.TemporaryDirectory(prefix=".mb-", dir=PLUGIN.parents[1]) as directory:
            smoke(Path(directory), session)
