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
    libayatana-indicator
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
    darktable
    flameshot
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
    hyprpolkitagent
    btop
    fastfetch
    awww
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
    rofi
    waybar
    playerctl
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    cava
    # calendar popup of the bar (waybar/scripts/calendar.py)
    python-gobject
    gtk4-layer-shell
    swaync
    earlyoom
    noto-fonts
    ristretto
    eza
    ttf-jetbrains-mono-nerd
    ttf-ubuntu-font-family
    ttf-nerd-fonts-symbols
    pavucontrol
    nwg-look
    orchis-theme
    papirus-icon-theme
    otf-codenewroman-nerd
    qt5ct
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
    blueman
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
    # Wi-Fi/network tools used by the swaync Wi-Fi button and waybar (nmcli, nmtui)
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
    eid-mw
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
vk_earlyoom "waybar|swaync"
vk_install_aur
vk_oh_my_zsh
vk_cleanup

# === Services and login screen ===
vk_enable_services
vk_greetd

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
    waybar/colors/colors.css
    waybar/layouts/current.jsonc
    swaync/colors/colors.css
    foot/colors-dark.ini
    rofi/colors/colors.rasi
    hypr/hyprland/border-colors.lua
    hypr/colors/hyprlock-colors.conf
    btop/themes/wallust.theme
    btop/btop.conf
)
vk_copy_configs
# the kept bar position (top/left) also sets where the notification panel and the volume
# popup
# goes: write those files to match it
"$HOME/.config/waybar/scripts/bar-position.sh" --files-only
vk_hyprlock_password
vk_app_entries
vk_easyeffects_presets
vk_prism_icons
vk_thunar_bookmarks
# the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/swaync/scripts/*.sh \
         "$HOME"/.config/rofi/launchers/type-2/launcher.sh

# === Post install: kernel, boot and tuning, then the YubiKey setup (if chosen) ===
vk_post run-all-desktop.sh
vk_yubikey
vk_summary "Reboot now to start the CachyOS kernel and apply everything."
