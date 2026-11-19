#!/bin/bash
# Install.sh - Asus Laptop profile
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-laptop.sh" (kernel, boot, tuning)
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
    brightnessctl
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
    unrar
    smartmontools
    7zip
    qt6-multimedia-ffmpeg
    jre-openjdk
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
    playerctl
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    cava
    # in the CachyOS repo (were installed through yay before)
    jdownloader2
    auto-cpufreq
    claude-desktop
    claude-code
    # the bar's network icon, the network panel and the control center (state
    # and Wi-Fi from NetworkManager; the panel does everything nmtui does,
    # through nmcli, which comes with it)
    networkmanager
    # battery: critical-charge action (CriticalPowerAction)
    upower
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
    auto-cpufreq.service
    "syncthing@$USER.service"
    fwupd-refresh.timer
    fstrim.timer
    paccache.timer
    pkgfile-update.timer
    earlyoom.service
    avahi-daemon.service
    rtkit-daemon.service
    bluetooth.service
)

# === Apps ===
vk_enable_multilib
vk_cachyos_repos
# graphics drivers (64- and 32-bit) for this laptop's Intel or AMD graphics,
# detected, with hardware video decoding (saves battery); Intel: also thermald
vk_hw_drivers lib32
vk_install_pacman
vk_nvidia_sleep
vk_earlyoom "qs|quickshell"
vk_install_aur
# the Belgian eID middleware (eid-mw), with a temporary OpenSSL 4.0 fix
vk_eid_mw
vk_oh_my_zsh
vk_cleanup

# === Services and login screen ===
vk_mask_power_daemons
# auto-cpufreq: full speed on AC, the longest battery life on battery
vk_auto_cpufreq
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
vk_firewall syncthing orcaslicer localsend
# laptop disks run warmer: warn above 80 °C
vk_smartd 80
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
)
vk_copy_configs
# KDE / Kirigami apps in dark colors (the WiVRn dashboard, EasyEffects, ...)
vk_kde_dark
vk_hyprlock_password
# File Roller (Hyprland doesn't blur behind it) and LibreWolf (it takes its
# address bar colors from GTK, so its suggestions would have no background)
# start without the GTK glass
vk_app_entries org.gnome.FileRoller librewolf
vk_prism_icons
# Prism Launcher: GameMode and tuned Java arguments
vk_prism_tune
# GameMode for games: the gamemode group (higher priority for games) and
# GameMode on in Heroic when it's set up
vk_gamemode
vk_thunar_bookmarks
# the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/quickshell/scripts/*.sh
# frosted glass for Qt apps (Orchis for Kvantum, in the wallpaper's colors)
vk_kvantum_glass

# === Post install: kernel, boot and tuning, then the YubiKey setup (if chosen) ===
vk_post run-all-laptop.sh
vk_yubikey
vk_summary "Reboot now to start the CachyOS kernel and apply everything."
