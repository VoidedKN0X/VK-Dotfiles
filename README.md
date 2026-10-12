# VK-Dotfiles

Personal dotfiles for my Arch Linux, BTW :)

A Hyprland desktop with colors that follow your wallpaper, plus the scripts I use to set up a fresh
Arch install: packages, services, the CachyOS kernel, Secure Boot, a boot splash, performance tuning
and YubiKey login.

> 🤖 **Co-made with AI.** Parts of this repo were made together with
> [Claude](https://claude.ai) (Anthropic's AI assistant): most of the install and post-install
> scripts, the bug fixes and cleanup in the configs, and this README. I decided what went in and
> reviewed the changes, but as with any dotfiles: **read the scripts before you run them.**

> ⚠️ **These are my personal settings.** The install scripts install *my* apps, enable *my*
> services and contain values for *my* network and hardware (see
> [Things to change for your setup](#things-to-change-for-your-setup)). Don't run them blindly on
> a machine you care about.

## Two profiles

The repo has **two independent profiles**. Everything is duplicated on purpose, so each profile
stays self-contained and works on its own.

| Profile | Machine | What's different |
| --- | --- | --- |
| `Desktop/` | Desktop PC | Two monitors (3440x1440 + rotated 2560x1440, both 165 Hz, VRR), US keyboard layout, VR streaming with WiVRn, EasyEffects, AMD GPU |
| `Asus Laptop/` | Asus laptop | Any monitor at its preferred mode, Belgian keyboard layout, touchpad gestures, battery module in the bar, media keys, screen + keyboard backlight dimming, locks when the lid closes, Intel GPU |

## What's inside

| Part | Used for |
| --- | --- |
| [Hyprland](https://hypr.land) | Window manager (Lua config in `.config/hypr/`) |
| waybar | Top bar |
| swaync | Notifications + control center (Wi-Fi/Bluetooth toggles, volume, media) |
| rofi | App launcher, wallpaper picker, clipboard history |
| foot | Terminal |
| hyprlock / hypridle | Lock screen / screen-off and suspend timers |
| greetd + tuigreet | Login screen |
| [wallust](https://codeberg.org/explosion-mental/wallust) | Generates the colors of everything above from your wallpaper |
| zsh + Oh My Zsh | Shell |
| btop, fastfetch | System monitor, system info |

## Installation

Start from a fresh Arch install (I use `archinstall`) with **systemd-boot**. Then run three
scripts, in this order:

```sh
git clone https://github.com/VoidedKN0X/VK-Dotfiles
```

### 1. `Install.sh`: apps and configs

Run the one for your profile as your **normal user** (not with `sudo`; it asks for your password
when needed). It works from any directory.

```sh
"VK-Dotfiles/Desktop/Install.sh"        # or "VK-Dotfiles/Asus Laptop/Install.sh"
```

It does the following:

1. Enables the `multilib` repo if needed (for Steam, Wine and 32-bit drivers).
2. Installs the packages (pacman), then `yay` and the AUR packages.
3. Installs Oh My Zsh (keeping your `.zshrc`), sets zsh as your shell and installs OpenCode.
4. Removes leftover build dependencies and cleans the package caches.
5. Enables the services (CUPS, Bluetooth, Syncthing, fstrim, ...) and the greetd login screen.
6. Sets up tuigreet, the TrueNAS network share, the printer and the ufw firewall (rules for
   Syncthing, LocalSend, OrcaSlicer, plus WiVRn on the desktop).
7. Copies `.config` and `.zshrc` into your home folder.

### 2. `run-all-<profile>.sh`: kernel, boot and tuning (optional)

```sh
sudo "VK-Dotfiles/Post Install/run-all-desktop.sh"   # or run-all-laptop.sh
```

Then **reboot**. It runs these stages in order:

1. **CachyOS repositories:** added with the official CachyOS installer.
2. **CachyOS kernel:** installs `linux-cachyos`, makes it the default boot entry and adds the
   Plymouth boot splash. The boot menu timeout is set to 0; hold <kbd>Space</kbd> while booting to
   see the menu.
   - If you're still running the old kernel, its removal waits for the next boot: a one-shot
     service removes it only once `linux-cachyos` is actually running, then deletes itself.
3. **Unified kernel images + Secure Boot:** switches to UKIs and sets up Secure Boot with `sbctl`.
   It creates keys, enrolls them together with Microsoft's keys (for dual boot) and signs
   everything. Enrolling only works while your firmware's Secure Boot is in **Setup Mode**, so
   switch that on in the firmware settings *before* running this script; after the reboot, turn
   Secure Boot on. If you skip Setup Mode, this step reports a failure and the rest still runs.
4. **Performance tuning:** sysctl (memory, BBR networking), I/O schedulers, noatime, gamemode,
   ananicy-cpp, irqbalance, AMD GPU variables, audio. The only desktop/laptop difference is
   `vm.laptop_mode` (0 vs 5).
5. **Check:** verifies everything the CachyOS kernels need is in place.

All kernel and boot changes are made before the images are built, so they're only built once. Both
entry scripts share their logic in `run-all-common.sh`, so a fix only has to be made once.

### 3. `yubikey-setup.sh`: YubiKey login and disk unlock (optional)

```sh
sudo "VK-Dotfiles/Post Install/yubikey-setup.sh"
```

Keep your YubiKey(s) at hand. Every step asks before it changes anything:

1. **Registers your keys** for login.
2. **Accepts the key instead of your password** for sudo, the login screen, the lock screen and
   other logins. It checks first that all of these really use the shared PAM file it edits, and
   if the `sudo` test afterwards fails, it puts every file back exactly as it was.
3. **Unlocks your LUKS-encrypted disk** with the key at boot (`systemd-cryptenroll`).

Your password and LUKS passphrase always keep working as a fallback.

`Post Install/Post-Install.txt` repeats this run order and lists the few steps that are still manual.

## Keybinds

| Keys | Action |
| --- | --- |
| <kbd>Super</kbd> (tap) | App launcher (tap again to close) |
| <kbd>Super</kbd> + <kbd>T</kbd> / <kbd>E</kbd> / <kbd>W</kbd> | Terminal / file manager / browser |
| <kbd>Super</kbd> + <kbd>D</kbd> | Discord |
| <kbd>Super</kbd> + <kbd>Q</kbd> | Close window |
| <kbd>Super</kbd> + <kbd>F</kbd> / <kbd>Alt</kbd> + <kbd>F</kbd> | Fullscreen / maximize |
| <kbd>Super</kbd> + <kbd>V</kbd> | Toggle floating |
| <kbd>Super</kbd> + <kbd>P</kbd> / <kbd>J</kbd> | Pseudo-tile / toggle split direction |
| <kbd>Super</kbd> + arrow keys | Move focus |
| <kbd>Super</kbd> + <kbd>1</kbd>–<kbd>0</kbd> | Go to workspace 1–10 |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>1</kbd>–<kbd>0</kbd> | Move window to workspace 1–10 |
| <kbd>Ctrl</kbd> + <kbd>Super</kbd> + <kbd>←</kbd> / <kbd>→</kbd>, <kbd>Super</kbd> + scroll | Previous / next workspace |
| <kbd>Super</kbd> + left / right mouse drag, or <kbd>Z</kbd> / <kbd>X</kbd> | Move / resize window |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd> | Wallpaper picker (also recolors everything) |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>H</kbd> | Clipboard history (<kbd>Ctrl</kbd> + <kbd>Delete</kbd> removes an entry) |
| <kbd>Super</kbd> + <kbd>N</kbd> | Notification center |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock screen |
| <kbd>Super</kbd> + <kbd>R</kbd> | Restart the bar and notifications |
| <kbd>Super</kbd> + <kbd>M</kbd> | Log out |
| <kbd>Print</kbd> | Screenshot (copied + saved to `~/Pictures/Screenshots`) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>V</kbd> | Volume mixer |
| Volume / mute keys | Volume, mute, mic mute |
| Media keys, brightness keys *(laptop)* | Play/pause, next/previous, screen brightness |
| 3-finger swipe *(laptop)* | Switch workspace |

## Wallpaper and colors

Put your wallpapers in `~/Pictures/Wallpapers` (subfolders work too) and pick one with
<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd>. [wallust](https://codeberg.org/explosion-mental/wallust)
then regenerates the colors for Hyprland, waybar, swaync, rofi, foot, hyprlock, btop and OpenCode.
The last wallpaper is re-applied at every login.

Seven of the generated color files are included in the repo as working defaults, so a fresh install
looks right before you've picked a wallpaper:
`hypr/colors/colors.lua`, `hypr/hyprland/border-colors.lua`, `rofi/colors/colors.rasi`,
`swaync/colors/colors.css`, `waybar/colors/colors.css`, `btop/themes/wallust.theme` and
`opencode/themes/wallust.json`. wallust overwrites them as soon as you set a wallpaper. The rest
(`hypr/colors/hyprlock-colors.conf`, `hypr/colors/current-wallpaper.conf`, `foot/colors-dark.ini`)
are only created on your machine.

## Things to change for your setup

If you're not me, look at these before running anything:

- **`Install.sh`:**
  - the package lists (my apps);
  - the TrueNAS share (`192.168.1.9:/mnt/Data/axel`);
  - the printer (`Canon_TS5350a` at `192.168.1.60`);
  - the firewall rules;
  - the `/media` folders (desktop).
- **`hypr/hyprland/monitors.lua`:** monitor names, resolutions, positions and which workspace goes
  where.
- **`hypr/hyprland/input.lua`:** keyboard layout.
- **`waybar/config.jsonc`:** the network interface name (`eno1` / `wlp2s0`) and, on the desktop,
  the CPU temperature sensor (also set in `btop/btop.conf`).
- **`hypr/hypridle.conf` (laptop):** the keyboard backlight device is `asus::kbd_backlight`.
- **`hypr/variables.lua`:** terminal, file manager, browser, cursor and GTK theme.

## Structure

```
<profile>/                 # Desktop/ or Asus Laptop/
├── .config/               # Hyprland, waybar, swaync, rofi, wallust, foot, btop, fastfetch, ...
├── .zshrc                 # Shell config
└── Install.sh             # Apps, services, shell, login screen, printer, firewall, copies the configs

Post Install/
├── Post-Install.txt       # Run order + the few steps that are still manual
├── run-all-desktop.sh     # Kernel, boot and tuning for the desktop
├── run-all-laptop.sh      # Kernel, boot and tuning for the laptop
├── run-all-common.sh      # Shared logic for both (used by the two scripts above; don't run it directly)
└── yubikey-setup.sh       # YubiKey login + LUKS disk unlock (interactive)
```

## Credits

- [Elifouts](https://github.com/elifouts/Dotfiles): base of this config, tweaked to be more minimal and personal.
- [Claude](https://claude.ai) by Anthropic: co-wrote the scripts, fixes and documentation (see the note at the top).

---

Still in progress, I switch between Linux and Windows a lot. Suggestions and improvements are welcome!
