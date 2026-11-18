#!/bin/bash
# Install.sh - Desktop profile
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-desktop.sh" (kernel, boot, tuning)
# and "Post Install/yubikey-setup.sh" (only the YubiKey parts you chose at the
# start: login and/or disk unlock), so this one file does the whole setup.
# Reboot once at the end.

# the package lists and settings below are read by install-common.sh
# shellcheck disable=SC2034
set -uo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# the steps all profiles share (functions named vk_*)
# shellcheck source=/dev/null  # (checked on its own)
source "$PROFILE_DIR/../Post Install/install-common.sh"

vk_init
vk_ask_yubikey

# === Packages (official repos) ===
PACMAN_PKGS=(
    yt-dlp
    gst-plugin-gtk
    gst-libav
    feishin
    btrfs-progs
    dosfstools
    exfatprogs
    e2fsprogs
    ntfs-3g
    plymouth
    fwupd
    adobe-source-han-sans-otc-fonts
    adobe-source-han-serif-otc-fonts
    adobe-source-sans-fonts
    adobe-source-serif-fonts
    android-tools
    android-udev
    qbittorrent
    gamemode
    gimp
    wget
    partitionmanager
    kdenlive
    libreoffice-fresh
    mangohud
    noto-fonts-emoji
    obs-studio
    prismlauncher
    moonlight-qt
    steam
    ttf-dejavu
    ttf-liberation
    vlc
    vlc-plugins-all
    nfs-utils
    pcsclite
    ccid
    opensc
    cups
    freecad
    audacity
    solaar
    greetd
    greetd-tuigreet
    gnome-keyring
    unzip
    papers
    element-desktop
    syncthing
    lact
    unrar
    smartmontools
    7zip
    wine
    nodejs
    qt6-multimedia-ffmpeg
    jre-openjdk
    vulkan-radeon
    lib32-vulkan-radeon
    sbctl
    chromium
    xdg-user-dirs
    hyprland
    hyprlock
    hypridle
    btop
    # GPU monitor (usage, memory, temperature, per-process; AMD, Intel and NVIDIA)
    nvtop
    fastfetch
    thunar
    thunar-volman
    gvfs
    gvfs-mtp
    gvfs-smb
    tumbler
    ffmpegthumbnailer
    file-roller
    thunar-archive-plugin
    foot
    nano
    git
    base-devel
    pacman-contrib
    zsh
    pkgfile
    # the bar, control center, notifications and popups (~/.config/quickshell)
    quickshell
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    # the mixer's Devices button: show or hide sound devices (popups/Mixer.qml)
    pavucontrol
    # the music visualizer in the bar and the control center
    cava
    earlyoom
    noto-fonts
    ristretto
    eza
    ttf-jetbrains-mono-nerd
    ttf-ubuntu-font-family
    ttf-nerd-fonts-symbols
    nwg-look
    orchis-theme
    papirus-icon-theme
    qt5ct
    # Qt theme engine: the frosted glass for Qt apps (hypr/scripts/kvantum-glass.sh)
    kvantum
    kvantum-qt5
    qt5-wayland
    qt6-wayland
    breeze-icons
    breeze
    grim
    cliphist
    wl-clipboard
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    discord
    yubikey-manager
    pam-u2f
    libfido2
    ghostscript
    skanlite
    sane-airscan
    rtkit
    easyeffects
    # EasyEffects' equalizer, compressor, delay and loudness (without it the
    # equalizer can't be added or does nothing)
    lsp-plugins-lv2
    librewolf
    otf-geist-mono-nerd
    bluez
    bluez-utils
    libnotify
    # in the CachyOS repo (were installed through yay before)
    faugus-launcher
    jdownloader2
    claude-desktop
    claude-code
    # the bar's network icon, the network panel and the control center (state
    # and Wi-Fi from NetworkManager; nmtui comes with it, for VPN / static IP)
    networkmanager
    # Stream Deck app (official repo; was the AUR opendeck-bin)
    opendeck
)

# === Packages (AUR, via yay) ===
# The desktop itself needs these: installed on their own first, so a failed
# build of one of the big optional apps below can't leave them out
AUR_ESSENTIAL_PKGS=(
    wallust
    bibata-cursor-theme-bin
    qt6ct-kde
)
AUR_PKGS=(
    rapidraw-bin
    bs-manager-bin
    xrizer
    lib32-xrizer
    wivrn-dashboard
    amethyst-mod-manager
    github-desktop-bin
    orca-slicer-bin
    mangojuice-bin
    localsend-bin
    imsprog
    vscodium-bin
    vscodium-bin-marketplace
    yubico-authenticator-bin
    bedrock-on-linux-bin
)

# === Services (enabled AND started) ===
SERVICES=(
    NetworkManager.service
    pcscd.service
    cups.service
    "syncthing@$USER.service"
    fwupd-refresh.timer
    fstrim.timer
    paccache.timer
    pkgfile-update.timer
    earlyoom.service
    lactd.service
    avahi-daemon.service
    rtkit-daemon.service
    bluetooth.service
)

# === Apps ===
vk_enable_multilib
vk_cachyos_repos
vk_install_pacman
vk_earlyoom "qs|quickshell"
vk_install_aur
# the Belgian eID middleware (eid-mw), with a temporary OpenSSL 4.0 fix
vk_eid_mw
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

# === Network, firewall, disks ===
vk_truenas
vk_printer
vk_firewall syncthing orcaslicer localsend wivrn
vk_smartd 70
vk_media_folders
xdg-user-dirs-update

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
    # the OBS plugin's settings: the repo has no password in them, yours is kept
    opendeck/settings/dev.theca11.multiobs.sdPlugin.json
)
vk_copy_configs
# KDE / Kirigami apps in dark colors (the WiVRn dashboard, EasyEffects, ...)
vk_kde_dark
vk_hyprlock_password
# LACT, Faugus Launcher and File Roller (Hyprland doesn't blur behind them)
# and LibreWolf (its address bar suggestions had no background) start without
# the GTK glass
vk_app_entries io.github.ilya_zlobintsev.LACT io.github.Faugus.faugus-launcher \
    io.github.Faugus.faugus-launcher.shortcut org.gnome.FileRoller librewolf
vk_easyeffects_presets
vk_prism_icons
vk_thunar_bookmarks
# the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/quickshell/scripts/*.sh
# frosted glass for Qt apps (Orchis for Kvantum, in the wallpaper's colors)
vk_kvantum_glass

# === Post install: kernel, boot and tuning, then the YubiKey setup (if chosen) ===
vk_post run-all-desktop.sh
vk_yubikey
vk_summary "Reboot now to start the CachyOS kernel and apply everything."
