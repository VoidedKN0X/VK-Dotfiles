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

## Three profiles

The repo has **three independent profiles**. Everything is duplicated on purpose, so each profile
stays self-contained and works on its own.

| Profile | Machine | What's different |
| --- | --- | --- |
| `Desktop/` | Desktop PC | Two monitors (3440x1440 + rotated 2560x1440, both 165 Hz, VRR), US keyboard layout, VR streaming with WiVRn, EasyEffects, AMD GPU |
| `Asus Laptop/` | Asus laptop | Any monitor at its preferred mode, Belgian keyboard layout, touchpad gestures, battery module in the bar, media keys, screen + keyboard backlight dimming, locks when the lid closes, Intel GPU |
| `Steam Deck/` | LCD Steam Deck with the controllers removed, used as a **tablet** | Rotated built-in screen, touchscreen gestures, on-screen keyboard, automatic brightness from the light sensor, Valve's fan control and BIOS updates, power button = sleep, auto-login, no automatic screen lock, AMD GPU (see [Steam Deck](#steam-deck-tablet)) |

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
"VK-Dotfiles/Desktop/Install.sh"        # or "Asus Laptop/Install.sh" / "Steam Deck/Install.sh"
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
sudo "VK-Dotfiles/Post Install/run-all-desktop.sh"   # or run-all-laptop.sh / run-all-steamdeck.sh
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

All kernel and boot changes are made before the images are built, so they're only built once. The
entry scripts share their logic in `run-all-common.sh`, so a fix only has to be made once.

`run-all-steamdeck.sh` differs in three ways: it installs **`linux-cachyos-deckify`** (the CachyOS
handheld kernel, the only one with the Steam Deck's fan/sensor, embedded-controller and USB-C dock
drivers), it **skips Secure Boot** (the Deck's firmware has no Secure Boot switch, so enrolled keys
can't simply be turned off again), and it adds Valve's **fan control** and **BIOS updates** (see
[Steam Deck](#steam-deck-tablet)).

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

## Steam Deck (tablet)

The `Steam Deck/` profile turns an LCD Steam Deck without its controllers into a Hyprland tablet.
It's based on the laptop profile.

**Touchscreen gestures** (via [lisgd](https://git.sr.ht/~mil/lisgd)):

| Gesture | Action |
| --- | --- |
| Swipe up from the bottom edge | On-screen keyboard |
| Swipe down from the top edge | Notification center |
| Swipe right from the left edge | App launcher |
| 3 fingers left / right | Next / previous workspace |
| 3 fingers up | Fullscreen on/off |
| 3 fingers down | Close the window |

- **On-screen keyboard:** [squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard) pops up
  by itself when you tap a text field in most apps (GTK, Qt, Firefox/LibreWolf, foot). For apps
  that don't support that (Steam and other X11 apps, some Electron apps), use the swipe-up
  gesture.
- **Power button:** a short press puts the Deck to sleep, like SteamOS.
- **Login and lock:** logs in automatically at boot. The screen is **not locked automatically**
  (like SteamOS), because the on-screen keyboard can't appear on a lock screen. With a keyboard or
  a plugged-in YubiKey you can still lock by hand: hyprlock accepts a YubiKey touch without a
  keyboard.
- **Disk unlock:** on the Deck, `yubikey-setup.sh` enrolls your YubiKey for LUKS **without a PIN**
  (plug it in and touch it at boot), since there's no keyboard before the desktop starts. It can
  also replace older enrollments that needed a PIN. Desktop and laptop keep the PIN.
- **Brightness:** [wluma](https://github.com/max-baz/wluma) sets it automatically from the light
  sensor and learns your preference whenever you change it with the slider in the notification
  center.
- **Fan:** Valve's own fan curve (`jupiter-fan-control`).
- **BIOS updates:** checked 2 minutes after boot and every hour. With the charger connected (and
  at least 20% battery) a new BIOS is **prepared automatically but never installed with a forced
  reboot**: it installs the next time you restart. Notifications tell you when an update is
  available, ready, installed, or needs you. Status: `cat /var/lib/steamdeck-bios-update/status`.
- **Speakers:** work out of the box with the regular Arch audio packages. Valve's speaker tuning
  for the LCD model is already part of Arch's audio config.

After the first boot, test the gestures once. If a swipe goes the wrong way, change `ROTATION=3`
to `1` in `~/.config/hypr/scripts/touch-gestures.sh`. `touch-gestures.sh --debug` prints every
gesture it sees.

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
- **Steam Deck:** `Post Install/run-all-steamdeck.sh` only installs the Valve packages on an LCD
  Steam Deck (board "Valve Jupiter"); on anything else it skips them.
- **`hypr/variables.lua`:** terminal, file manager, browser, cursor and GTK theme.

## Structure

```
<profile>/                 # Desktop/, Asus Laptop/ or Steam Deck/
├── .config/               # Hyprland, waybar, swaync, rofi, wallust, foot, btop, fastfetch, ...
├── .zshrc                 # Shell config
└── Install.sh             # Apps, services, shell, login screen, printer, firewall, copies the configs

Post Install/
├── Post-Install.txt       # Run order + the few steps that are still manual
├── run-all-desktop.sh     # Kernel, boot and tuning for the desktop
├── run-all-laptop.sh      # Kernel, boot and tuning for the laptop
├── run-all-steamdeck.sh   # Kernel (deckify), boot, tuning + Valve hardware support for the Steam Deck
├── steamdeck/             # Steam Deck BIOS update service (installed by run-all-steamdeck.sh)
├── run-all-common.sh      # Shared logic for both (used by the two scripts above; don't run it directly)
└── yubikey-setup.sh       # YubiKey login + LUKS disk unlock (interactive)
```

## Credits

- [Elifouts](https://github.com/elifouts/Dotfiles): base of this config, tweaked to be more minimal and personal.
- [Claude](https://claude.ai) by Anthropic: co-wrote the scripts, fixes and documentation (see the note at the top).

---

Still in progress, I switch between Linux and Windows a lot. Suggestions and improvements are welcome!
