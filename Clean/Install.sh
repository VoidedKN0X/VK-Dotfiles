#!/bin/bash
# Install.sh - Clean profile
# The desktop of this repo without my personal apps and settings: Hyprland,
# the bar, notifications, launcher, lock screen, terminal and the colors that
# follow your wallpaper, plus the programs they need. Works on desktops and
# laptops, with any monitor (see README.md, "Clean profile").
#
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-clean.sh" (CachyOS kernel, boot
# splash, tuning). It asks one question at the start (the gaming extras) and
# then runs on its own. Reboot once at the end.

# the package lists and settings below are read by install-common.sh
# shellcheck disable=SC2034
set -uo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the steps all profiles share (functions named vk_*)
# shellcheck source=/dev/null  # (checked on its own)
source "$PROFILE_DIR/../Post Install/install-common.sh"

vk_init

# Gaming extras, installed by run-all-clean.sh at the end: asked now, so the
# rest can run without you
read -r -p "Install the gaming extras (Steam, gamemode, MangoHud, Proton-CachyOS, Heroic)? [y/N] " answer
if [[ "$answer" =~ ^[Yy] ]]; then
    GAMING_FLAG=--gaming
else
    GAMING_FLAG=--no-gaming
fi

# === Packages (official repos) ===
# Only what the config uses. Graphics drivers and CPU microcode aren't here:
# archinstall installs the right ones for your hardware.
PACMAN_PKGS=(
    # base tools (AUR builds, the shell's `clean` function, unzip for wallpapers etc.)
    base-devel
    git
    nano
    wget
    unzip
    pacman-contrib
    xdg-user-dirs

    # Hyprland and its lock screen and idle timers (the password prompts are
    # Quickshell's)
    hyprland
    hyprlock
    hypridle
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    qt5-wayland
    qt6-wayland
    gnome-keyring

    # login screen
    greetd
    greetd-tuigreet

    # the bar, control center, notifications, launcher and popups
    # (~/.config/quickshell)
    quickshell
    libnotify
    # the media keys
    playerctl
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    # the music visualizer in the bar and the control center
    cava
    # brightness keys and the dimming in hypridle.conf (no-op without a backlight)
    brightnessctl
    # battery in the bar and on the lock screen (hidden without a battery)
    upower

    # terminal, clipboard history, screenshots
    foot
    cliphist
    wl-clipboard
    grim

    # apps the keybinds and bar buttons open
    firefox
    thunar
    thunar-volman
    thunar-archive-plugin
    file-roller
    gvfs
    gvfs-mtp
    tumbler
    ffmpegthumbnailer
    btop
    # GPU monitor (usage, memory, temperature, per-process; AMD, Intel and NVIDIA)
    nvtop
    pavucontrol
    bluez
    bluez-utils
    # the bar's network icon, the network panel and the control center (nmtui
    # comes with it, for VPN / static IP)
    networkmanager

    # shell
    zsh
    pkgfile
    eza
    fastfetch

    # look: GTK and Qt themes, icons, fonts
    nwg-look
    orchis-theme
    papirus-icon-theme
    breeze
    breeze-icons
    qt5ct
    # Qt theme engine: the frosted glass for Qt apps (hypr/scripts/kvantum-glass.sh)
    kvantum
    kvantum-qt5
    adwaita-fonts
    noto-fonts
    noto-fonts-emoji
    ttf-ubuntu-font-family
    ttf-nerd-fonts-symbols
    ttf-jetbrains-mono-nerd
    otf-geist-mono-nerd

    # audio: realtime priority for PipeWire
    rtkit
    # tuning (see below): out-of-memory guard, disk health, boot splash, firewall
    earlyoom
    smartmontools
    plymouth
    ufw
)
# with the gaming extras: Steam and the native gamemode and MangoHud
# (run-all-clean.sh adds their 32-bit versions, Proton-CachyOS and Heroic)
if [[ $GAMING_FLAG == --gaming ]]; then
    PACMAN_PKGS+=(steam gamemode mangohud)
fi

# === Packages (AUR, via yay) ===
AUR_PKGS=(
    wallust
    bibata-cursor-theme-bin
    qt6ct-kde
)

# === Services (enabled AND started) ===
SERVICES=(
    NetworkManager.service
    bluetooth.service
    rtkit-daemon.service
    earlyoom.service
    fstrim.timer
    paccache.timer
    pkgfile-update.timer
)

# === Apps ===
vk_enable_multilib
vk_cachyos_repos
vk_install_pacman
vk_earlyoom "qs|quickshell"
vk_install_aur
vk_oh_my_zsh
vk_cleanup

# === Services and login screen ===
vk_enable_services
# tuigreet in pastel colors of your wallpaper (until the first wallpaper
# change: yours if you have them, else the ones this profile ships with)
colors_json="$HOME/.config/quickshell/colors.json"
[[ -f "$colors_json" ]] || colors_json="$PROFILE_DIR/.config/quickshell/colors.json"
vk_tuigreet_pastel "$colors_json"
vk_greetd /usr/local/bin/vk-tuigreet

# === Firewall and disks ===
# blocks everything that comes in unless you allow it (ufw's default). Add
# rules for your own apps with `sudo ufw allow <port or app>`.
vk_firewall
vk_smartd 70
# home folders (Documents, Downloads, Pictures, ...); the wallpaper picker
# (Super + Shift + W) looks in Pictures/Wallpapers
xdg-user-dirs-update
mkdir -p "$HOME/Pictures/Wallpapers"

# === Configs ===
KEEP_IF_EXISTS=(
    hypr/colors/current-wallpaper.conf
    quickshell/colors.json
    quickshell/bar-position
    foot/colors-dark.ini
    hypr/hyprland/border-colors.lua
    hypr/colors/hyprlock-colors.conf
    btop/themes/wallust.theme
    btop/btop.conf
    gtk-3.0/vk-colors.css
    gtk-4.0/vk-colors.css
)
ZSHRC_BACKUP=1
vk_copy_configs
# KDE / Kirigami apps in dark colors (the WiVRn dashboard, EasyEffects, ...)
vk_kde_dark
# hide helper apps (settings tools, foot server, ...) from the launcher, and
# File Roller (Hyprland doesn't blur behind it) and Firefox (it takes its
# address bar colors from GTK, so its suggestions would have no background)
# without the GTK glass
vk_app_entries org.gnome.FileRoller firefox
vk_thunar_bookmarks
# the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/quickshell/scripts/*.sh
# frosted glass for Qt apps (Orchis for Kvantum, in the wallpaper's colors)
vk_kvantum_glass

# === Post install: CachyOS kernel, boot splash and tuning ===
vk_post run-all-clean.sh "$GAMING_FLAG"
vk_summary "Put some wallpapers in ~/Pictures/Wallpapers, then reboot to start the" \
    "CachyOS kernel. After logging in, pick a wallpaper with Super + Shift + W."
