#!/usr/bin/env python3
"""Volume / microphone / Caps Lock popup (replaces SwayOSD), in the same
glass as the bar's other popups. hypr/scripts/osd.sh changes the level and
then calls this:
    osd.py volume <0-100> <muted 0|1>
    osd.py mic <muted 0|1>
    osd.py brightness <0-100>
    osd.py caps <on 0|1>

The first call starts the popup; it keeps running and later calls only send
it the new value (over a socket), so holding a key updates one popup instead
of opening new ones. It shows on the focused monitor, at the same distance
from the bar as the calendar (popup_common.GAP), and hides itself after a
moment. With a side bar (left or right) it shows at the bottom of the screen.

Needs python-gobject and gtk4-layer-shell (Install.sh installs both).
"""

import json
import os
import socket
import sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "vk-osd.sock")
MESSAGE = json.dumps(sys.argv[1:]).encode()
HIDE_AFTER_MS = 1200


def send():
    """Hand the value to the running popup. False when none is running."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
        try:
            s.sendto(MESSAGE, SOCK)
            return True
        except (FileNotFoundError, ConnectionRefusedError):
            return False


if len(sys.argv) < 3:
    sys.exit("usage: osd.py volume <0-100> <muted 0|1> | mic <muted 0|1> | brightness <0-100> | caps <on 0|1>")
if send():
    sys.exit(0)

# No popup running: become it
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import popup_common as common  # noqa: E402

common.preload_layer_shell()

# take over the socket (a leftover file from a crash is replaced)
server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    os.unlink(SOCK)
except FileNotFoundError:
    pass
try:
    server.bind(SOCK)
except OSError:
    # another key press started a popup at the same moment: use that one
    sys.exit(0 if send() else 1)

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

CSS = """
.panel {
    padding: 8px 14px 8px 12px;
    border-radius: 999px;
}

.osd-icon {
    font-size: 18px;
}

.osd-value {
    font-size: 12px;
    font-weight: 600;
}

progressbar {
    min-width: 100px;
}

progressbar > trough {
    min-height: 4px;
    border: none;
    border-radius: 999px;
    background: alpha(#ffffff, 0.14);
}

progressbar > trough > progress {
    min-height: 4px;
    border: none;
    border-radius: 999px;
    background: @color5;
}

.muted .osd-icon,
.muted .osd-value {
    color: alpha(#d3d6de, 0.45);
}

.muted progressbar > trough > progress {
    background: alpha(#d3d6de, 0.35);
}
"""

VOLUME_ICONS = ["󰕿", "󰖀", "󰕾"]  # low, medium, high
MUTED_ICON = "󰝟"
MIC_ICONS = {False: "󰍬", True: "󰍭"}
BRIGHTNESS_ICONS = ["󰃞", "󰃟", "󰃠"]  # low, medium, high
CAPS_ICON = "󰘲"


class Osd:
    def __init__(self, app):
        self.app = app
        self.hide_timer = 0
        self.monitor = None

        self.win = Gtk.ApplicationWindow(application=app)
        self.win.add_css_class("vk-popup")
        LayerShell.init_for_window(self.win)
        LayerShell.set_namespace(self.win, "vk-osd")
        LayerShell.set_layer(self.win, LayerShell.Layer.OVERLAY)
        LayerShell.set_keyboard_mode(self.win, LayerShell.KeyboardMode.NONE)
        # position counts from the screen edge, the bar's space included
        LayerShell.set_exclusive_zone(self.win, -1)

        self.panel = Gtk.Box(spacing=10)
        self.panel.add_css_class("panel")
        self.icon = Gtk.Label()
        self.icon.add_css_class("osd-icon")
        self.bar = Gtk.ProgressBar()
        self.bar.set_valign(Gtk.Align.CENTER)
        self.value = Gtk.Label()
        self.value.add_css_class("osd-value")
        self.value.set_width_chars(4)
        self.value.set_xalign(1)
        for widget in (self.icon, self.bar, self.value):
            self.panel.append(widget)
        self.win.set_child(self.panel)
        common.load_css(Gtk, Gdk, CSS)

        channel = GLib.IOChannel.unix_new(server.fileno())
        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN, self.on_message)
        self.show(sys.argv[1:])

    def on_message(self, *_):
        try:
            self.show(json.loads(server.recv(256)))
        except (OSError, ValueError):
            pass
        return True

    def show(self, args):
        kind, values = args[0], args[1:]
        muted = False
        if kind == "volume":
            level = max(0, min(100, int(values[0])))
            muted = values[1] == "1"
            icon = MUTED_ICON if muted or level == 0 else VOLUME_ICONS[min(2, level // 34)]
            self.set(icon, level, f"{level}%", muted)
        elif kind == "mic":
            muted = values[0] == "1"
            self.set(MIC_ICONS[muted], None, "Off" if muted else "On", muted)
        elif kind == "brightness":
            level = max(0, min(100, int(values[0])))
            self.set(BRIGHTNESS_ICONS[min(2, level // 34)], level, f"{level}%", False)
        elif kind == "caps":
            on = values[0] == "1"
            self.set(CAPS_ICON, None, "On" if on else "Off", not on)
        else:
            return

        # the focused monitor; moving a popup to another monitor means
        # hiding it first
        monitor = common.focused_monitor(Gdk)
        if monitor != self.monitor:
            self.win.set_visible(False)
            LayerShell.set_monitor(self.win, monitor)
            self.monitor = monitor
        self.place(monitor)
        self.win.present()

        if self.hide_timer:
            GLib.source_remove(self.hide_timer)
        self.hide_timer = GLib.timeout_add(HIDE_AFTER_MS, self.hide)

    def set(self, icon, level, text, muted):
        self.icon.set_label(icon)
        self.bar.set_visible(level is not None)
        if level is not None:
            self.bar.set_fraction(level / 100)
        self.value.set_label(text)
        if muted:
            self.panel.add_css_class("muted")
        else:
            self.panel.remove_css_class("muted")

    def place(self, monitor):
        """Top bar: centered under it. Side bar: at the bottom of the screen."""
        top = common.bar_position(monitor.get_connector()) == "top"
        LayerShell.set_anchor(self.win, LayerShell.Edge.TOP, top)
        LayerShell.set_anchor(self.win, LayerShell.Edge.BOTTOM, not top)
        LayerShell.set_margin(self.win, LayerShell.Edge.TOP, common.offset("top") if top else 0)
        LayerShell.set_margin(self.win, LayerShell.Edge.BOTTOM, 0 if top else 40)

    def hide(self):
        self.hide_timer = 0
        self.win.set_visible(False)
        return False


def on_activate(app):
    app.hold()  # keep running while hidden
    app.osd = Osd(app)


app = Gtk.Application(application_id="org.vknxworks.osd", flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", on_activate)
app.run(None)
