#!/usr/bin/env python3
"""Calendar popup for the bar's clock: click the clock to open it; click
anywhere outside it, click the clock again or press Escape to close it. Same
dark blurred glass as the notification panel. With the bar on top it opens
under the clock; with the bar on the left it opens next to it, at the same
distance from the bar as the volume popup (popup_common.GAP).

Like swaync's panel, the window is an invisible layer over the whole screen
with the calendar panel inside it: a click outside the panel lands on that
invisible part, which closes the popup.

Needs python-gobject and gtk4-layer-shell (Install.sh installs both).
"""

import os
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import popup_common as common  # noqa: E402

common.preload_layer_shell()

PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "vk-calendar.pid")

# Toggle: when a calendar is already open, close it and stop here. The pid is
# only used when it's really this script (a stale file after a crash could
# name another program by now).
try:
    with open(PIDFILE) as f:
        pid = int(f.read().strip())
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        running = b"calendar.py" in f.read()
    if running and pid != os.getpid():
        os.kill(pid, signal.SIGTERM)
        sys.exit(0)
except (OSError, ValueError):
    pass
with open(PIDFILE, "w") as f:
    f.write(str(os.getpid()))

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

CSS = """
.panel {
    padding: 10px 12px 12px 12px;
}

calendar {
    background: transparent;
    border: none;
    color: #d3d6de;
}

calendar > header {
    background: transparent;
    border: none;
    padding-bottom: 6px;
}

calendar > header > button {
    background: transparent;
    border: none;
    box-shadow: none;
    color: #d3d6de;
    border-radius: 999px;
    min-width: 26px;
    min-height: 26px;
}

calendar > header > button:hover {
    background: alpha(#ffffff, 0.08);
}

calendar > header label {
    font-weight: 700;
}

calendar > grid > label.day-name {
    color: alpha(#d3d6de, 0.55);
    font-size: 11px;
    font-weight: 700;
}

calendar > grid > label.week-number {
    color: alpha(#d3d6de, 0.35);
    font-size: 11px;
}

calendar > grid > label.day-number {
    border-radius: 999px;
    min-width: 28px;
    min-height: 28px;
}

calendar > grid > label.day-number:hover {
    background: alpha(#ffffff, 0.08);
}

calendar > grid > label.day-number.other-month {
    color: alpha(#d3d6de, 0.28);
}

calendar > grid > label.day-number:selected {
    background: alpha(#ffffff, 0.12);
    color: #d3d6de;
}

calendar > grid > label.day-number.today {
    background: @color5;
    color: #05060a;
    font-weight: 700;
}
"""


def on_activate(app):
    position = common.bar_position()
    win = Gtk.ApplicationWindow(application=app)
    win.add_css_class("vk-popup")

    LayerShell.init_for_window(win)
    # vk-calendar-top / vk-calendar-left: Hyprland picks the slide-in/out
    # direction by name (hypr/hyprland/rules.lua)
    LayerShell.set_namespace(win, f"vk-calendar-{position}")
    LayerShell.set_layer(win, LayerShell.Layer.TOP)
    LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.ON_DEMAND)
    LayerShell.set_monitor(win, common.focused_monitor(Gdk))
    # cover the whole screen, the bar included (exclusive zone -1), so the
    # panel's position counts from the screen edge, like the volume popup's
    LayerShell.set_exclusive_zone(win, -1)
    for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
        LayerShell.set_anchor(win, edge, True)

    panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    panel.add_css_class("panel")
    # centered along the bar, where the clock sits (the bar's center module)
    if position == "left":
        panel.set_halign(Gtk.Align.START)
        panel.set_valign(Gtk.Align.CENTER)
        panel.set_margin_start(common.offset(position))
    else:
        panel.set_halign(Gtk.Align.CENTER)
        panel.set_valign(Gtk.Align.START)
        panel.set_margin_top(common.offset(position))

    calendar = Gtk.Calendar()
    calendar.set_show_week_numbers(True)
    panel.append(calendar)
    win.set_child(panel)

    # a click outside the panel (on the invisible rest of the window) closes it
    def on_click(_gesture, _n_press, x, y):
        widget = win.pick(x, y, Gtk.PickFlags.DEFAULT)
        while widget is not None and widget is not panel:
            widget = widget.get_parent()
        if widget is None:
            app.quit()

    click = Gtk.GestureClick()
    click.set_button(0)  # any mouse button
    click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
    click.connect("pressed", on_click)
    win.add_controller(click)

    keys = Gtk.EventControllerKey()
    keys.connect("key-pressed", lambda _c, keyval, _code, _state: keyval == Gdk.KEY_Escape and app.quit())
    win.add_controller(keys)

    common.load_css(Gtk, Gdk, CSS)
    win.present()


def cleanup(*_):
    try:
        os.remove(PIDFILE)
    except OSError:
        pass


# NON_UNIQUE: no D-Bus single-instance handling, the pid file does the toggling
app = Gtk.Application(application_id="org.vknxworks.calendar", flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", on_activate)
# closed by a second click (SIGTERM) or Escape: remove the pid file either way
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (cleanup(), app.quit(), False)[2])
app.connect("shutdown", cleanup)
app.run(None)
