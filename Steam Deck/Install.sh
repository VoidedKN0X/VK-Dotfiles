#!/bin/bash
# Install.sh - Steam Deck profile (LCD Steam Deck used as a Hyprland tablet)
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-steamdeck.sh" (kernel, boot, tuning)
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
    gamescope
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
    vulkan-radeon
    lib32-vulkan-radeon
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
    tailscale
    rofi
    nwg-drawer
    waybar
    playerctl
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    cava
    # calendar, music and volume popups of the bar (waybar/scripts/*.py)
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
    librewolf
    otf-geist-mono-nerd
    bluez
    bluez-utils
    libnotify
    squeekboard
    # in the CachyOS repo (were installed through yay before)
    jdownloader2
    auto-cpufreq
    claude-desktop
    claude-code
    # Wi-Fi/network tools used by the swaync Wi-Fi button and waybar (nmcli, nmtui)
    networkmanager
)

# === Packages (AUR, via yay) ===
# The desktop itself needs these: installed on their own first, so a failed
# build of one of the big optional apps below can't leave them out
AUR_ESSENTIAL_PKGS=(
    lisgd
    wallust
    bibata-cursor-theme-bin
    qt6ct-kde
)
AUR_PKGS=(
    rapidraw-bin
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
    tailscaled.service
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
vk_install_pacman
vk_earlyoom "waybar|swaync"
vk_install_aur
vk_oh_my_zsh
vk_cleanup

# === Services and login screen ===
vk_mask_power_daemons
vk_enable_services
# Tailscale: lets you control it (and its tray icon) without sudo. Log in once
# from the tray icon, or with: tailscale up
sudo tailscale set --operator="$USER" || warn "could not make $USER the Tailscale operator"
# tablet: logged in automatically at boot (no keyboard needed)
AUTOLOGIN=1
vk_greetd

# === Steam Deck hardware ===
# Power button: short press = sleep, like SteamOS (systemd's default is power off).
# Takes effect after the next reboot.
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/50-steamdeck-power-button.conf >/dev/null <<'LOGIND'
[Login]
HandlePowerKey=suspend
LOGIND

# Touchscreen: a fixed name (/dev/input/touchscreen) for the gesture daemon, and
# read access for the logged-in user only ("uaccess"), instead of adding you to
# the "input" group, which would let every app read every keyboard.
sudo mkdir -p /etc/udev/rules.d
sudo tee /etc/udev/rules.d/70-touchscreen.rules >/dev/null <<'UDEV'
ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHSCREEN}=="1", SYMLINK+="input/touchscreen", TAG+="uaccess"
UDEV
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input --action=change

# === Network, firewall, disks ===
vk_truenas
vk_printer
vk_firewall syncthing orcaslicer localsend tailscale
vk_smartd 70
xdg-user-dirs-update

# === Configs ===
KEEP_IF_EXISTS=(
    hypr/colors/current-wallpaper.conf
    waybar/colors/colors.css
    waybar/layouts/current.jsonc
    swaync/colors/colors.css
    foot/colors-dark.ini
    rofi/colors/colors.rasi
    nwg-drawer/colors.css
    hypr/hyprland/border-colors.lua
    hypr/colors/hyprlock-colors.conf
    btop/themes/wallust.theme
    xfce4/xfconf/xfce-perchannel-xml/thunar.xml
    btop/btop.conf
)
vk_copy_configs
# the kept bar position (top/left) also sets where the notification panel
# goes: write those files to match it
"$HOME/.config/waybar/scripts/bar-position.sh" --files-only
vk_hyprlock_password
vk_app_entries
vk_prism_icons
vk_thunar_bookmarks
# the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/swaync/scripts/*.sh

# === Post install: kernel, boot and tuning, then the YubiKey setup (if chosen) ===
vk_post run-all-steamdeck.sh
vk_yubikey
vk_summary "Reboot now to start the CachyOS kernel and apply everything."
