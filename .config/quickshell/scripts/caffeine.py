#!/usr/bin/env python3
"""Own one logind idle inhibitor until stdin closes or this process exits.

Hypridle honours logind idle inhibitors by default. No daemon is stopped and no
manual lock, suspend, lid-switch or shutdown operation is inhibited.
"""
import json
import os
import sys


def acquire(Gio, GLib):
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    reply, descriptors = bus.call_with_unix_fd_list_sync(
        "org.freedesktop.login1", "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager", "Inhibit",
        GLib.Variant("(ssss)", ("idle", "Quickshell", "Caffeine mode", "block")),
        GLib.VariantType.new("(h)"), Gio.DBusCallFlags.NONE, 5000, None, None)
    return descriptors.get(reply.unpack()[0])


def serve(acquire_fd=None):
    descriptor = None
    try:
        if acquire_fd is None:
            from gi.repository import Gio, GLib
            descriptor = acquire(Gio, GLib)
        else:
            descriptor = acquire_fd()
        print(json.dumps({"enabled": True}), flush=True)
        # The private pipe is owned by Quickshell. EOF also releases the lock.
        for _ in sys.stdin:
            pass
        return 0
    except Exception:
        print(json.dumps({"enabled": False, "error": "Could not enable caffeine mode."}), flush=True)
        return 1
    finally:
        if descriptor is not None:
            os.close(descriptor)


if __name__ == "__main__":
    raise SystemExit(serve())
