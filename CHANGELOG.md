# Changelog

Changes to VK-Dotfiles, newest first.

## 2026-10-18

### Added
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
