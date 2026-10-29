#!/usr/bin/env python3
"""Music popup for the bar's music island: click the track title (or the
visualizer) to open it; click outside it, click the island again or press
Escape to close it. Same glass as the calendar and the notification panel.

Shows the cover, title, artist and album, a progress bar you can drag to
seek, and previous / play-pause / next. It opens under the music island
(next to it with the bar on the left), at the same distance from the bar as
the other popups (popup_common.GAP).

The track info comes from playerctl, run as its own process every half
second (libplayerctl crashed waybar before, see CHANGELOG 2026-10-29).

Needs python-gobject and gtk4-layer-shell (Install.sh installs both).
"""

import hashlib
import os
import signal
import subprocess
import sys
import threading
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import popup_common as common  # noqa: E402

common.preload_layer_shell()
PIDFILE = common.toggle_open("music")

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402
from gi.repository import Gtk4LayerShell as LayerShell  # noqa: E402

PANEL_WIDTH = 340
ART_SIZE = 72
ART_CACHE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "vk-music-art")
FIELDS = ["status", "title", "artist", "album", "mpris:artUrl", "position", "mpris:length"]

CSS = """
.panel {
    padding: 14px;
}

.art {
    border-radius: 14px;
    background: alpha(#ffffff, 0.06);
}

.art-placeholder {
    font-size: 28px;
    color: alpha(#d3d6de, 0.35);
}

.title {
    font-size: 14px;
    font-weight: 700;
}

.artist {
    color: alpha(#d3d6de, 0.65);
}

.album {
    font-size: 11px;
    color: alpha(#d3d6de, 0.4);
}

.time {
    font-size: 11px;
    color: alpha(#d3d6de, 0.55);
}

scale {
    padding: 4px 0;
}

scale > trough {
    min-height: 4px;
    border: none;
    border-radius: 999px;
    background: alpha(#ffffff, 0.14);
}

scale > trough > highlight {
    border: none;
    border-radius: 999px;
    background: @color5;
}

scale > trough > slider {
    min-width: 12px;
    min-height: 12px;
    margin: -5px;
    border: none;
    border-radius: 999px;
    background: #d3d6de;
    box-shadow: none;
}

.controls button {
    background: transparent;
    border: none;
    box-shadow: none;
    border-radius: 999px;
    min-width: 38px;
    min-height: 38px;
    padding: 0;
    color: #d3d6de;
    font-size: 18px;
}

.controls button:hover {
    background: alpha(#ffffff, 0.08);
}

.controls button.play {
    background: @color5;
    color: #05060a;
}
"""


def playerctl(*args):
    try:
        return subprocess.run(["playerctl", *args], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def read_track():
    """Current track as a dict, or None when no player is running."""
    out = playerctl("metadata", "--format", "\t".join("{{%s}}" % f for f in FIELDS))
    parts = out.rstrip("\n").split("\t")
    if len(parts) != len(FIELDS):
        return None
    track = dict(zip(FIELDS, parts))
    for key in ("position", "mpris:length"):
        try:
            track[key] = int(float(track[key] or 0)) / 1_000_000  # µs -> s
        except ValueError:
            track[key] = 0
    return track


def mmss(seconds):
    seconds = int(max(0, seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


class MusicPopup:
    def __init__(self, app):
        self.app = app
        self.position_bar = common.bar_position()
        self.art_url = None
        self.length = 0
        self.updating = False

        win = self.win = Gtk.ApplicationWindow(application=app)
        win.add_css_class("vk-popup")
        LayerShell.init_for_window(win)
        # vk-music-top / vk-music-left: Hyprland picks the slide-in/out
        # direction by name (hypr/hyprland/rules.lua)
        LayerShell.set_namespace(win, f"vk-music-{self.position_bar}")
        LayerShell.set_layer(win, LayerShell.Layer.TOP)
        LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.ON_DEMAND)
        monitor = common.focused_monitor(Gdk)
        LayerShell.set_monitor(win, monitor)
        # an invisible layer over the whole screen with the panel inside it:
        # a click outside the panel closes the popup
        LayerShell.set_exclusive_zone(win, -1)
        for edge in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM, LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(win, edge, True)

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.panel.add_css_class("panel")
        self.panel.set_size_request(PANEL_WIDTH, -1)
        self.place(monitor)
        self.build()
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
        self.refresh()
        GLib.timeout_add(500, self.refresh)
        win.present()

    def place(self, monitor):
        """Under the music island, where it was clicked (centered on the mouse,
        kept on the screen); next to it with the bar on the left."""
        geo = monitor.get_geometry()
        cursor = common.cursor_position()
        if self.position_bar == "left":
            self.panel.set_halign(Gtk.Align.START)
            self.panel.set_valign(Gtk.Align.START)
            self.panel.set_margin_start(common.offset("left"))
            y = (cursor[1] - geo.y) if cursor else geo.height // 4
            self.panel.set_margin_top(max(10, min(geo.height - 220, y - 60)))
        else:
            self.panel.set_halign(Gtk.Align.START)
            self.panel.set_valign(Gtk.Align.START)
            self.panel.set_margin_top(common.offset("top"))
            x = (cursor[0] - geo.x) if cursor else geo.width // 4
            self.panel.set_margin_start(max(10, min(geo.width - PANEL_WIDTH - 10, x - PANEL_WIDTH // 2)))

    def build(self):
        # cover + text
        top = Gtk.Box(spacing=12)
        self.art = Gtk.Picture()
        self.art.set_content_fit(Gtk.ContentFit.COVER)
        self.art.set_size_request(ART_SIZE, ART_SIZE)
        self.art_placeholder = Gtk.Label(label="󰝚")
        self.art_placeholder.add_css_class("art-placeholder")
        art_box = Gtk.Overlay()
        art_box.add_css_class("art")
        art_box.set_overflow(Gtk.Overflow.HIDDEN)
        art_box.set_size_request(ART_SIZE, ART_SIZE)
        art_box.set_valign(Gtk.Align.CENTER)
        art_box.set_child(self.art_placeholder)
        art_box.add_overlay(self.art)
        top.append(art_box)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)
        self.title = Gtk.Label(xalign=0)
        self.artist = Gtk.Label(xalign=0)
        self.album = Gtk.Label(xalign=0)
        for label, css in ((self.title, "title"), (self.artist, "artist"), (self.album, "album")):
            label.add_css_class(css)
            label.set_ellipsize(Pango.EllipsizeMode.END)
            label.set_max_width_chars(1)  # ellipsize to the panel's width
            label.set_hexpand(True)
            text.append(label)
        top.append(text)
        self.panel.append(top)

        # progress: drag to seek
        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 1)
        self.scale.set_draw_value(False)
        self.scale.connect("change-value", self.on_seek)
        self.panel.append(self.scale)
        times = Gtk.Box()
        self.elapsed = Gtk.Label(xalign=0)
        self.total = Gtk.Label(xalign=1)
        self.total.set_hexpand(True)
        for label in (self.elapsed, self.total):
            label.add_css_class("time")
            times.append(label)
        self.panel.append(times)

        # controls
        controls = Gtk.Box(spacing=14)
        controls.add_css_class("controls")
        controls.set_halign(Gtk.Align.CENTER)
        self.play = None
        for icon, command, css in (("󰒮", "previous", None), ("󰐊", "play-pause", "play"), ("󰒭", "next", None)):
            button = Gtk.Button(label=icon)
            if css:
                button.add_css_class(css)
                self.play = button
            button.connect("clicked", lambda _b, c=command: (playerctl(c), self.refresh()))
            controls.append(button)
        self.panel.append(controls)

    def refresh(self):
        track = read_track()
        if track is None:
            self.title.set_label("Nothing playing")
            for label in (self.artist, self.album, self.elapsed, self.total):
                label.set_label("")
            self.scale.set_sensitive(False)
            return True

        self.title.set_label(track["title"] or "Unknown title")
        self.artist.set_label(track["artist"])
        self.album.set_label(track["album"])
        self.album.set_visible(bool(track["album"]))
        self.play.set_label("󰏤" if track["status"] == "Playing" else "󰐊")

        self.length = track["mpris:length"]
        self.scale.set_sensitive(self.length > 0)
        self.updating = True
        self.scale.set_range(0, max(1, self.length))
        self.scale.set_value(min(track["position"], self.length))
        self.updating = False
        self.elapsed.set_label(mmss(track["position"]))
        self.total.set_label(mmss(self.length) if self.length else "")

        if track["mpris:artUrl"] != self.art_url:
            self.art_url = track["mpris:artUrl"]
            self.load_art(self.art_url)
        return True

    def on_seek(self, _scale, _scroll, value):
        if not self.updating and self.length:
            playerctl("position", f"{max(0, min(value, self.length)):.1f}")
        return False

    def load_art(self, url):
        """Show the cover: a local file directly, a web address downloaded once
        into a cache (in a thread, so the popup doesn't wait for it)."""
        if not url:
            self.art.set_paintable(None)
            return
        if url.startswith("file://"):
            self.art.set_file(Gio.File.new_for_uri(url))
            return
        if not url.startswith(("http://", "https://")):
            self.art.set_paintable(None)
            return
        os.makedirs(ART_CACHE, exist_ok=True)
        path = os.path.join(ART_CACHE, hashlib.sha1(url.encode()).hexdigest())

        def fetch():
            if not os.path.exists(path):
                try:
                    with urllib.request.urlopen(url, timeout=5) as response, open(path + ".part", "wb") as f:
                        f.write(response.read(10_000_000))
                    os.replace(path + ".part", path)
                except OSError:
                    return
            # still the current track's cover?
            GLib.idle_add(lambda: url == self.art_url and self.art.set_filename(path))

        threading.Thread(target=fetch, daemon=True).start()

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
    app.popup = MusicPopup(app)


app = Gtk.Application(application_id="org.vknxworks.music", flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", on_activate)
# closed by a second click (SIGTERM) or Escape: remove the pid file either way
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (cleanup(), app.quit(), False)[2])
app.connect("shutdown", cleanup)
app.run(None)
