#!/usr/bin/env python3
"""Live Helium popup regression using a temporary profile and local HTML only.

Briefly opens two test windows. No personal profile, website, login, clipboard,
wallpaper or device settings are changed. Only the launched browser is stopped.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def clients():
    return json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], text=True))


def verify(browser):
    original = json.loads(subprocess.check_output(["hyprctl", "activewindow", "-j"], text=True)).get("address")
    with tempfile.TemporaryDirectory(prefix="hypr-popup-test-", ignore_cleanup_errors=True) as tmp:
        root = Path(tmp)
        page = root / "parent.html"
        page.write_text('''<!doctype html><title>Hyprland popup test parent</title>
<h1>Temporary popup test</h1><script>
setTimeout(() => {
    const popup = window.open('', 'hypr-test', 'popup,width=560,height=360');
    if (popup) setTimeout(() => {
        popup.document.write('<!doctype html><title>Hyprland popup test child</title><h1>Temporary popup</h1>');
        popup.document.close();
    }, 500);
}, 1000);
</script>''')
        with (root / "browser.log").open("w") as log:
            process = subprocess.Popen([browser, "--user-data-dir=" + str(root / "profile"),
                "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
                "--disable-extensions", "--disable-sync", "--disable-popup-blocking", "--new-window", page.as_uri()],
                stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                rows = []
                while time.monotonic() < deadline:
                    rows = [row for row in clients() if row.get("pid") == process.pid
                            and row.get("title", "").startswith("Hyprland popup test")]
                    if len(rows) == 2:
                        break
                    if process.poll() is not None:
                        raise AssertionError("The temporary browser exited before mapping its fixture windows")
                    time.sleep(.1)
                assert len(rows) == 2, "The parent and popup did not both map"
                parent = next(row for row in rows if row["title"].startswith("Hyprland popup test parent"))
                child = next(row for row in rows if row["title"].startswith("Hyprland popup test child"))
                assert not parent["floating"], "Normal browser windows must stay tiled"
                assert child["floating"], f"Popup still tiled (initial title: {child['initialTitle']!r})"
                assert child["initialTitle"].startswith("about:blank"), child["initialTitle"]
                assert all(dimension > 0 for dimension in child["size"])
                print("PASS real browser: normal parent tiled; blank-initial popup floating after its title changes")
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                if original:
                    # Select only the recorded original window, if it still exists.
                    expression = 'local w = hl.get_window(' + json.dumps("address:" + original) + '); if w then hl.dispatch(hl.dsp.focus({window=w})) end'
                    subprocess.run(["hyprctl", "eval", expression], text=True, capture_output=True, timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", default="helium-browser", help="Chromium-family executable")
    args = parser.parse_args()
    if not shutil.which(args.browser) or not shutil.which("hyprctl"):
        parser.error("The browser and hyprctl must be installed; run in a live unlocked Hyprland session")
    verify(args.browser)


if __name__ == "__main__":
    main()
