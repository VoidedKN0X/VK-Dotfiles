#!/bin/bash
# Install.sh - Steam Deck profile (LCD Steam Deck used as a Hyprland tablet)
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-steamdeck.sh" (kernel, boot, tuning)
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
    brightnessctl
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
    gamescope
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
    wallust-git
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

# Steam, Wine and the lib32-* packages come from the multilib repo: enable it
# if it isn't yet (uncomment the stock block, or add it if it's missing)
if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
    if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
    fi
fi

# CachyOS repos first (official installer, as root), so the apps below are
# installed as CachyOS builds right away. Added later, the installer's own
# `pacman -Syu` would download and reinstall almost every app a second time to
# switch it to the CachyOS build. Stop here if it fails: installing everything
# from the Arch repos and switching later is exactly that slow path.
POST_DIR="$PROFILE_DIR/../Post Install"
sudo "$POST_DIR/cachyos-repo.sh" || { echo "CachyOS repo setup failed, stopping." >&2; exit 1; }

# Install apps from pacman (stop here if this fails: everything below depends on it).
# -Syu also refreshes the package lists (needed after enabling multilib) and avoids
# installing onto an out-of-date system (a partial upgrade).
sudo pacman -Syu --needed "${PACMAN_PKGS[@]}" || { echo "pacman install failed, stopping." >&2; exit 1; }

# === Memory: close the biggest app instead of freezing (earlyoom) ===
# Written after the pacman install: earlyoom's package owns this file, so a
# copy written before it is installed makes pacman refuse the whole install.
# When free memory AND free swap (zram) both drop below 10%, earlyoom closes
# the single process using the most memory - usually the game or app that
# filled it - before the system locks up. The desktop itself (Hyprland, bar,
# notifications, login) is never picked (--ignore).
# -r 0: no memory reports in the journal. (No quotes around the regex: the
# service passes it on word by word, quotes would become part of it.)
echo 'EARLYOOM_ARGS="-r 0 --ignore ^(Hyprland|start-hyprland|greetd|systemd|sshd|waybar|swaync)$"' \
    | sudo tee /etc/default/earlyoom >/dev/null

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
yay -S --needed "${AUR_ESSENTIAL_PKGS[@]}" || warn "some essential AUR packages failed to install"
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

# Remove leftover install files (orphaned deps such as make-dependencies, then caches).
# pacman lists the orphans and asks first: on a re-run the list can also hold
# optional dependencies you installed on purpose.
mapfile -t ORPHANS < <(pacman -Qdtq)
if [[ ${#ORPHANS[@]} -gt 0 ]]; then
    sudo pacman -Rns "${ORPHANS[@]}" || warn "orphan removal skipped or failed"
fi
yay -Sc --noconfirm || warn "cache cleanup failed"

# auto-cpufreq sets the CPU governor and power profile itself: stop and mask the
# other daemons that do the same (the CachyOS installer can add them), so they
# don't fight over it. Units that aren't installed are skipped.
for unit in power-profiles-daemon.service tuned.service tuned-ppd.service tlp.service; do
    systemctl list-unit-files "$unit" >/dev/null 2>&1 && sudo systemctl mask --now "$unit"
done

# Enable services one by one, so one missing unit doesn't skip all the others
for unit in "${SERVICES[@]}"; do
    sudo systemctl enable --now "$unit" || warn "could not enable $unit"
done
# Tailscale: lets you control it (and its tray icon) without sudo. Log in once
# from the tray icon, or with: tailscale up
sudo tailscale set --operator="$USER" || warn "could not make $USER the Tailscale operator"
# zsh's "command not found" names the package that has the command: it needs
# pkgfile's list of files, downloaded now and refreshed by pkgfile-update.timer
sudo pkgfile --update >/dev/null || warn "could not download the pkgfile database"
# greetd is only enabled, not started: starting it now would replace this session
# If another login screen (e.g. sddm) is enabled, display-manager.service already
# points to it and enabling greetd fails: switch it over to greetd.
if [[ "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" != */greetd.service ]]; then
    sudo systemctl disable display-manager.service 2>/dev/null
fi
sudo systemctl enable greetd.service || warn "could not enable greetd.service"

# === Login screen (greetd + tuigreet) ===
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd start-hyprland"
user = "greeter"

# Tablet: log in automatically at boot (no keyboard needed). tuigreet still
# appears after you log out.
[initial_session]
command = "start-hyprland"
user = "__USER__"
GREETD
sudo sed -i "s/__USER__/$USER/" /etc/greetd/config.toml

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
    # Tailscale: everything that comes in over the tailnet (your own devices) is
    # allowed; 41641/udp lets devices connect directly instead of via a relay
    sudo ufw allow in on tailscale0
    sudo ufw allow 41641/udp
    # Turn the firewall on now and at every boot (--force skips the
    # "may disrupt SSH connections" prompt). Safe to run when already enabled.
    sudo ufw --force enable || warn "could not enable ufw"
    sudo systemctl enable --now ufw.service || warn "could not enable ufw.service"
fi

# === Disk health warnings (smartd) ===
# smartd checks every disk every 30 minutes and runs a short self-test daily at
# 12:00. On a problem (failing health check, bad sectors, self-test or error log
# entries, over 70 °C) it runs smartd-notify, which shows a critical notification
# in your session: by default smartd only emails root, and Arch has no mail set
# up. "-n standby" skips disks that are spun down instead of waking them.
sudo tee /etc/smartd.conf >/dev/null <<'SMARTD'
# Written by Install.sh (VK-Dotfiles)
DEVICESCAN -a -n standby,24,q -s S/../.././12 -W 0,0,70 -m <nomailer> -M exec /usr/local/bin/smartd-notify
SMARTD
sudo tee /usr/local/bin/smartd-notify >/dev/null <<'NOTIFY'
#!/bin/sh
# Run by smartd (as root), with SMARTD_DEVICE, SMARTD_FAILTYPE and SMARTD_MESSAGE
# set. Sends the warning to every logged-in user's notification center.
for bus in /run/user/*/bus; do
    [ -S "$bus" ] || continue
    uid="${bus#/run/user/}"; uid="${uid%/bus}"
    [ "$uid" -ge 1000 ] || continue
    user="$(id -nu "$uid" 2>/dev/null)" || continue
    runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
        notify-send -u critical -a smartd -i drive-harddisk \
        "Disk problem on $SMARTD_DEVICE" "$SMARTD_FAILTYPE: $SMARTD_MESSAGE"
done
NOTIFY
sudo chmod 755 /usr/local/bin/smartd-notify
sudo systemctl enable smartd.service || warn "could not enable smartd.service"
# restart (not just start) so a re-run picks up the new config
sudo systemctl restart smartd.service || warn "could not start smartd.service"

# Create directories for mounting disks
sudo mkdir -p /media/TrueNAS

# Add home directories
xdg-user-dirs-update

# Copy .config folder and .zshrc. Files the desktop changes by itself are kept
# when they already exist, so running this again doesn't reset them: the chosen
# wallpaper, the colors wallust made from it, and settings apps save themselves.
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
    opencode/themes/wallust.json
    xfce4/xfconf/xfce-perchannel-xml/thunar.xml
    btop/btop.conf
)
mkdir -p "$HOME/.config"
KEEP_TMP="$(mktemp -d)"
for f in "${KEEP_IF_EXISTS[@]}"; do
    if [[ -e "$HOME/.config/$f" ]]; then
        mkdir -p "$KEEP_TMP/$(dirname "$f")" && cp -a "$HOME/.config/$f" "$KEEP_TMP/$f"
    fi
done
cp -r "$PROFILE_DIR/.config/." "$HOME/.config/"
cp -a "$KEEP_TMP/." "$HOME/.config/"
rm -rf "$KEEP_TMP"
# the kept bar position (top/left) also sets where the notification panel
# goes: write swaync's files to match it
"$HOME/.config/waybar/scripts/bar-position.sh" --files-only
cp "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"
# App entries that override the installed ones: hide helper apps from the
# launcher, and RapidRAW opens RAW photos passed to it (for mimeapps.list)
mkdir -p "$HOME/.local/share/applications"
cp -r "$PROFILE_DIR/.local/share/applications/." "$HOME/.local/share/applications/"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Thunar sidebar bookmarks (~/.config/gtk-3.0/bookmarks), built from $HOME so
# they work for any username. The folders are created if missing. An existing
# bookmarks file is kept: only missing lines are added, so running this again
# changes nothing.
BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
if mkdir -p "$HOME/.config/gtk-3.0" && touch "$BOOKMARKS"; then
    # make sure an existing file ends with a newline before adding lines
    [[ -s $BOOKMARKS && -n $(tail -c1 "$BOOKMARKS") ]] && echo >>"$BOOKMARKS"
    for dir in Documents Downloads Music Pictures; do
        mkdir -p "$HOME/$dir" || warn "could not create $HOME/$dir"
        # a line can also carry a label ("file:///home/me/Music My music")
        awk -v u="file://$HOME/$dir" '$1 == u { found = 1 } END { exit !found }' "$BOOKMARKS" ||
            echo "file://$HOME/$dir" >>"$BOOKMARKS" || warn "could not add $dir to $BOOKMARKS"
    done
else
    warn "could not create $BOOKMARKS (Thunar bookmarks)"
fi

# Make the scripts executable (no sudo needed: they're in your own home)
chmod +x "$HOME"/.config/hypr/scripts/*.sh \
         "$HOME"/.config/swaync/scripts/*.sh

# === Post install: kernel, boot and tuning, then the YubiKey setup ===
# Both run as root (sudo is still active from the start of this script). Each one
# runs even if the other reports a failure, and nothing reboots on its own:
# reboot at the end.

echo
echo "== Apps and configs done. Next: run-all-steamdeck.sh (kernel, boot, tuning) =="
if sudo "$POST_DIR/run-all-steamdeck.sh"; then
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
    "run-all-steamdeck.sh:" "$POST_RESULT" \
    "yubikey-setup.sh:" "$YUBIKEY_RESULT"
echo "Reboot now to start the CachyOS kernel and apply everything."
