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
| `Desktop/` | Desktop PC | Two monitors (3440x1440 at 280 Hz + rotated 2560x1440 at 165 Hz, VRR; the main one runs SDR and switches to HDR by itself for fullscreen HDR games and video, or with <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd>), US keyboard layout, VR streaming with WiVRn, EasyEffects (with presets), AMD GPU |
| `Asus Laptop/` | Asus laptop | Any monitor at its preferred mode, Belgian keyboard layout, touchpad gestures, battery module in the bar and on the lock screen, media keys, screen + keyboard backlight dimming, locks when the lid closes, Intel GPU |
| `Steam Deck/` | LCD Steam Deck with the controllers removed, used as a **tablet** | Rotated built-in screen, bigger touch-friendly bar, battery on the lock screen, touchscreen gestures, on-screen keyboard (with a button in the bar), Valve's fan control and BIOS updates, power button = sleep, auto-login, no automatic screen lock, AMD GPU (see [Steam Deck](#steam-deck-tablet)) |

## What's inside

| Part | Used for |
| --- | --- |
| [Hyprland](https://hypr.land) | Window manager (Lua config in `.config/hypr/`) |
| waybar | The bar: blurred "dynamic island" style, on the top or left edge (see [The bar](#the-bar)) |
| swaync | Notifications + control center (Wi-Fi/Bluetooth toggles, volume, media) |
| Bar popups (`waybar/scripts/*.py`) | Calendar and music popups, and the on-screen popup for the volume, mic and brightness keys and Caps Lock (GTK4 + gtk4-layer-shell) |
| rofi | App launcher (on the Steam Deck: [nwg-drawer](https://github.com/nwg-piotr/nwg-drawer) instead), wallpaper picker, clipboard history |
| foot | Terminal |
| hyprlock / hypridle | Lock screen / screen-off and suspend timers |
| greetd + tuigreet | Login screen |
| [wallust](https://codeberg.org/explosion-mental/wallust) | Generates the colors of everything above from your wallpaper |
| zsh + Oh My Zsh | Shell |
| btop, fastfetch | System monitor, system info |

## Installation

Start from a fresh Arch install (I use `archinstall`) with **systemd-boot**. Want the YubiKey to
unlock an encrypted disk at boot? In archinstall's disk encryption menu, also set **HSM** to your
YubiKey: only then does it build the boot image with `sd-encrypt`, the hook that can use the key
(without it, step 3 can't set up the disk unlock). Then run **one script**, your profile's
`Install.sh`. When it's done it runs the other two by itself, in this
order: `run-all-<profile>.sh` (step 2) and `yubikey-setup.sh` (step 3). Reboot once at the end.

Using Secure Boot (desktop and laptop)? Put your firmware's Secure Boot in **Setup Mode** before you
start; see step 2.

```sh
git clone https://github.com/VoidedKN0X/VK-Dotfiles
```

### 1. `Install.sh`: apps and configs

Run the one for your profile as your **normal user** (not with `sudo`; it asks for your password
once at the start and keeps sudo active until the end, so the long AUR builds and steps 2 and 3
don't ask again). It works from any directory.

```sh
"VK-Dotfiles/Desktop/Install.sh"        # or "Asus Laptop/Install.sh" / "Steam Deck/Install.sh"
```

It does the following:

1. Enables the `multilib` repo if needed (for Steam, Wine and 32-bit drivers).
2. Adds the CachyOS repositories with the official CachyOS installer (`Post Install/cachyos-repo.sh`),
   before any of your apps are installed, so they're installed as CachyOS builds straight away
   instead of being downloaded and reinstalled a second time when the repos are added later.
   The installer switches only the base system from archinstall to the CachyOS builds.
3. Installs the packages (pacman), then `yay` and the AUR packages.
4. Installs Oh My Zsh (keeping your `.zshrc`), sets zsh as your shell and installs OpenCode.
5. Removes leftover build dependencies and cleans the package caches.
6. Enables the services (CUPS, Bluetooth, Syncthing, fstrim, ...) and the greetd login screen.
7. Sets up tuigreet, the TrueNAS network share, the printer and the ufw firewall (rules for
   Syncthing, LocalSend, OrcaSlicer, plus WiVRn on the desktop).
   It also sets up earlyoom (when memory runs out, the app using the most is closed instead of
   the system freezing) and turns on disk health checks (smartd): a failing disk shows up as a
   notification that stays until you close it.
8. Copies `.config` and `.zshrc` into your home folder, and adds Documents, Downloads, Music
   and Pictures to Thunar's sidebar (`~/.config/gtk-3.0/bookmarks`, built from your home
   folder, so it works for any username; bookmarks you already have are kept).
9. Runs step 2 and then step 3 below, and prints a short summary of all three. Step 3 still
   runs if step 2 reports a failure.

### 2. `run-all-<profile>.sh`: kernel, boot and tuning

`Install.sh` runs this for you. To run it again on its own:

```sh
sudo "VK-Dotfiles/Post Install/run-all-desktop.sh"   # or run-all-laptop.sh / run-all-steamdeck.sh
```

Then **reboot**. It runs these stages in order:

1. **CachyOS repositories:** already added by `Install.sh`, so this only checks them. Run on its
   own, it adds them with the official CachyOS installer (`cachyos-repo.sh`).
2. **CachyOS kernel:** installs `linux-cachyos`, makes it the default boot entry and adds the
   Plymouth boot splash. The boot menu timeout is set to 0; hold <kbd>Space</kbd> while booting to
   see the menu.
   - If you're still running the old kernel, its removal waits for the next boot: a one-shot
     service removes it only once `linux-cachyos` is actually running, then deletes itself.
3. **Unified kernel images + Secure Boot:** switches to UKIs and sets up Secure Boot with `sbctl`.
   It creates keys, enrolls them together with Microsoft's keys (for dual boot) and signs
   everything. Enrolling only works while your firmware's Secure Boot is in **Setup Mode**, so
   switch that on in the firmware settings *before* running `Install.sh`; after the reboot, turn
   Secure Boot on. If you skip Setup Mode, this step reports a failure and the rest still runs.
4. **Performance tuning:** sysctl (smaller write batches, BBR networking, NMI watchdog off, and
   swap tuning for zram when zram is set up, with zswap turned off), a hard-disk readahead rule,
   transparent huge pages, noatime, 32-bit gamemode and MangoHud, Proton-CachyOS, Heroic, the `ntsync`
   module (smoother frame times with Proton-CachyOS and GE-Proton), and a lower default PipeWire
   latency. The HDA audio power-save tweak is desktop-only, to save battery on the laptop and the
   Deck.
   At the end it checks everything it set up and prints a pass/fail summary.

All kernel and boot changes are made before the images are built, so they normally only need
building once (stage 3 rebuilds only if it had to switch a kernel to unified kernel images). The
entry scripts share their logic in `run-all-common.sh`, so a fix only has to be made once.

`run-all-steamdeck.sh` differs in three ways: it installs **`linux-cachyos-deckify`** (the CachyOS
handheld kernel, the only one with the Steam Deck's fan/sensor, embedded-controller and USB-C dock
drivers), it **skips Secure Boot** (the Deck's firmware has no Secure Boot switch, so enrolled keys
can't simply be turned off again), and it adds Valve's **fan control** and **BIOS updates** (see
[Steam Deck](#steam-deck-tablet)).

### 3. `yubikey-setup.sh`: YubiKey login and disk unlock (optional)

`Install.sh` runs this for you after step 2; answer **N** to the questions to skip it. To run it
again on its own (for example to add a 2nd key later):

```sh
sudo "VK-Dotfiles/Post Install/yubikey-setup.sh"
```

Keep your YubiKey(s) at hand. Every step asks before it changes anything:

1. **Registers your keys** for login. Keys that are already registered stay; a 2nd key is added
   to them.
2. **Accepts the key instead of your password** for sudo, the login screen and other logins, with
   your password as a fallback. It checks first that all of these really use the shared PAM file
   it edits.
   **The lock screen (hyprlock) accepts only the key**, not your password.
3. **Unlocks your LUKS-encrypted disk** with the key at boot (`systemd-cryptenroll`). It adds
   keys (e.g. your 2nd key as a backup); a key that's already enrolled stays, except PIN keys on
   the Steam Deck (see [Steam Deck](#steam-deck-tablet)).
   This needs the `sd-encrypt` boot hook (archinstall's **HSM** option, see above); with the older
   `encrypt` hook the script says so and skips this step.

Your password and LUKS passphrase keep working as a fallback, except on the lock screen. Locked
out of the lock screen without a key? Switch to a text console (Ctrl+Alt+F3), log in with your
password and run `pkill -USR1 hyprlock`.

## The bar

Waybar as separate "islands" of dark, blurred glass, with the wallpaper's accent color:

- **Islands:** workspaces (dots; the active one is a pill), music, clock, CPU / temperature / RAM,
  tray + Bluetooth + network + volume (+ battery, and on the Steam Deck the on-screen keyboard
  button), idle inhibitor, notifications, power menu.
- **Music:** a visualizer ([cava](https://github.com/karlstav/cava)) and the track title; it
  shows while a player has a title. Hovering slides out the artist and previous / play-pause /
  next. Clicking opens the **music popup** (cover, progress bar you can drag, controls).
- **Clock:** click for the **calendar popup**. Click outside it or press <kbd>Esc</kbd> to close.
- **CPU, temperature, RAM:** click for btop.
- **Notifications:** click for the notification panel (it opens under or next to the bell),
  right-click for do not disturb. Popups appear in the same spot.
- **Top or left edge:** <kbd>Super</kbd> + <kbd>B</kbd> moves the bar between the top and the
  left edge (on an OLED screen, so it doesn't stay in one place). The notification panel,
  calendar, music and volume popups move with it. The choice survives a reinstall.
- **Blur:** Hyprland's layer rules blur the bar (`hypr/hyprland/rules.lua`). swaync and the popups
  are GTK4 apps: they mark the areas to blur themselves with `backdrop-filter` in their CSS
  (Hyprland 0.56 follows the app, not the layer rules). The strength is `decoration.blur` in
  `hypr/hyprland/decoration.lua`, the same for everything.
- **Files:** `waybar/config.jsonc` only includes the others: `layouts/top.jsonc` /
  `layouts/left.jsonc` (what differs per edge), `layouts/current.jsonc` (the edge in use, written
  by `scripts/bar-position.sh`) and `modules.jsonc` (everything else). The popups are
  `waybar/scripts/calendar.py`, `music.py` and `osd.py`; `popup_common.py` holds their shared
  look and the gap between them and the bar (`GAP`, in px).
- **Fonts:** text in Ubuntu, icons from Symbols Nerd Font, so the icons line up with the numbers.

## Keybinds

| Keys | Action |
| --- | --- |
| <kbd>Super</kbd> (tap) | App launcher (tap again to close; the nwg-drawer app menu on the Steam Deck) |
| <kbd>Super</kbd> + <kbd>T</kbd> / <kbd>E</kbd> / <kbd>W</kbd> | Terminal / file manager / browser |
| <kbd>Super</kbd> + <kbd>D</kbd> | Discord |
| <kbd>Super</kbd> + <kbd>Q</kbd> | Close window |
| <kbd>Super</kbd> + <kbd>F</kbd> / <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>F</kbd> | Fullscreen / maximize |
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
| <kbd>Super</kbd> + <kbd>B</kbd> | Move the bar between the top and the left edge |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> *(desktop)* | HDR on/off on the main monitor (needed for HDR on YouTube in Chromium: turn it on, then reload the video) |
| <kbd>Super</kbd> + <kbd>M</kbd> | Log out |
| <kbd>Print</kbd> | Screenshot (copied + saved to `~/Pictures/Screenshots`) |
| <kbd>Shift</kbd> + <kbd>Print</kbd> | Screenshot of a selected area (draw on it, then Enter: copied + saved) |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>V</kbd> | Volume mixer |
| Volume / mute keys | Volume, mute, mic mute (with an on-screen popup) |
| Media keys, brightness keys *(laptop)* | Play/pause, next/previous, screen brightness (with an on-screen popup) |
| 3-finger swipe *(laptop)* | Switch workspace |

## Steam Deck (tablet)

The `Steam Deck/` profile turns an LCD Steam Deck without its controllers into a Hyprland tablet.
It's based on the laptop profile.

**Touchscreen gestures** (via [lisgd](https://git.sr.ht/~mil/lisgd)):

| Gesture | Action |
| --- | --- |
| Swipe up from the bottom edge | App menu |
| Swipe down from the top edge | Notification center |
| 3 fingers left / right | Next / previous workspace |
| 3 fingers up | Fullscreen on/off |
| 3 fingers down | Close the window |

- **On-screen keyboard:** [squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard),
  opened and closed only with the keyboard button (󰌌) in the bar. It doesn't pop
  up by itself when you tap a text field, so it never covers the screen unasked (and a USB or
  Bluetooth keyboard needs no special handling).
- **App menu:** [nwg-drawer](https://github.com/nwg-piotr/nwg-drawer) instead of rofi: a
  full-screen grid of big icons, without search bar or categories (typing on a physical keyboard
  still filters). Opens with the Super key or a swipe up from the bottom edge. Rofi is only used for the
  clipboard history and the wallpaper picker.
- **Thunar:** a tap opens a folder or file (single-click mode, set in
  `xfce4/xfconf/xfce-perchannel-xml/thunar.xml`), because two taps don't count as a double-click.
  To select files without opening them, drag a box around them from an empty spot, or use Ctrl+A.
- **Screen rotation:** the rotate button in the notification center switches between landscape
  and portrait; the touchscreen and gestures turn with it, and the choice is kept after a
  reboot.
- **Power button:** a short press puts the Deck to sleep, like SteamOS.
- **Login and lock:** logs in automatically at boot. The screen locks when the Deck goes to sleep,
  so the lock screen is there when it wakes up; it isn't locked while you're just idle. hyprlock
  only unlocks with a YubiKey touch, so no keyboard is needed (the same key the Deck already needs
  to boot).
- **Tailscale:** installed and running, with a tray icon in waybar to log in, connect/disconnect
  and pick an exit node. The first time, log in from the tray icon (or run `tailscale up`). The
  firewall allows everything that comes in over your tailnet.
- **Disk unlock:** on the Deck, `yubikey-setup.sh` enrolls your YubiKey for LUKS **without a PIN**
  (plug it in and touch it at boot), since there's no keyboard before the desktop starts. A key
  enrolled with a PIN (for example by archinstall's HSM option) can be enrolled again without one;
  the script then offers to remove the PIN slots. Desktop and laptop keep the PIN.
- **Brightness:** set it with the slider in the notification center (it's pointed at the Deck's
  backlight automatically at every login).
- **Fan:** Valve's own fan curve (`jupiter-fan-control`).
- **BIOS updates:** checked 2 minutes after boot and every hour. With the charger connected (and
  at least 20% battery) a new BIOS is **prepared automatically but never installed with a forced
  reboot**: it installs the next time you restart. Notifications tell you when an update is
  available, ready, installed, or needs you. Status: `cat /var/lib/steamdeck-bios-update/status`.
- **Speakers:** work out of the box with the regular Arch audio packages. Valve's speaker tuning
  for the LCD model is already part of Arch's audio config.
- **More FPS in heavy games:** gamescope is installed. Render a game at a lower resolution and
  upscale it with FSR via its Steam launch options:
  `gamescope -w 960 -h 600 -W 1280 -H 800 -F fsr -f -- %command%`.

After the first boot, test the gestures once. If a swipe goes the wrong way in landscape, change
`ROTATION=3` to `ROTATION=1` in `~/.config/hypr/scripts/touch-gestures.sh`.
`touch-gestures.sh --debug` prints every gesture it sees.

## Wallpaper and colors

Put your wallpapers in `~/Pictures/Wallpapers` (subfolders work too) and pick one with
<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd>. [wallust](https://codeberg.org/explosion-mental/wallust)
then regenerates the colors for Hyprland, waybar and its popups, swaync, rofi, foot, hyprlock, btop
and OpenCode.
The last wallpaper is re-applied at every login.

All generated color files are included in the repo as working defaults, so a fresh install
looks right before you've picked a wallpaper:
`hypr/colors/hyprlock-colors.conf`, `hypr/hyprland/border-colors.lua`,
`rofi/colors/colors.rasi`, `swaync/colors/colors.css`, `waybar/colors/colors.css`,
`foot/colors-dark.ini`, `btop/themes/wallust.theme`,
`opencode/themes/wallust.json`, and on the Steam Deck `nwg-drawer/colors.css`. wallust overwrites
them as soon as you set a wallpaper.
Until then, `hypr/colors/current-wallpaper.conf` makes the lock screen show a blurred screenshot.

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
- **`waybar/modules.jsonc`:** the network interface name (`eno1` / `wl*`), the CPU temperature
  sensor (also set in `btop/btop.conf`) and, on the desktop, which workspaces each monitor's bar
  shows.
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
├── run-all-desktop.sh     # Kernel, boot and tuning for the desktop
├── run-all-laptop.sh      # Kernel, boot and tuning for the laptop
├── run-all-steamdeck.sh   # Kernel (deckify), boot, tuning + Valve hardware support for the Steam Deck
├── steamdeck/             # Steam Deck BIOS update service (installed by run-all-steamdeck.sh)
├── run-all-common.sh      # Shared logic (used by the three scripts above; don't run it directly)
├── cachyos-repo.sh        # Adds the CachyOS repos (run by Install.sh first, and by run-all-common.sh)
└── yubikey-setup.sh       # YubiKey login + LUKS disk unlock (interactive)
```

## Credits

- [Elifouts](https://github.com/elifouts/Dotfiles): base of this config, tweaked to be more minimal and personal.
- [Claude](https://claude.ai) by Anthropic: co-wrote the scripts, fixes and documentation (see the note at the top).

---

Still in progress, I switch between Linux and Windows a lot. Suggestions and improvements are welcome!
