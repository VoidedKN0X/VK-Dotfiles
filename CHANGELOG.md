# Changelog

Changes to VK-Dotfiles, newest first.

## 2026-10-18

### Added
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
- **Steam Deck: closing the on-screen keyboard with the swipe no longer types
  letters.** In `hypr/scripts/touch-gestures.sh` the keyboard gesture (1 finger
  up from the bottom edge) now runs in lisgd's pressed mode (`P`): it fires as
  soon as the swipe is recognised, while the finger is still down, so the
  keyboard hides before the finger is lifted over its keys. The other gestures
  are unchanged.
