#!/bin/bash
# Install.sh - Desktop profile
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-desktop.sh" (kernel, boot, tuning)
# and "Post Install/yubikey-setup.sh" (asks before every step), so this one
# file does the whole setup. Reboot once at the end.

set -uo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not as root/sudo." >&2
    exit 1
fi

WARNINGS=0
warn() { echo "WARNING: $*" >&2; WARNINGS=$((WARNINGS + 1)); }

# $USER is used below for services and file ownership
USER="${USER:-$(id -un)}"

# Ask for your password once, then keep sudo active in the background, so the
# long AUR builds and the post-install steps don't ask again
sudo -v || { echo "This script needs sudo." >&2; exit 1; }
while sleep 60; do sudo -n true || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# === Packages (official repos) ===
PACMAN_PKGS=(
    libayatana-indicator
    yt-dlp
    gst-plugin-gtk
    gst-libav
    feishin
    bcachefs-tools
    btrfs-progs
    dosfstools
    exfatprogs
    f2fs-tools
    e2fsprogs
    jfsutils
    mtd-utils
    nilfs-utils
    ntfs-3g
    udftools
    xfsprogs
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
    ttf-firacode-nerd
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
    foot
    nano
    git
    base-devel
    zsh
    rofi
    waybar
    swaync
    noto-fonts
    ristretto
    eza
    ttf-jetbrains-mono-nerd
    pavucontrol
    nwg-look
    orchis-theme
    papirus-icon-theme
    otf-codenewroman-nerd
    qt5ct
    breeze-icons
    breeze
    grim
    cliphist
    wl-clipboard
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
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
    calf
    librewolf
    otf-geist-mono-nerd
    bluez
    bluez-utils
    libnotify
)

# === Packages (AUR, via yay) ===
AUR_PKGS=(
    rapidraw-bin
    bs-manager-bin
    faugus-launcher
    xrizer
    lib32-xrizer
    wivrn-dashboard
    amethyst-mod-manager
    wallust-git
    github-desktop-bin
    eid-mw
    heroic-games-launcher-bin
    jdownloader2
    orca-slicer-bin
    auto-cpufreq
    mangojuice-bin
    localsend-bin
    opendeck-bin
    imsprog
    vscodium-bin
    vscodium-bin-marketplace
    bibata-cursor-theme-bin
    waybar-module-music-git
    qt6ct-kde
    yubico-authenticator-bin
    bedrock-on-linux-bin
    claude-desktop
    claude-code
)

# === Services (enabled AND started) ===
SERVICES=(
    pcscd.service
    cups.service
    auto-cpufreq.service
    "syncthing@$USER.service"
    fwupd-refresh.timer
    fstrim.timer
    lactd.service
    avahi-daemon.service
    rtkit-daemon.service
    bluetooth.service
)

# Steam, Wine and the lib32-* packages come from the multilib repo: enable it
# if it isn't yet (uncomment the stock block, or add it if it's missing)
if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
    if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
    fi
fi

# Install apps from pacman (stop here if this fails: everything below depends on it).
# -Syu also refreshes the package lists (needed after enabling multilib) and avoids
# installing onto an out-of-date system (a partial upgrade).
sudo pacman -Syu --needed "${PACMAN_PKGS[@]}" || { echo "pacman install failed, stopping." >&2; exit 1; }

# Install yay (skipped if it's already installed), built in a temp dir
if ! command -v yay >/dev/null; then
    YAY_TMP="$(mktemp -d)"
    if git clone https://aur.archlinux.org/yay.git "$YAY_TMP/yay" && (cd "$YAY_TMP/yay" && makepkg -si); then
        rm -rf "$YAY_TMP"
    else
        rm -rf "$YAY_TMP"
        echo "yay install failed, stopping." >&2
        exit 1
    fi
fi

# Install apps from yay (a failed AUR build shouldn't stop the config copy below)
yay -S --needed "${AUR_PKGS[@]}" || warn "some AUR packages failed to install"

# === Shell + CLI tools (as your user) ===
# Oh My Zsh: --keep-zshrc so the installer never replaces your .zshrc with its
# template, --unattended so it doesn't stop to ask questions. The installer
# refuses to run if ~/.oh-my-zsh exists, so it's skipped in that case.
# Downloaded to a file first, so a failed download is reported as a failure.
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    OMZ_INSTALLER="$(mktemp)"
    if curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"; then
        sh "$OMZ_INSTALLER" --unattended --keep-zshrc || warn "Oh My Zsh install failed"
    else
        warn "Oh My Zsh download failed"
    fi
    rm -f "$OMZ_INSTALLER"
fi
# --unattended doesn't change the login shell, so do it here
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]]; then
    sudo chsh -s /usr/bin/zsh "$USER" || warn "could not set zsh as login shell"
fi

# OpenCode: --no-modify-path because .zshrc already adds ~/.opencode/bin to PATH
if [[ ! -x "$HOME/.opencode/bin/opencode" ]]; then
    curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path || warn "OpenCode install failed"
fi

# Remove leftover install files (orphaned deps such as make-dependencies, then caches)
mapfile -t ORPHANS < <(pacman -Qdtq)
if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    sudo pacman -Rns --noconfirm "${ORPHANS[@]}" || warn "orphan removal failed"
fi
yay -Sc --noconfirm || warn "cache cleanup failed"

# Enable services one by one, so one missing unit doesn't skip all the others
for unit in "${SERVICES[@]}"; do
    sudo systemctl enable --now "$unit" || warn "could not enable $unit"
done
# greetd is only enabled, not started: starting it now would replace this session
sudo systemctl enable greetd.service || warn "could not enable greetd.service"

# === Login screen (greetd + tuigreet) ===
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd start-hyprland"
user = "greeter"
GREETD


# === TrueNAS share (only added if /media/TrueNAS isn't in fstab yet) ===
TRUENAS_LINE='192.168.1.9:/mnt/Data/axel    /media/TrueNAS  nfs     noauto,user,_netdev,bg  0       0'
if ! grep -Eq '^[^#]*[[:space:]]/media/TrueNAS[[:space:]]' /etc/fstab; then
    # shellcheck disable=SC1003  # $a\ appends a newline if the file lacks one
    sudo sed -i -e '$a\' /etc/fstab
    printf '\n# TrueNAS\n%s\n' "$TRUENAS_LINE" | sudo tee -a /etc/fstab >/dev/null
    sudo systemctl daemon-reload
fi

# === Printer (driverless IPP Everywhere, no driver package needed) ===
if lpstat -p Canon_TS5350a >/dev/null 2>&1; then
    echo "Printer Canon_TS5350a already set up"
elif ! sudo lpadmin -p Canon_TS5350a -E -v ipp://192.168.1.60/ipp/print -m everywhere; then
    warn "could not add the printer (is it switched on?). Rerun later with:"
    echo "  sudo lpadmin -p Canon_TS5350a -E -v ipp://192.168.1.60/ipp/print -m everywhere" >&2
fi

# === Firewall (ufw) ===
# archinstall normally installs ufw; install it here if it's missing.
if ! command -v ufw >/dev/null; then
    sudo pacman -S --needed --noconfirm ufw || warn "could not install ufw"
fi
if command -v ufw >/dev/null; then
    # Syncthing: use the app profile if it exists, otherwise its default ports
    if sudo ufw app info syncthing >/dev/null 2>&1; then
        sudo ufw allow syncthing
    else
        sudo ufw allow 22000/tcp && sudo ufw allow 22000/udp && sudo ufw allow 21027/udp
    fi
    # OrcaSlicer: Bambu Lab printers announce themselves over SSDP on UDP 1990
    # and 2021 (Bambu wiki, "printer network ports"); the slicer must receive
    # these to discover the printer. All other printer traffic (MQTT 8883, FTP
    # 990, camera) is opened by the slicer itself, so it needs no rule.
    #
    printf '[OrcaSlicer]\ntitle=OrcaSlicer\ndescription=Bambu Lab printer discovery (SSDP)\nports=1990,2021/udp\n' \
        | sudo tee /etc/ufw/applications.d/orcaslicer >/dev/null
    sudo ufw allow OrcaSlicer
    # LocalSend: discovery (UDP multicast) and transfers (HTTP) both use 53317.
    # A named app profile, so `ufw status` shows "LocalSend" instead of a bare port.
    printf '[LocalSend]\ntitle=LocalSend\ndescription=LocalSend file sharing\nports=53317\n' \
        | sudo tee /etc/ufw/applications.d/localsend >/dev/null
    sudo ufw allow LocalSend
    # WiVRn (desktop only): the same profile + rule the WiVRn dashboard's
    # "fix firewall" button creates (dashboard/firewall.cpp). The dashboard checks
    # for this exact file, so it won't ask to fix the firewall again.
    printf '[WiVRn]\ntitle=WiVRn server\ndescription=WiVRn OpenXR streaming server\nports=9757\n' \
        | sudo tee /etc/ufw/applications.d/wivrn >/dev/null
    sudo ufw allow wivrn
    # Turn the firewall on now and at every boot (--force skips the
    # "may disrupt SSH connections" prompt). Safe to run when already enabled.
    sudo ufw --force enable || warn "could not enable ufw"
    sudo systemctl enable --now ufw.service || warn "could not enable ufw.service"
fi

# Create directories for mounting disks
sudo mkdir -p /media/TrueNAS

# Add home directories
xdg-user-dirs-update

# Make the folders in /media writable for you. They're handed to your user
# instead of chmod 777, which let every account and service write to them.
for _d in /media /media/Games /media/Recordings /media/Data /media/Backup; do
    [[ -d "$_d" ]] && sudo chown "$USER:" "$_d"
done

# Copy .config folder and .zshrc
mkdir -p "$HOME/.config"
cp -r "$PROFILE_DIR/.config/." "$HOME/.config/"
cp "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"

# Make the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/swaync/scripts/*.sh \
         "$HOME"/.config/rofi/launchers/type-2/launcher.sh

# === Post install: kernel, boot and tuning, then the YubiKey setup ===
# Both run as root (sudo is still active from the start of this script). Each one
# runs even if the other reports a failure, and nothing reboots on its own:
# reboot at the end.
POST_DIR="$PROFILE_DIR/../Post Install"

echo
echo "== Apps and configs done. Next: run-all-desktop.sh (kernel, boot, tuning) =="
if sudo "$POST_DIR/run-all-desktop.sh"; then
    POST_RESULT="done"
else
    POST_RESULT="finished with failures (see its summary above)"
fi

echo
echo "== Next: yubikey-setup.sh (every step asks first; answer N to skip it) =="
if sudo "$POST_DIR/yubikey-setup.sh"; then
    YUBIKEY_RESULT="done"
else
    YUBIKEY_RESULT="finished with failures (see above)"
fi

echo
echo "== Setup finished =="
if [[ $WARNINGS -gt 0 ]]; then
    INSTALL_RESULT="done, with $WARNINGS warning(s) (see above)"
else
    INSTALL_RESULT="done"
fi
printf '  %-22s %s\n' "Install.sh:" "$INSTALL_RESULT" \
    "run-all-desktop.sh:" "$POST_RESULT" \
    "yubikey-setup.sh:" "$YUBIKEY_RESULT"
echo "Reboot now to start the CachyOS kernel and apply everything."
