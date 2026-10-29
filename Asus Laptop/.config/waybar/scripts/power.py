#!/usr/bin/env python3
"""Power menu for the bar's power button: lock, suspend, log out, restart and
shut down, in the same blurred glass as the bar's other popups. It opens next
to the power button (top right with the bar on top, bottom left / bottom
right with a side bar); click outside it, click the button again or press
Escape to close it.

Log out, restart and shut down ask for a second click: the first turns the
row red ("Click again to restart"), and after 3 seconds without that click it
goes back to normal.

Needs python-gobject and gtk4-layer-shell (Install.sh installs both).
"""

import os
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import popup_common as common  # noqa: E402

common.preload_layer_shell()
PIDFILE = common.toggle_open("power")

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

# label, icon, command, confirmation text (None: no second click needed)
ACTIONS = [
    # through hypridle's lock_cmd, so hyprlock never starts twice
    ("Lock", "󰌾", "loginctl lock-session", None),
    ("Suspend", "󰤄", "systemctl suspend", None),
    # same as Super + M
    ("Log out", "󰍃", "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'",
     "Click again to log out"),
    ("Restart", "󰜉", "systemctl reboot", "Click again to restart"),
    ("Shut down", "󰐥", "systemctl poweroff", "Click again to shut down"),
]
CONFIRM_TIMEOUT_MS = 3000

CSS = """
.panel {
    padding: 8px;
    min-width: 210px;
}

.action {
    background: transparent;
    border: none;
    box-shadow: none;
    border-radius: 14px;
    padding: 8px 12px;
    color: #d3d6de;
}

.action:hover,
.action:focus-visible {
    background: alpha(#ffffff, 0.08);
}

.action .icon {
    font-size: 17px;
    min-width: 22px;
}

.action .label {
    font-size: 13px;
    font-weight: 500;
}

/* shut down and restart: red icon */
.action.danger .icon {
    color: #e07a6c;
}

/* waiting for the second click */
.action.confirm {
    background: alpha(#e07a6c, 0.22);
}

.action.confirm .label {
    color: #f3b4aa;
    font-weight: 600;
}

.separator {
    min-height: 1px;
    background: alpha(#ffffff, 0.08);
    margin: 4px 10px;
}
"""


class PowerMenu:
    def __init__(self, app):
        self.app = app
        self.pending = None  # (button, timer id) waiting for its second click
        monitor = common.focused_monitor(Gdk)
        position = common.bar_position(monitor.get_connector())

        win = self.win = Gtk.ApplicationWindow(application=app)
        win.add_css_class("vk-popup")
        LayerShell.init_for_window(win)
        # vk-power-top / -left / -right: Hyprland picks the slide-in/out
        # direction by name (hypr/hyprland/rules.lua)
        LayerShell.set_namespace(win, f"vk-power-{position}")
        LayerShell.set_layer(win, LayerShell.Layer.TOP)
        LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.ON_DEMAND)
        LayerShell.set_monitor(win, monitor)
        # an invisible layer over the whole screen with the menu inside it: a
        # click outside the menu closes it
        LayerShell.set_exclusive_zone(win, -1)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(win, edge, True)

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.panel.add_css_class("panel")
        # next to the power button: the last island of the bar (top bar: its
        # right end; side bars: their bottom end). 10 px from the screen edge
        # along the bar, like the bar's own margins.
        edge = common.offset(position)
        if position == "top":
            self.panel.set_halign(Gtk.Align.END)
            self.panel.set_valign(Gtk.Align.START)
            self.panel.set_margin_top(edge)
            self.panel.set_margin_end(10)
        elif position == "left":
            self.panel.set_halign(Gtk.Align.START)
            self.panel.set_valign(Gtk.Align.END)
            self.panel.set_margin_start(edge)
            self.panel.set_margin_bottom(10)
        else:
            self.panel.set_halign(Gtk.Align.END)
            self.panel.set_valign(Gtk.Align.END)
            self.panel.set_margin_end(edge)
            self.panel.set_margin_bottom(10)

        for i, (label, icon, command, confirm) in enumerate(ACTIONS):
            if i == 2:  # lock + suspend, then the session-ending ones
                separator = Gtk.Box()
                separator.add_css_class("separator")
                self.panel.append(separator)
            self.panel.append(self.make_button(label, icon, command, confirm))
        win.set_child(self.panel)

        click = Gtk.GestureClick()
        click.set_button(0)
        click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        click.connect("pressed", self.on_click)
        win.add_controller(click)
        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", lambda _c, keyval, _code, _state: keyval == Gdk.KEY_Escape and app.quit())
        win.add_controller(keys)

        common.load_css(Gtk, Gdk, CSS)
        win.present()

    def make_button(self, label, icon, command, confirm):
        button = Gtk.Button()
        button.add_css_class("action")
        if confirm and label != "Log out":
            button.add_css_class("danger")
        row = Gtk.Box(spacing=12)
        icon_label = Gtk.Label(label=icon)
        icon_label.add_css_class("icon")
        text = Gtk.Label(label=label, xalign=0)
        text.add_css_class("label")
        row.append(icon_label)
        row.append(text)
        button.set_child(row)
        button.connect("clicked", self.on_action, text, label, command, confirm)
        return button

    def on_action(self, button, text, label, command, confirm):
        if confirm and (self.pending is None or self.pending[0] is not button):
            self.reset_pending()
            button.add_css_class("confirm")
            text.set_label(confirm)
            timer = GLib.timeout_add(CONFIRM_TIMEOUT_MS, self.confirm_timed_out)
            self.pending = (button, timer, text, label)
            return
        # close the menu first, so it isn't on screen (or in the lock screen's
        # screenshot) while the action runs
        self.win.set_visible(False)
        subprocess.Popen(["sh", "-c", command], start_new_session=True)
        self.app.quit()

    def confirm_timed_out(self):
        # the timer ends itself (returns False), so don't remove it again
        if self.pending:
            self.pending = (self.pending[0], 0, *self.pending[2:])
        self.reset_pending()
        return False

    def reset_pending(self):
        if self.pending:
            button, timer, text, label = self.pending
            button.remove_css_class("confirm")
            text.set_label(label)
            if timer:
                GLib.source_remove(timer)
            self.pending = None

    def on_click(self, _gesture, _n_press, x, y):
        widget = self.win.pick(x, y, Gtk.PickFlags.DEFAULT)
        while widget is not None and widget is not self.panel:
            widget = widget.get_parent()
        if widget is None:
            self.app.quit()


def cleanup(*_):
    try:
        os.remove(PIDFILE)
    except OSError:
        pass


def on_activate(app):
    app.menu = PowerMenu(app)


app = Gtk.Application(application_id="org.vknxworks.power", flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", on_activate)
# closed by a second click on the button (SIGTERM) or Escape
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (cleanup(), app.quit(), False)[2])
app.connect("shutdown", cleanup)
app.run(None)
