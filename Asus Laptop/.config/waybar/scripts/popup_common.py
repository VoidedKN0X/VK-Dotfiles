"""Shared by the bar's popups (calendar.py and osd.py): where they sit next
to the bar, which monitor they open on, and their glass look.

Both popups are placed in pixels from the screen edge, so they line up on
every monitor (also the rotated, taller DP-2).
"""

import json
import os
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/waybar")


# Space between the bar and the popups (calendar, volume popup), in px.
# One number for both, so they always line up.
GAP = 14

LAYER_SHELL_LIB = "/usr/lib/libgtk4-layer-shell.so"


def preload_layer_shell():
    """gtk4-layer-shell has to be loaded before GTK connects to Wayland, which
    for Python means preloading it: start the script again with it preloaded.
    Call before importing gi."""
    if "libgtk4-layer-shell" not in os.environ.get("LD_PRELOAD", "") and os.path.exists(LAYER_SHELL_LIB):
        os.environ["LD_PRELOAD"] = f"{LAYER_SHELL_LIB} {os.environ.get('LD_PRELOAD', '')}".strip()
        os.execv(sys.executable, [sys.executable] + sys.argv)


def _read_jsonc(path):
    import re
    with open(path) as f:
        return json.loads(re.sub(r"^\s*//.*$", "", f.read(), flags=re.M))


def focused_monitor_name():
    """Name of the monitor Hyprland has focused (e.g. DP-1), or None."""
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2).stdout
        return next(m["name"] for m in json.loads(out) if m.get("focused"))
    except (OSError, ValueError, StopIteration, subprocess.SubprocessError):
        return None


def bar_position(monitor=None):
    """Edge of the bar on a monitor (default: the focused one): 'top', 'left'
    or 'right'. waybar/config.jsonc can give monitors their own bar (on the
    desktop DP-2 always has one on the right); otherwise the bar follows
    layouts/current.jsonc (top or left, switched with Super + B)."""
    layout = "current"
    try:
        config = _read_jsonc(os.path.join(CONFIG, "config.jsonc"))
        if isinstance(config, list):
            monitor = monitor or focused_monitor_name()
            for bar in config:
                outputs = bar.get("output", [])
                outputs = [outputs] if isinstance(outputs, str) else outputs
                if monitor in outputs:
                    includes = bar.get("include", [])
                    includes = [includes] if isinstance(includes, str) else includes
                    layout = next((os.path.basename(i)[:-6] for i in includes if "/layouts/" in i), layout)
                    break
    except (OSError, ValueError, AttributeError):
        pass
    if layout in ("top", "left", "right"):
        return layout
    try:
        with open(os.path.join(CONFIG, "layouts", "current.jsonc")) as f:
            return "left" if "left.jsonc" in f.read() else "top"
    except OSError:
        return "top"


def bar_edge(position):
    """Where the bar ends, in px from the screen edge: margin + height (top)
    or margin + width (left, right), read from waybar/layouts/<position>.jsonc,
    so every profile's own bar size is used."""
    try:
        layout = _read_jsonc(os.path.join(CONFIG, "layouts", f"{position}.jsonc"))
    except (OSError, ValueError):
        layout = {}
    if position in ("left", "right"):
        return layout.get(f"margin-{position}", 8) + layout.get("width", 40)
    return layout.get("margin-top", 8) + layout.get("height", 30)


def offset(position=None):
    """Distance from the bar's screen edge to a popup's near edge, in px."""
    position = position or bar_position()
    return bar_edge(position) + GAP


def focused_monitor(Gdk):
    """The Gdk monitor Hyprland has focused (where the click or key press
    happened), or the first monitor."""
    monitors = Gdk.Display.get_default().get_monitors()
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2).stdout
        name = next(m["name"] for m in json.loads(out) if m.get("focused"))
        for i in range(monitors.get_n_items()):
            if monitors.get_item(i).get_connector() == name:
                return monitors.get_item(i)
    except (OSError, ValueError, StopIteration, subprocess.SubprocessError):
        pass
    return monitors.get_item(0)


# Same glass as the notification panel (swaync/style.css); @color5 is
# wallust's accent. backdrop-filter marks the panel for blur: on Hyprland 0.56
# a GTK4 app tells the compositor which areas to blur, and Hyprland blurs them
# with its own settings (the value here is ignored).
GLASS_CSS = """
@import url("file://%s");

window.vk-popup {
    background: transparent;
}

.panel {
    background: alpha(#15171d, 0.58);
    border: 1px solid alpha(#ffffff, 0.11);
    border-radius: 20px;
    box-shadow: inset 0 1px alpha(#ffffff, 0.07);
    backdrop-filter: blur(20px);
    color: #d3d6de;
    font-family: "Ubuntu", "Symbols Nerd Font";
    font-size: 13px;
}
""" % os.path.join(CONFIG, "colors", "colors.css")


def load_css(Gtk, Gdk, css):
    provider = Gtk.CssProvider()
    provider.load_from_string(GLASS_CSS + css)
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)


def toggle_open(name):
    """For popups opened by clicking the bar: when this popup is already
    open, close it (the second click) and exit; otherwise record this one.
    Returns the pid file to remove when the popup closes."""
    import signal
    pidfile = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), f"vk-{name}.pid")
    script = os.path.basename(sys.argv[0]).encode()
    try:
        with open(pidfile) as f:
            pid = int(f.read().strip())
        # only when the pid is really this script (a stale file after a
        # crash could name another program by now)
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            running = script in f.read()
        if running and pid != os.getpid():
            os.kill(pid, signal.SIGTERM)
            sys.exit(0)
    except (OSError, ValueError):
        pass
    with open(pidfile, "w") as f:
        f.write(str(os.getpid()))
    return pidfile


def cursor_position():
    """Mouse position in Hyprland's layout coordinates, or None."""
    try:
        out = subprocess.run(["hyprctl", "cursorpos", "-j"], capture_output=True, text=True, timeout=2).stdout
        pos = json.loads(out)
        return pos["x"], pos["y"]
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return None


if __name__ == "__main__":
    # for shell scripts (notifications.sh): the bar's edge on the focused monitor
    print(bar_position())
