# VK-Dotfiles

Personal dotfiles for my Arch Linux, BTW :)

A Hyprland desktop with colors that follow your wallpaper, plus the scripts I use to set up a fresh
Arch install: packages, services, the CachyOS kernel, Secure Boot, a boot splash, performance tuning
and YubiKey login.

> 🤖 **Co-made with AI.** Parts of this repo were made together with
> [Claude](https://claude.ai) (Anthropic's AI assistant): most of the install and post-install
> scripts, the bug fixes and cleanup in the configs, and this README. I decided what went in and
> reviewed the changes, but as with any dotfiles: **read the scripts before you run them.**

> ⚠️ **These are my personal settings.** The Desktop, Asus Laptop and Steam Deck install scripts
> install *my* apps, enable *my* services and contain values for *my* network and hardware (see
> [Things to change for your setup](#things-to-change-for-your-setup)). Don't run them blindly on
> a machine you care about. **Want the desktop without my stuff? Use the
> [Clean profile](#clean-profile).**

## Four profiles

The repo has **four independent profiles**, all with the same desktop shell made in
[Quickshell](https://quickshell.org) (see [The desktop shell](#the-desktop-shell-quickshell)).
The configs are duplicated on purpose, so each profile stays self-contained and works on its
own; the install steps they share are in `Post Install/install-common.sh`.

| Profile | Machine | What's different |
| --- | --- | --- |
| `Desktop/` | Desktop PC | Two monitors (3440x1440 at 280 Hz + rotated 2560x1440 at 165 Hz, VRR; the main one runs SDR and switches to HDR by itself for fullscreen HDR games and video, or with <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd>), US keyboard layout, VR streaming with WiVRn, EasyEffects (with presets that switch with the output), OpenDeck for the Stream Deck (profiles and plugins), AMD GPU with LACT overclocking, CPU always on the `performance` governor, watchdogs off |
| `Asus Laptop/` | Asus laptop | Any monitor at its preferred mode, Belgian keyboard layout, touchpad gestures, battery in the bar and on the lock screen, brightness slider in the control center, media keys, screen + keyboard backlight dimming, locks when the lid closes, Intel or AMD graphics (detected at install), auto-cpufreq: full speed on AC, longest battery life on battery |
| `Clean/` | **Any** desktop or laptop: for everyone who isn't me | Only the desktop itself and the programs it needs, with the graphics drivers for the hardware it finds (AMD, Intel, NVIDIA) and laptop or desktop power settings; none of my apps, network shares, printer or hardware settings, no Secure Boot and no YubiKey setup (see [Clean profile](#clean-profile)) |
| `Steam Deck/` | LCD Steam Deck with the controllers removed, used as a **tablet** | Rotated built-in screen, battery in the bar and on the lock screen, touchscreen gestures, on-screen keyboard (with a button in the bar), rotate button in the control center, Valve's fan control and BIOS updates, power button = sleep, auto-login, no automatic screen lock, AMD GPU, auto-cpufreq: full speed on AC, longest battery life on battery (see [Steam Deck](#steam-deck-tablet)) |

## What's inside

| Part | Used for |
| --- | --- |
| [Hyprland](https://hypr.land) | Window manager (Lua config in `.config/hypr/`) |
| [Quickshell](https://quickshell.org) | The whole desktop shell: wallpaper, bar, control center, notifications, popups, app launcher, wallpaper picker, clipboard history, volume mixer, window switcher, workspace overview, screenshots and the password dialog (see [The desktop shell](#the-desktop-shell-quickshell)) |
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
order: `run-all-<profile>.sh` (step 2) and `yubikey-setup.sh` (step 3, only the parts you chose).
Reboot once at the end.

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
4. Installs Oh My Zsh (keeping your `.zshrc`) and sets zsh as your shell.
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
   Prism Launcher gets the icon packs made for it (Fluent Dark, Ore UI, OSX, iOS and Twemoji,
   from its official [Themes](https://github.com/PrismLauncher/Themes) repository) in
   `~/.local/share/PrismLauncher/iconthemes`, with Fluent Dark picked, and Prism's "System" theme,
   so it gets the frosted glass of the other Qt apps; switch either in Prism's
   Settings > Appearance. It also gets GameMode and tuned Java arguments, and GameMode is set
   up for games (see [Gaming](#gaming)).
9. Runs step 2 and then step 3 below, and prints a short summary of all three. Step 3 still
   runs if step 2 reports a failure.

### 2. `run-all-<profile>.sh`: kernel, boot and tuning

`Install.sh` runs this for you. To run it again on its own:

```sh
sudo "VK-Dotfiles/Post Install/run-all-desktop.sh"   # or run-all-laptop.sh / run-all-steamdeck.sh / run-all-clean.sh
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
   On the desktop with an AMD graphics card it also turns on GPU overclocking for LACT
   (`amdgpu.ppfeaturemask=0xfff7ffff` on the kernel command line: the kernel's default plus
   OverDrive). On an existing install, run the desktop script again (or add that parameter to
   `/etc/kernel/cmdline` and rebuild with `sudo mkinitcpio -P`), then reboot.
   The desktop (and Clean on a desktop PC) keeps its CPU on the `performance` governor, now
   and at every boot (`/etc/tmpfiles.d/cpu-governor.conf`). The desktop also turns the
   watchdogs off (`nowatchdog` on the kernel command line, and the AMD chipset's `sp5100_tco`
   not loaded). Laptops (the laptop, the Deck and Clean on a laptop) use auto-cpufreq instead
   (`/etc/auto-cpufreq.conf`, written by `Install.sh`): full speed on AC (performance, boost
   on), the longest battery life on battery (powersave, power-saving energy preference, boost
   off). The laptop and Clean install the graphics drivers for the hardware they find, and
   Intel laptops get thermald.
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

Both parts are **optional**. Right after your password, `Install.sh` asks two questions:

- *Use a YubiKey for login, sudo and the lock screen?* (steps 1 and 2 below)
- *Unlock the encrypted disk with a YubiKey at boot?* (step 3)

Both default to **no**. Install.sh then runs unattended until the end, where it runs this
script with only the parts you said yes to (`--login` and/or `--disk`), or skips it. Without
the YubiKey login, the lock screen unlocks with your password and gets a password field
(`hypr/hyprlock-password.conf`, loaded from `hyprlock.conf`); with it, there's nothing to type, so
the field isn't there. Keep your
YubiKey(s) at hand for that. The parts you chose start right away; the questions that show what
will change or remove something (the PAM plan, adding more keys, removing PIN slots) are still
asked.

To run it again on its own (for example to add a 2nd key later), with every step asking first:

```sh
sudo "VK-Dotfiles/Post Install/yubikey-setup.sh"          # all steps
sudo "VK-Dotfiles/Post Install/yubikey-setup.sh" --login  # only login (steps 1 and 2)
sudo "VK-Dotfiles/Post Install/yubikey-setup.sh" --disk   # only the disk unlock (step 3)
```

The steps:

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

## Clean profile

`Clean/` is the same desktop (Hyprland, the Quickshell shell, foot, hyprlock, wallust colors)
for anyone's machine, without my personal apps and settings. It's based on the
laptop profile, so it works with any monitor and shows the battery when there is one.

```sh
git clone https://github.com/VoidedKN0X/VK-Dotfiles
"VK-Dotfiles/Clean/Install.sh"
```

Start from a fresh Arch install with **systemd-boot** and **PipeWire** (archinstall's defaults
for both). The graphics driver can stay on archinstall's default: the Clean profile finds your
graphics chips and installs their drivers itself.

**What it installs and sets up:**

- **Programs:** only what the config uses: Hyprland, hyprlock, hypridle, Quickshell, foot,
  wallust, cava, playerctl, cliphist, grim, Thunar, btop, pavucontrol, NetworkManager, zsh + Oh
  My Zsh, fastfetch, the GTK/Qt themes (with Kvantum for the Qt glass), icons, cursor and fonts,
  and Firefox (for <kbd>Super</kbd> + <kbd>W</kbd>; change `browser` in
  `hypr/variables.lua` to use another).
- **Login:** greetd + tuigreet, in pastel colors of your wallpaper.
- **Your hardware (detected):**
  - **Graphics:** AMD: Vulkan (RADV; OpenGL and video decoding come with mesa). Intel: Vulkan
    and video decoding. NVIDIA GTX 16 / RTX 20 and newer: NVIDIA's driver (the CachyOS kernel's
    open module, its libraries and video decoding), set up for sleep, with Hyprland's NVIDIA
    settings when it's the only graphics card. A laptop with built-in graphics plus NVIDIA:
    the desktop stays on the built-in chip (battery), and `prime-run <game>` starts a game on
    NVIDIA. NVIDIA GTX 10 and older: NVIDIA's current driver no longer supports them, so the
    open-source driver stays (with NVK for Vulkan); NVIDIA's legacy driver is
    `nvidia-580xx-dkms` in the AUR. With the gaming extras, also the 32-bit drivers.
  - **Desktop PC:** the CPU always on the `performance` governor (full speed).
  - **Laptop** (a battery or a laptop case): auto-cpufreq, at full speed on AC and the longest
    battery life on battery (boost off), on Intel and AMD; Intel laptops also get thermald.
- **Gaming extras (you choose):** `Install.sh` asks once at the start. Answer **y** for Steam,
  gamemode and MangoHud (with their 32-bit versions), Proton-CachyOS, Heroic and the `ntsync`
  module (smoother frame times with Proton), with GameMode set up like on the other profiles
  (see [Gaming](#gaming)). The Mesa shader cache is 12 GB either way
  (`hypr/hyprland/env.lua`), so games don't have to recompile dropped shaders.
- **Tuning:** the CachyOS repos and kernel, unified kernel images, the Plymouth boot splash,
  and the performance tuning of step 2 (sysctl, zram swap, THP, noatime, hard-disk readahead,
  lower PipeWire latency), earlyoom, disk health notifications (smartd) and the ufw firewall
  (everything incoming blocked, no extra rules).
- **Configs:** `.config` and `.zshrc` (an existing `.zshrc` is saved as `.zshrc.bak` first).
  Settings that depend on your hardware are left on auto: every monitor at its preferred mode
  with a bar on each, the network interface (the first connected one), the CPU temperature
  sensor (found by its driver: AMD k10temp/zenpower or Intel coretemp), the battery and
  brightness (shown only when there are any), US keyboard layout (`hypr/hyprland/input.lua`).

**Not included** (compared to my profiles): my apps, Syncthing, the NAS share, the printer,
firewall rules for my apps, EasyEffects, the `/media` folders, Secure Boot and the
YubiKey setup. Secure Boot is off by default; to use it, set `SECURE_BOOT=1` in
`Post Install/run-all-clean.sh` (read [step 2](#2-run-all-profilesh-kernel-boot-and-tuning)
first). Run on its own, `sudo "Post Install/run-all-clean.sh"` asks about the gaming extras
(or takes `--gaming` / `--no-gaming`). The YubiKey setup can be run on its own: `sudo "Post Install/yubikey-setup.sh"`.

When it's done: put wallpapers in `~/Pictures/Wallpapers`, reboot, log in and pick one with
<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd>. Everything takes its colors from it.

## The desktop shell (Quickshell)

Every profile's desktop shell is one [Quickshell](https://quickshell.org) config
(`.config/quickshell/`): the wallpaper, bar, notifications and control center, the popups, app
launcher, wallpaper picker, clipboard history, volume mixer (pavucontrol stays for the full
mixer), Bluetooth and network panels, window switcher, workspace overview, screenshots and the
password dialog when an app asks for admin rights. nmtui (part of NetworkManager) stays for VPNs
and static addresses, but the bar and control center open the network panel instead.

The bar is a row of glass islands, set in a **frame**: one piece of
glass around each screen with a bar. The bar's side holds the islands, the other three sides are a
thin border (8 px), and the desktop inside has round corners. Windows stay inside the frame.
Every popup grows out of the frame's inner edge with rounded joins: the calendar, power menu,
mixer, Bluetooth and network panels out of the bar's side, the control center along the whole
right side (with a side bar: the bar's side), notifications out of the right side under a top bar
(the bar's side at the bottom with a side bar), the volume popup out of the right side, and the
launcher, wallpaper picker and clipboard out of the bottom. They're drawn in the frame's own layer,
so they're the same glass with the same blur, and they open by growing out of the frame's edge and
close by going back into it.
While one is open the frame moves above fullscreen apps too. The password dialog and the window
switcher float in the middle.

- **Islands:** workspaces (dots; at least 1 to 6, further up to the highest with windows; the
  focused one a pill), music
  (visualizer + title, hover for the artist and the buttons), clock, CPU / temperature / memory
  (as percentages; the control center shows memory used / total), tray + Bluetooth + network +
  volume (+ the battery on a laptop, and on the Steam Deck the on-screen keyboard button), stay
  awake, notifications, power.
- **Every icon opens its program or panel:** CPU, temperature and memory open btop, Bluetooth
  opens the Bluetooth panel (right click: Bluetooth on/off), network opens the network panel,
  volume opens the mixer (scroll: volume, right click: mute), tray icons open their app (right
  click: their menu).
- **Bluetooth panel:** on/off, your paired devices (connect/disconnect, battery, forget), and
  *Search* to find new devices in pairing mode; click one to pair, trust and connect it. A device
  that asks for a PIN code needs `bluetoothctl` in a terminal (Quickshell can't answer PIN requests
  yet).
- **Network panel:** each cable connection with its state and IP address; on a PC with Wi-Fi also
  Wi-Fi on/off and the networks around (strongest first): click one to connect, a password field
  opens when it needs one; disconnect and forget. *More settings* opens nmtui.
- **Window switcher** (<kbd>Alt</kbd> + <kbd>Tab</kbd>): live previews of every window, most
  recently used first. Keep <kbd>Alt</kbd> down, <kbd>Tab</kbd> / <kbd>Shift</kbd> + <kbd>Tab</kbd>
  to pick, let go to switch; a quick <kbd>Alt</kbd> + <kbd>Tab</kbd> flips between the last two.
- **Workspace overview** (<kbd>Super</kbd> + <kbd>Tab</kbd>, or middle-click the workspaces
  island): on the monitor that has the focus, that monitor's workspaces as thumbnails with their
  windows as live previews at their real place. Click a workspace to go there, click a window to
  focus it, drag a window onto another workspace to move it,
  middle-click a window to close it. Type to find a window (the others dim, <kbd>Enter</kbd> goes
  to it); arrow keys + <kbd>Enter</kbd> pick a workspace; <kbd>Esc</kbd> clears the search, then
  closes it.
- **Screenshot** (<kbd>Print</kbd>): both monitors in one image, saved to
  `~/Pictures/Screenshots` and copied to the clipboard, with a short flash and a notification
  (Open / Show in folder). `hypr/scripts/screenshot.sh`, with grim.
- **Volume:** click the volume icon (or <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>V</kbd>) for the
  **mixer**: pick the output and input device, their volume, and a volume slider for every app
  playing sound. Its **Edit** button hides devices you never use (a GPU's HDMI outputs, a webcam
  mic) from the popup's lists, remembered per PC; click them again to show them. That only hides
  them in the popup, so it also works for devices pavucontrol can't turn off. The **pavucontrol**
  button opens the full mixer, separately: there a sound card's profile **Off** turns its
  outputs and inputs off everywhere.
- **Clock:** click for the **calendar** (month view, Monday first; arrows or scrolling change the
  month, clicking the month's name goes back to today).
- **Power:** click for the **power menu** (lock, suspend, log out, restart, shut down; the last
  three need a second click).
- **Control center** (the bell or <kbd>Super</kbd> + <kbd>N</kbd>): an overlay, not a window,
  that floats over everything. Session buttons (lock, suspend, restart, shut down), quick toggles
  (network, Bluetooth, do not disturb, stay awake, bar position, wallpaper), CPU usage and memory
  as ring gauges with the CPU temperature between them (click for btop), volume and microphone
  sliders (and on a laptop or the Steam Deck screen brightness, with the battery's charge and
  time left), the music player, and the notifications (one row; click it for the list). Right-click
  the bell for do not disturb.
- **Notifications:** Quickshell is the notification daemon. Popups appear next to the bell on the
  focused monitor, stay 8 s (low: 6 s, critical: until closed; hovering keeps them) and stay in
  the control center's list. Clicking one runs its default action. With do not disturb on, only
  critical ones (like a failing disk) pop up.
- **Top or left edge:** <kbd>Super</kbd> + <kbd>B</kbd> (or the control center's toggle), saved
  in `quickshell/bar-position` (kept by a reinstall). The bar goes back into the frame and grows
  out of its new edge. On the desktop, DP-2 always has its bar on the right edge; the other
  profiles have a bar on every monitor.
- **App launcher** (tap <kbd>Super</kbd>): type to search (names, descriptions, keywords),
  <kbd>↑</kbd> / <kbd>↓</kbd> and <kbd>Enter</kbd>, or click. Always in alphabetical order, also
  while searching. To hide an app: copy its `.desktop` file from `/usr/share/applications` to
  `~/.local/share/applications` and add `NoDisplay=true` under `[Desktop Entry]`.
- **Wallpaper picker** (<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd>, or the control
  center's toggle): thumbnails of `~/Pictures/Wallpapers` (subfolders too), the current one
  outlined; search, arrow keys, <kbd>Enter</kbd> or a click.
- **Wallpaper:** Quickshell draws it (cropped to fill each monitor, fading over to a new one,
  GIFs play), from `hypr/colors/current-wallpaper.conf`, which `hypr/scripts/wallpaper.sh`
  writes and the lock screen reads.
- **Clipboard history** (<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>H</kbd>): what you copied,
  newest first (kept by cliphist); search, <kbd>Enter</kbd> copies it again,
  <kbd>Ctrl</kbd> + <kbd>Delete</kbd> removes it.
- **Admin rights (polkit):** when an app asks for your password, a dialog in the same glass
  (what's asking, a password field; with the YubiKey login also "touch your key").
- **Volume popup:** grows out of the frame's right side whenever the volume, the mic's mute or
  Caps Lock changes, whatever changed it (the keys, scrolling on the volume icon, the mixer, an
  app): it watches them itself. The volume keys still go through `hypr/scripts/osd.sh`. It's part of the frame, so it doesn't
  show over fullscreen apps.
- **Colors:** everything follows the wallpaper. wallust writes `quickshell/colors.json`
  (`wallust/templates/colors-quickshell.template`); Quickshell watches it and recolors at once,
  without a restart. The accent is wallust's color5, the glass is the palette's background, the
  text its foreground, and every other color (borders, cards, sliders, switches, the red of the
  power button) is made from those, with guards that keep it readable: the text stays light, the
  glass dark, the accent bright enough for dark text on it. A black and white wallpaper gives a
  gray shell (wallust fills the palette with shades, `fallback_generator` in `wallust.toml`).
  Window borders, foot, btop and the lock screen follow wallust too. App icons in the shell come
  from Papirus-Dark, like in the GTK apps.
- **Frosted glass in apps:** GTK 3 apps (Thunar, Ristretto, file dialogs) and GTK 4 / libadwaita
  apps (Papers, File Roller) get the same 42 % glass in the wallpaper's colors, blurred by
  Hyprland (`gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`; wallust writes their colors to
  `vk-colors.css`). Menus stay solid. Delete those `gtk.css` files to go back to the plain theme.
  Qt apps get it through Kvantum (`hypr/scripts/kvantum-glass.sh`, run at every wallpaper change):
  "VKGlass" in `~/.config/Kvantum`, made from Orchis Dark (the Kvantum version of the GTK apps'
  Orchis theme: rounded, flat, modern buttons; Install.sh downloads it from
  [Orchis-kde](https://github.com/vinceliuice/Orchis-kde)) with 42 % opaque windows in the
  wallpaper's colors; qt5ct and qt6ct use the `kvantum` style. Open Qt apps take new colors when
  they're started again, and Kvantum keeps video apps such as VLC and Kdenlive solid on purpose.
  Electron apps draw their own windows and can't be made see-through this way; foot has its own
  glass setting.
- **AMD GPU overclocking (desktop):** LACT is installed and its service enabled, and the
  post-install adds `amdgpu.ppfeaturemask=0xfff7ffff` to the kernel command line (the kernel's
  default plus OverDrive) on a desktop with an AMD card, so LACT can change clocks, voltage
  offset and power limit.
- **Restart:** <kbd>Super</kbd> + <kbd>R</kbd> (`hypr/scripts/restart-quickshell.sh`).
- **Login screen:** tuigreet (greetd) with a clock, your last user and session filled in and a dot
  per password character, on black, in pastel versions of your wallpaper's colors: wallust writes them to
  `/var/lib/vk-greeter/palette`, and `/usr/local/bin/vk-tuigreet` (written by `Install.sh`) softens
  them and loads them into the text console before tuigreet starts.
- **Blur:** Hyprland's layer rules blur everything named `vk-*` (`hypr/hyprland/rules.lua`).
- **Files:** `shell.qml` (what runs, and the `qs ipc` commands), `common/Theme.qml` (colors, fonts,
  sizes, icons), `services/` (system info, audio, music, notifications, network/Bluetooth),
  `bar/`, `controlcenter/`, `popups/`, `background/` (the wallpaper), and `scripts/stats.sh` (CPU, memory and temperature,
  every 2 s) and `scripts/cava.sh` (the visualizer). The monitors, their bar edges and their
  workspaces, and whether it's a touch tablet, are at the top of `services/BarState.qml`; the
  network interface (desktop: `eno1`, the others: the first connected one) is in
  `services/Connectivity.qml`.

## Keybinds

| Keys | Action |
| --- | --- |
| <kbd>Super</kbd> (tap) | App launcher (tap again to close) |
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
| <kbd>Super</kbd> + <kbd>N</kbd> | Control center |
| <kbd>Super</kbd> + <kbd>L</kbd> | Lock screen |
| <kbd>Super</kbd> + <kbd>R</kbd> | Restart Quickshell |
| <kbd>Super</kbd> + <kbd>B</kbd> | Move the bar between the top and the left edge (desktop: the main monitor's bar) |
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
| Swipe up from the bottom edge | App launcher |
| Swipe down from the top edge | Control center |
| 3 fingers left / right | Next / previous workspace |
| 3 fingers up | Fullscreen on/off |
| 3 fingers down | Close the window |

- **On-screen keyboard:** [squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard),
  opened and closed only with the keyboard button (󰌌) in the bar. It doesn't pop
  up by itself when you tap a text field, so it never covers the screen unasked (and a USB or
  Bluetooth keyboard needs no special handling).
- **App launcher:** the Quickshell launcher, the same as on the other profiles: opens with the
  Super key or a swipe up from the bottom edge.
- **Thunar:** a tap opens a folder or file (single-click mode, set in
  `xfce4/xfconf/xfce-perchannel-xml/thunar.xml`), because two taps don't count as a double-click.
  To select files without opening them, drag a box around them from an empty spot, or use Ctrl+A.
- **Screen rotation:** the rotate button in the control center switches between landscape
  and portrait; the touchscreen and gestures turn with it, and the choice is kept after a
  reboot.
- **Power button:** a short press puts the Deck to sleep, like SteamOS.
- **Login and lock:** logs in automatically at boot. The screen locks when the Deck goes to sleep,
  so the lock screen is there when it wakes up; it isn't locked while you're just idle. hyprlock
  only unlocks with a YubiKey touch, so no keyboard is needed (the same key the Deck already needs
  to boot).
- **Tailscale:** installed and running, with a tray icon in the bar to log in, connect/disconnect
  and pick an exit node. The first time, log in from the tray icon (or run `tailscale up`). The
  firewall allows everything that comes in over your tailnet.
- **Disk unlock:** on the Deck, `yubikey-setup.sh` enrolls your YubiKey for LUKS **without a PIN**
  (plug it in and touch it at boot), since there's no keyboard before the desktop starts. A key
  enrolled with a PIN (for example by archinstall's HSM option) can be enrolled again without one;
  the script then offers to remove the PIN slots. Desktop and laptop keep the PIN.
- **Brightness:** set it with the slider in the control center.
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

## Gaming

The same on every profile (Clean: with the gaming extras):

- **Game windows:** Steam games, gamescope, Minecraft and Wine/Proton games outside Steam (Heroic,
  Faugus: windows whose class ends in `.exe`) are marked as games in `hypr/hyprland/rules.lua`:
  opaque, tearing allowed (lower input lag), the game content type (VRR follows the game, not the
  cursor) and no screen lock or sleep while they're fullscreen (Steam games: while they're open).
- **GameMode** (`~/.config/gamemode.ini`): while a game runs with it, the CPU runs at full speed
  (`performance` governor) and the game gets a higher CPU priority (nice -10; the install adds you
  to the `gamemode` group for that, active after logging in again) and the highest disk priority.
  It starts by itself in Prism Launcher (turned on by the install). Elsewhere, turn it on once:
  - **Steam:** a game's Properties > Launch Options: `gamemoderun %command%` (with MangoHud:
    `gamemoderun mangohud %command%`);
  - **Heroic:** Settings > Game Defaults > Other > Use GameMode (running `Install.sh` again turns it
    on for Heroic and every installed game, when Heroic is closed);
  - **Faugus** (desktop): the GameMode box per game.
- **Quickshell:** the music visualizer (cava) and the Caps Lock check pause while GameMode runs
  (`services/GameMode.qml`, told by the GameMode hook `~/.config/gamemode/hook.sh`).
- **Minecraft (Prism Launcher, not on Clean):** Java arguments for every instance without its own: G1 with short
  pauses (works on every Java version Minecraft uses) and huge pages, for fewer stutters. Change
  them in Prism's Settings > Java.

Desktop only:

- **3D V-Cache (Ryzen 9 9950X3D):** while GameMode runs, the CPU prefers the CCD with the extra
  cache (`amd_x3d_mode` = `cache`), which most games like; after the last game it goes back to
  `frequency` (faster clocks for everything else). Done by the GameMode hook, with a udev rule
  (`/etc/udev/rules.d/90-vk-x3d-mode.rules`) that lets the `gamemode` group switch it. Check it
  with `cat /sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode` while a game runs.
- **CPU governor:** `performance` all the time, not only during games (see step 4 of
  `run-all-<profile>.sh`). Clean on a desktop PC does the same.

## Wallpaper and colors

Put your wallpapers in `~/Pictures/Wallpapers` (subfolders work too) and pick one with
<kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd>. [wallust](https://codeberg.org/explosion-mental/wallust)
then regenerates the colors for Hyprland, Quickshell, the GTK and Qt glass, foot, hyprlock, btop
and the login screen.
The last wallpaper is re-applied at every login.

All generated color files are included in the repo as working defaults, so a fresh install
looks right before you've picked a wallpaper:
`hypr/colors/hyprlock-colors.conf`, `hypr/hyprland/border-colors.lua`,
`quickshell/colors.json`, `gtk-3.0/vk-colors.css`, `gtk-4.0/vk-colors.css`,
`foot/colors-dark.ini` and `btop/themes/wallust.theme`. wallust overwrites
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
- **`quickshell/services/BarState.qml`:** which monitor gets which bar, and their workspaces
  (desktop); **`quickshell/services/Connectivity.qml`:** the network interface (desktop: `eno1`).
- **`hypr/hypridle.conf` (laptop):** the keyboard backlight device is `asus::kbd_backlight`.
- **Steam Deck:** `Post Install/run-all-steamdeck.sh` only installs the Valve packages on an LCD
  Steam Deck (board "Valve Jupiter"); on anything else it skips them.
- **`hypr/variables.lua`:** terminal, file manager, browser, cursor and GTK theme.

## Structure

```
<profile>/                 # Desktop/, Asus Laptop/, Steam Deck/ or Clean/
├── .config/               # Hyprland, Quickshell, wallust, foot, btop, fastfetch, GTK/Qt themes, ...
├── .zshrc                 # Shell config
└── Install.sh             # The profile's apps, services and own steps; the rest via install-common.sh

Post Install/
├── run-all-desktop.sh     # Kernel, boot and tuning for the desktop
├── run-all-laptop.sh      # Kernel, boot and tuning for the laptop
├── run-all-steamdeck.sh   # Kernel (deckify), boot, tuning + Valve hardware support for the Steam Deck
├── run-all-clean.sh       # Kernel, boot and tuning for the Clean profile (no Secure Boot, gaming extras optional)
├── steamdeck/             # Steam Deck BIOS update service (installed by run-all-steamdeck.sh)
├── run-all-common.sh      # Shared logic (used by the four scripts above; don't run it directly)
├── install-common.sh      # The install steps every Install.sh shares (shell, login screen, firewall,
│                          #   configs, ...); sourced by them, don't run it directly
├── hw-detect.sh           # Finds the CPU and graphics makers and whether it's a laptop (used by
│                          #   install-common.sh and run-all-common.sh)
├── cachyos-repo.sh        # Adds the CachyOS repos (run by Install.sh first, and by run-all-common.sh)
├── eid-mw.sh              # Belgian eID middleware (AUR eid-mw) with a temporary OpenSSL 4.0 fix
├── eid-mw-openssl4.patch  #   (the upstream fix it applies; run by Install.sh)
└── yubikey-setup.sh       # YubiKey login + LUKS disk unlock (interactive)
```

## Credits

- [Elifouts](https://github.com/elifouts/Dotfiles): base of this config, tweaked to be more minimal and personal.
- [Claude](https://claude.ai) by Anthropic: co-wrote the scripts, fixes and documentation (see the note at the top).

---

Still in progress, I switch between Linux and Windows a lot. Suggestions and improvements are welcome!
