# Changelog

Changes to VK-Dotfiles, newest first.

## 2026-10-29

### Fixed
- **Waybar no longer crashes when music starts** (all profiles: Desktop,
  Asus Laptop, Steam Deck). Waybar's built-in `mpris` module crashed waybar
  (segfault in libplayerctl) the first time music started playing, so the bar
  had to be restarted by hand. It's replaced by `custom/mpris`, which runs
  `playerctl --follow metadata` as its own process, so a playerctl problem
  can't take the bar down. Clicking the title toggles play/pause. Titles are
  escaped (`markup_escape`), so a title with `&` or `<` still shows, and both
  music modules restart after 5 seconds if playerctl exits
  (`restart-interval`). This replaces the `mpris` module from 2026-10-22.
- **Fresh installs no longer stop at the pacman step** (all profiles).
  `Install.sh` wrote `/etc/default/earlyoom` before installing earlyoom; that
  file belongs to the earlyoom package, so pacman refused the whole install.
  It's now written after the pacman install.
- **HDR stays on when you change the wallpaper** (Desktop). wallust rewrites
  `hypr/hyprland/border-colors.lua`, which reloads the Hyprland config, and
  the reload put DP-1 back to SDR. The HDR toggle now keeps its state in
  `$XDG_RUNTIME_DIR/hypr-dp1-hdr`; every login still starts in SDR.
- **Restarting waybar (Super + R) no longer leaves playerctl running**
  (all profiles). The music modules' `playerctl --follow` processes don't
  exit with waybar, so every restart left another set behind;
  `restart-waybar-swaync.sh` now stops them with waybar.
- **Steam Deck BIOS updates**: a prepared update that didn't install at the
  next restart was reported as "ready" forever and never tried again. The
  boot it was prepared in is now saved with it; after a restart without the
  new version it's reported as failed and prepared again. Sleep, shutdown
  and the power button are blocked while the update is written
  (`systemd-inhibit`), and the "BIOS update ready" notification says to
  connect the charger before restarting.

### Changed
- **Desktop main monitor (DP-1) runs SDR by default, with HDR when needed.**
  It runs at 280 Hz (was 165 Hz). `render.cm_auto_hdr` switches it to HDR
  by itself while a fullscreen game or video shows HDR content, and
  <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> switches it by hand
  (needed for HDR on YouTube in Chromium, which only offers HDR when the
  screen is already in HDR mode). DP-2 never switches to HDR. The HDR
  brightness values come from the monitor's EDID; `sdr_min_luminance = 0`
  keeps SDR blacks black while in HDR. README updated.
- **Running `Install.sh` again keeps your wallpaper and colors** (all
  profiles). The chosen wallpaper (`hypr/colors/current-wallpaper.conf`), the
  files wallust generates from it, and settings apps save themselves
  (btop, and Thunar on the Deck) are only copied when they don't exist yet.
- **Each Desktop bar shows five dots for its own monitor's workspaces**: DP-1
  shows 1, 3, 5, 7, 9 and DP-2 shows 2, 4, 6, 8, 10 (the split from the
  workspace rules in `monitors.lua`), instead of 1-5 on both bars.
- **Desktop file associations** (`mimeapps.list`) cover every file type the
  installed apps can open (about 1,100 entries, alias names included):
  - web pages and links (also XHTML and browser add-ons): LibreWolf
  - all text and code (everything the system treats as text, also shell,
    Perl, Ruby, Lua, fish scripts, CSV, JSON, XML, YAML, TOML, logs): VSCodium
  - images: Ristretto for every type it can open (its gdk-pixbuf/glycin
    loaders: also AVIF, HEIC/HEIF, JPEG XL, SVG, ICO, TGA, ...), editor
    formats (XCF, PSD, JPEG 2000, ...) in GIMP
  - RAW photos (all 30 RAW types, also Canon CR3, CR2, Nikon NEF, Sony ARW,
    DNG, Fuji RAF): RapidRAW. Its own entry has no file argument and lists no
    file types, so the new `.local/share/applications/RapidRAW.desktop`
    overrides it with `Exec=RapidRAW %f` (RapidRAW opens the file straight in
    the editor) and the RAW types; `Install.sh` copies it. darktable stays
    available under "Open with" and keeps the HDR formats (ACES, Radiance, PFM)
  - all video and audio, and playlists: VLC
  - PDF and comic books: Papers; office documents: LibreOffice (Writer, Calc,
    Impress, Draw, Math); archives and disk images: File Roller
  - 3D prints (STL, OBJ, 3MF): OrcaSlicer; CAD (STEP, IGES, FreeCAD): FreeCAD
  - Windows programs and installers: Faugus; `.jar`: Java; torrents and magnet
    links: qBittorrent; certificates and keys: the certificate viewer
  - app links (Steam, Discord, Element, Heroic, GitHub Desktop, Claude,
    nxm, ...) go to their own app; Kdenlive and Audacity projects to their apps.
- **Asus Laptop and Steam Deck get the same file associations** as the
  Desktop, built from the apps their `Install.sh` installs. RapidRAW is now
  installed there too (AUR `rapidraw-bin`), so RAW photos open in it as on
  the Desktop. Windows programs (`.exe`, `.msi`, shortcuts), Wine help files,
  BSManager and OpenDeck links have no default there, since Faugus, Wine,
  BSManager and OpenDeck are Desktop-only.
- **Helper apps are hidden from the app launcher** (all profiles). The new
  `.local/share/applications/` folder holds copies of their entries with
  `NoDisplay=true`: Qt tools (Assistant, Designer, Linguist, QDBusViewer),
  qt5ct/qt6ct, nwg-look, Breeze style settings, Blueman, pavucontrol, CUPS,
  btop, foot client/server, Flameshot, G'MIC, lstopo, qv4l2/qvidcap,
  xgps/xgpsspeed, rofi and its theme selector, Thunar's bulk rename and
  settings, thunar-volman, File Roller, Papers, Ristretto, the VSCodium URL
  handler, and LibreOffice Base, Draw, Math and the start center (the apps
  still open their files). Claude Desktop's entry keeps its login in the
  GNOME keyring (`--password-store=gnome-libsecret`), and RapidRAW's entry is
  there too. `Install.sh` copies the folder in every profile.
- **Logging in is lighter** (all profiles). `wallpaper.sh` at login only shows
  the saved wallpaper; wallust, the waybar/swaync reload and the swayosd
  restart now run only for a new wallpaper, or when a wallust template
  changed since the colors were made.
- **`Install.sh`** (all profiles):
  - asks before removing orphaned packages (it removed them without asking,
    on every run);
  - switches the login screen to greetd also when another one (e.g. sddm) is
    enabled;
  - masks power-profiles-daemon, tuned and TLP when they're installed, so they
    don't fight auto-cpufreq over the CPU settings;
  - installs `faugus-launcher`, `jdownloader2`, `auto-cpufreq`,
    `claude-desktop` and `claude-code` with pacman (they're in the CachyOS
    repo), and the AUR packages the desktop needs (wallust, the cursor theme,
    qt6ct-kde, and lisgd on the Deck) before the optional ones, so a failed
    build can't leave them out;
  - installs and enables NetworkManager (the Wi-Fi button and waybar use
    `nmcli`/`nmtui`).
- **Asus Laptop**: `upower` (critical-battery action, keyboard backlight in
  swayosd) and `intel-media-driver` (hardware video decoding) are installed;
  the disk temperature warning is at 80 °C instead of 70 °C (laptop NVMe
  drives often pass 70 °C under load); waybar's network module matches any
  Wi-Fi card (`wl*`) and the temperature module reads the CPU package sensor
  (coretemp).
- **`yubikey-setup.sh`** saves a `.bak-yubikey` copy of `/etc/pam.d/system-auth`,
  `/etc/pam.d/hyprlock`, `/etc/crypttab.initramfs` and `/etc/kernel/cmdline`
  before changing them for the first time, and keeps keys saved on more than
  one line of `u2f_keys` (older setups) instead of dropping all but the first.

## 2026-10-22

### Changed
- **Waybar music module uses the built-in `mpris` module** (all profiles:
  Desktop, Asus Laptop, Steam Deck). The
  `custom/music` module (`waybar-module-music`) is replaced by Waybar's own
  `mpris` module, which shows the track title (max 20 characters) and hides
  itself when nothing is playing. A new `custom/playpause` button to its left
  shows the pause icon while playing and the play icon while paused, and
  toggles playback on click (`playerctl --follow status` / `playerctl
  play-pause`). `style.css` styles `#mpris` and `#custom-playpause` like the
  old `#custom-music`.

### Removed
- **`waybar-module-music-git`** from the AUR packages of all profiles;
  `playerctl` is added to the Desktop and Steam Deck packages instead (the
  Asus Laptop already had it).

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
- **Claude Desktop autostart uses the GNOME keyring** (all profiles). The
  (still commented-out) line in `hypr/hyprland/execs.lua` is now
  `claude-desktop --startup --password-store=gnome-libsecret`, so the app
  keeps its login in the GNOME keyring (gnome-keyring is installed by
  `Install.sh`). With a YubiKey-only login the keyring isn't unlocked at
  login, so the app may ask for the keyring password when it starts.
- **CachyOS repos are added before your apps are installed** (all profiles),
  so a fresh install downloads and installs everything once instead of
  twice. Before, `Install.sh` installed all apps from the Arch repos and
  stage 1 of `run-all-<profile>.sh` added the CachyOS repos afterwards; the
  official CachyOS installer ends with `pacman -Syu`, which then downloaded
  and reinstalled almost every package to switch it to the CachyOS build.
  Now `Install.sh` runs the new `Post Install/cachyos-repo.sh` right after
  enabling multilib and before the big `pacman -Syu --needed`, so the
  installer only switches the base system from archinstall and your apps are
  installed as CachyOS builds straight away (AUR packages that the CachyOS
  repo also has come prebuilt from it). `Install.sh` stops if the repo setup
  fails. `cachyos-repo.sh` holds the code that was in stage 1 (download and
  run the official installer, then check the repos and the keyring); stage 1
  of `run-all-common.sh` now calls it, so when Install.sh already added the
  repos it only checks them, and run on its own it still adds them. README
  updated.
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
- **Steam Deck: Thunar couldn't be navigated with the touchscreen.** A tap
  only selected a folder instead of opening it: Thunar opens items with a
  double-click by default, and two taps don't count as a double-click. New
  `.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml` (Steam Deck only)
  turns on Thunar's single-click mode (`misc-single-click`), so a tap opens a
  folder or file, and turns off selecting an item by hovering over it
  (`misc-single-click-timeout` = 0). To select files without opening them,
  drag a box around them from an empty spot, or use Ctrl+A. Install.sh
  copies the file with the rest of `.config`. README updated.
- **Wrong comment in the Secure Boot step** of
  `Post Install/run-all-common.sh`: it said "unfreeze and retry once", but
  the code makes the firmware's Secure Boot variables writable, enrolls once
  and makes them read-only again; there is no retry. Comment only.
