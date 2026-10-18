# Changelog

Changes to VK-Dotfiles, newest first.

## 2026-10-18

### Added
- **Claude Desktop starts at login, in the tray** (all profiles:
  Desktop, Asus Laptop, Steam Deck). `hypr/hyprland/execs.lua` runs
  `claude-desktop --startup` when Hyprland starts. `--startup` starts the app
  without opening its window; it waits as an icon in waybar's tray, and a click
  on that icon opens it. Claude Desktop itself was already installed by
  `Install.sh` (AUR package `claude-desktop`); only the autostart is new.
