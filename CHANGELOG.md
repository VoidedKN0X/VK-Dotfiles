# Changelog

Changes to VK-Dotfiles, newest first.

## 2026-10-18

### Added
- **Thunar sidebar bookmarks** (all profiles: Desktop, Asus Laptop, Steam
  Deck). After copying the configs, `Install.sh` creates
  `~/.config/gtk-3.0/bookmarks` with Documents, Downloads, Music and
  Pictures, in that order, built from `$HOME` at install time
  (`file://$HOME/<Folder>`), so it works for any username; no bookmarks file
  is kept in the repo. Missing folders are created first. An existing
  bookmarks file is kept: only missing lines are added (also lines that
  carry a label count as present), so running the script twice gives the
  same result. Failures go through `warn()`. README updated. A search of
  the repo found no other hardcoded home paths or usernames (the TrueNAS
  share `192.168.1.9:/mnt/Data/axel` is a path on the server and stays).
- **Battery on the lock screen** (Asus Laptop and Steam Deck). hyprlock shows
  the battery icon and percentage in the bottom-left corner, in the same
  color and font as the date, updated every 30 seconds. New script
  `hypr/scripts/lock-battery.sh` reads `/sys/class/power_supply/BAT*`: the
  icon follows the charge in 10% steps (same Nerd Font icons as waybar), and
  shows the charging icon (󰂄) while charging or full. Without a battery it
  shows nothing.
- **Keyboard button in the Steam Deck's waybar.** A new `custom/keyboard`
  button (󰌌) at the right end of the bar shows or hides the on-screen
  keyboard (`osk-toggle.sh`). Tap it to close the keyboard, instead of
  swiping over the keys, which typed stray letters. README updated.
- **Tailscale on the Steam Deck.** `Install.sh` installs `tailscale`, enables
  `tailscaled.service` and makes your user the Tailscale operator
  (`tailscale set --operator=$USER`), so it can be controlled without sudo.
  `hypr/hyprland/execs.lua` starts Tailscale's own tray app
  (`tailscale systray`, beta, Tailscale 1.88+) at login: log in,
  connect/disconnect and pick an exit node from its icon in waybar. The
  firewall (ufw) allows everything that comes in over the tailnet
  (`allow in on tailscale0`) and UDP 41641, so devices can connect directly
  instead of through Tailscale's relays. First login: from the tray icon, or
  `tailscale up`.
- **Steam Deck locks when it goes to sleep.** `hypr/hypridle.conf` runs
  `loginctl lock-session` before sleep (power button or the 30-minute idle
  sleep), so hyprlock is shown when the Deck wakes up. It still doesn't lock
  while only idle (the screen dims and turns off). Unlocking stays a YubiKey
  touch, the same key the Deck needs to boot. README updated.
- **Claude Desktop starts at login, in the tray** (all profiles:
  Desktop, Asus Laptop, Steam Deck). `hypr/hyprland/execs.lua` runs
  `claude-desktop --startup` when Hyprland starts. `--startup` starts the app
  without opening its window; it waits as an icon in waybar's tray, and a click
  on that icon opens it. Claude Desktop itself was already installed by
  `Install.sh` (AUR package `claude-desktop`); only the autostart is new.

### Changed
- **Claude Desktop no longer starts at login, for now** (all profiles:
  Desktop, Asus Laptop, Steam Deck). The `claude-desktop --startup` line in
  `hypr/hyprland/execs.lua` is commented out so the app can be set up first;
  remove the `-- ` in front of it to turn the autostart back on. The app is
  still installed by `Install.sh`.
- **Steam Deck: the on-screen keyboard no longer pops up by itself** in text
  fields; it's opened and closed only with the keyboard button in waybar.
  `hypr/hyprland/execs.lua` turns off squeekboard's automatic popup at login
  (`gsettings set org.gnome.desktop.a11y.applications
  screen-keyboard-enabled false`) instead of starting `osk-auto.sh`, which is
  removed: it only turned the popup off while a USB or Bluetooth keyboard was
  connected, and with the popup always off it has nothing left to do.
  `osk-toggle.sh` comments and README updated.
- **Bigger waybar on the Steam Deck**, so it's easier to tap: font 15px →
  18px, more padding inside the bar (7px → 8px) and around each module
  (5px → 7px), tray icons 14 → 17. (First tried at 20px, which was too big.)
- **Steam Deck: the swipe up from the bottom edge opens the app launcher**
  (nwg-drawer) instead of the on-screen keyboard. Swiping over the keys typed
  stray letters, and lisgd can't keep the touch away from squeekboard, so
  the keyboard is now opened and closed only with the waybar button (or
  pops up by itself in text fields). The swipe from the left edge no
  longer does anything (left free for later), so the launcher opens with
  the bottom swipe or the Super key. The unused `keyboard` action is removed from
  `hypr/scripts/touch-gestures.sh`, as is the left-edge gesture; comments in `osk-auto.sh` and
  `app-drawer.sh` and the README are updated. This replaces today's earlier
  keyboard-swipe changes.
- **Steam Deck waybar: CPU and RAM usage removed** to make room in the bigger
  bar (`cpu` and `memory` modules and their styles). btop still shows them.

### Removed
- **Unused Hyprland color file** (all profiles). `hypr/colors/colors.lua`
  defined `color0`…`color15`, `background` and `foreground` for Hyprland, but
  no setting used them (the window borders come from
  `hypr/hyprland/border-colors.lua`, which wallust writes separately). Removed
  together: the file, `require("colors/colors")` in `hypr/hyprland.lua`
  (deleting only the file made Hyprland fail with "module 'colors/colors' not
  found"), `wallust/templates/colors-lua.template` and its `colors-lua` entry
  in `wallust/wallust.toml`. Hyprland gets exactly the same settings as
  before, border colors included; the other wallust colors (hyprlock, waybar,
  swaync, SwayOSD, rofi, foot, btop, OpenCode, nwg-drawer) are unchanged.
  README updated.
- **Cleanup steps for older versions of the setup**, which a fresh install
  never needs:
  - `Post Install/run-all-common.sh`: step F, which removed `RADV_PERFTEST`
    and `MESA_NO_ERROR` from `/etc/environment` (only an older version of the
    script added them), and its unused `ENV_FILE` variable. The audio step
    is now F (was G), and its parts F.1 / F.2 (were labelled H.1 / H.2).
  - `Post Install/yubikey-setup.sh`: merging several `user:...` lines in the
    YubiKey key file into one (older setups added the 2nd key as a second
    line; the script always writes one line), and removing `pam_u2f` lines
    from `/etc/pam.d/sudo`, `greetd` and `system-login` (older setups put
    them there; the key is now added once, to `system-auth`). The check that
    those apps include `system-auth` stays.

### Fixed
- **Wrong comment in the Secure Boot step** of
  `Post Install/run-all-common.sh`: it said "unfreeze and retry once", but
  the code makes the firmware's Secure Boot variables writable, enrolls once
  and makes them read-only again; there is no retry. Comment only.
