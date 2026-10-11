# VK-Dotfiles

Personal dotfiles for my Arch Linux, BTW :)

This repo contains **two independent profiles** that I keep fully separate:

| Profile | Machine | Highlights |
| --- | --- | --- |
| `Asus Laptop/` | Asus laptop | Touchpad gestures, battery/backlight waybar modules, eDP-1 monitor, Belgian kb layout |
| `Desktop/` | Desktop | Multi-monitor layout (DP-1 + DP-2), desktop performance tuning |

Everything is duplicated between the two on purpose, so each profile stays self-contained.

## Structure

```
<profile>/
├── .config/               # Hyprland, waybar, swaync, rofi, wallust, foot, btop, fastfetch, ...
├── .zshrc                 # Shell config
└── Install.sh             # Installs packages, enables services, copies .config into $HOME

Post Install/
├── Post-Install.txt       # Manual post-install checklist (greetd, bootloader, yubikey, firewall, ...)
├── run-all-*.sh           # Run-orchestrator per profile
├── *-full-tune-*.sh       # Performance tuning scripts
└── install-cachyos-*.sh   # CachyOS kernel / repository helpers
```

## Notes

- Wallpaper colors are generated with [wallust](https://wallust.codeberg.page/); the outputs it writes
  (`hypr/colors/`, `rofi/colors/`, `swaync/colors/`, `waybar/colors/`, `foot/colors-dark.ini`) are
  generated files and are **not tracked** — they appear after the first wallpaper is applied
  (`~/.config/hypr/scripts/wallpaper.sh`).
- ⚠️ **The install scripts are personal and only partially automated.** I do not fully automate the
  install yet. Read every script before running it — they install my packages, enable services and
  copy configs into your home directory. Don't run them blindly on a machine you care about.

## Usage

1. `git clone https://github.com/VoidedKN0X/VK-Dotfiles`
2. Read the `Install.sh` of the profile you want, then run it from your home directory.
3. Finish the manual steps in `Post Install/Post-Install.txt`.

## Credits

- [Elifouts](https://github.com/elifouts/Dotfiles) — base of this config, tweaked to be more minimal and personal.

---

Still in progress, I switch between Linux and Windows a lot. Suggestions and improvements are welcome!