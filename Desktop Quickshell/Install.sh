#!/bin/bash
# Install.sh - Desktop Quickshell profile (the Desktop profile with a
# Quickshell bar, control center and notifications instead of waybar + swaync)
# Run as your normal user (NOT with sudo); it asks for your password once at the
# start and keeps sudo active until the end.
# Works from any directory: paths are resolved relative to this script.
# When it's done it runs "Post Install/run-all-desktop.sh" (kernel, boot, tuning)
# and "Post Install/yubikey-setup.sh" (only the YubiKey parts you chose at the
# start: login and/or disk unlock), so this one file does the whole setup.
# Reboot once at the end.

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

# === YubiKey (optional): asked now, done at the very end ===
# Both are off unless you answer y. Your YubiKey(s) are needed at the end
# (touch them when they blink); the disk unlock also needs your LUKS passphrase.
YUBIKEY_ARGS=()
echo
read -rp "Use a YubiKey for login, sudo and the lock screen? [y/N] " _a
[[ "$_a" =~ ^[Yy] ]] && YUBIKEY_ARGS+=(--login)
read -rp "Unlock the encrypted disk with a YubiKey at boot? [y/N] " _a
[[ "$_a" =~ ^[Yy] ]] && YUBIKEY_ARGS+=(--disk)
unset _a

# === Packages (official repos) ===
PACMAN_PKGS=(
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
    otf-codenewroman-nerd
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
    calf
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
    auto-cpufreq
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
    auto-cpufreq.service
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
# filled it - before the system locks up. The desktop itself (Hyprland, the
# Quickshell bar + notifications, login) is never picked (--ignore).
# -r 0: no memory reports in the journal. (No quotes around the regex: the
# service passes it on word by word, quotes would become part of it.)
echo 'EARLYOOM_ARGS="-r 0 --ignore ^(Hyprland|start-hyprland|greetd|systemd|sshd|qs|quickshell)$"' \
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
# No questions about reviewing or cleaning each build (--answerdiff/--answerclean
# None); build-only dependencies are removed again afterwards (--removemake).
# yay still asks before installing.
YAY_FLAGS=(--needed --answerdiff None --answerclean None --removemake)
yay -S "${YAY_FLAGS[@]}" "${AUR_ESSENTIAL_PKGS[@]}" || warn "some essential AUR packages failed to install"
yay -S "${YAY_FLAGS[@]}" "${AUR_PKGS[@]}" || warn "some AUR packages failed to install"

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
# tuigreet on the text console, in the colors of your last wallpaper: wallust
# writes them to /var/lib/vk-greeter/palette (wallust/templates/
# console-palette.template) at every wallpaper change, and vk-tuigreet loads
# them into the console before tuigreet starts. The folder is yours (wallust
# runs as you), readable by the greeter.
sudo install -d -o "$USER" -g "$(id -gn)" -m 755 /var/lib/vk-greeter
# until the first wallpaper change: the colors this profile ships with
# (yours if you have them, else the ones in this profile)
colors_json="$HOME/.config/quickshell/colors.json"
[[ -f "$colors_json" ]] || colors_json="$PROFILE_DIR/.config/quickshell/colors.json"
if [[ ! -s /var/lib/vk-greeter/palette && -f "$colors_json" ]]; then
    for i in $(seq 0 15); do
        sed -n "s/.*\"color$i\": *\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$colors_json"
    done > /var/lib/vk-greeter/palette
fi
sudo tee /usr/local/bin/vk-tuigreet >/dev/null <<'TUIGREET'
#!/bin/sh
# tuigreet in the colors of the last wallpaper (installed by VK-Dotfiles),
# made pastel: a light touch instead of the wallpaper's full colors.
# The text console has 16 colors; ESC ] P <n> <rrggbb> sets color n
# (console_codes(4)). tuigreet's theme names those colors (magenta = the
# accent, wallust's color5), so they become the wallpaper's.
palette=/var/lib/vk-greeter/palette
if [ -r "$palette" ]; then
    # each color keeps its hue; saturation at most 45 %, lightness at least
    # 78 % (white: 90 %, dark gray for hints: 55 %). Color 0, the
    # background, is always black. A black and white wallpaper stays gray.
    awk '
    function h(s,   v, i) {
        v = 0; s = tolower(s)
        for (i = 1; i <= 2; i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
        return v / 255
    }
    function ch(p, q, t) {
        if (t < 0) t += 1
        if (t > 1) t -= 1
        if (t < 1 / 6) return p + (q - p) * 6 * t
        if (t < 1 / 2) return q
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
        return p
    }
    NR <= 16 && length($0) == 6 && $0 !~ /[^0-9A-Fa-f]/ {
        n = NR - 1
        if (n == 0) { printf "\033]P0000000"; next }
        r = h(substr($0, 1, 2)); g = h(substr($0, 3, 2)); b = h(substr($0, 5, 2))
        mx = r; if (g > mx) mx = g; if (b > mx) mx = b
        mn = r; if (g < mn) mn = g; if (b < mn) mn = b
        l = (mx + mn) / 2; d = mx - mn; s = 0; hue = 0
        if (d > 0) {
            s = d / (1 - (2 * l - 1 < 0 ? 1 - 2 * l : 2 * l - 1))
            if (mx == r) { hue = (g - b) / d; if (hue < 0) hue += 6 }
            else if (mx == g) hue = (b - r) / d + 2
            else hue = (r - g) / d + 4
            hue /= 6
        }
        if (s > 0.45) s = 0.45
        if (n == 8) l = 0.55
        else if (n == 15) { if (l < 0.9) l = 0.9 }
        else if (l < 0.78) l = 0.78
        q = l < 0.5 ? l * (1 + s) : l + s - l * s; p = 2 * l - q
        printf "\033]P%x%02x%02x%02x", n, int(ch(p, q, hue + 1 / 3) * 255 + 0.5), int(ch(p, q, hue) * 255 + 0.5), int(ch(p, q, hue - 1 / 3) * 255 + 0.5)
    }' "$palette"
fi
# clock on top, the last user and session filled in, a dot per password
# character, a thin box in the accent color
exec tuigreet \
    --time --time-format "%H:%M  ·  %a %d %b" \
    --greeting "$(cat /etc/hostname 2>/dev/null)" \
    --remember --remember-session \
    --asterisks --asterisks-char "•" \
    --window-padding 2 --container-padding 2 \
    --theme "border=magenta;text=gray;prompt=magenta;time=gray;greet=gray;action=darkgray;button=magenta;input=white" \
    --cmd start-hyprland
TUIGREET
sudo chmod 755 /usr/local/bin/vk-tuigreet
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/vk-tuigreet"
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

# Make the folders in /media writable for you. They're handed to your user
# instead of chmod 777, which let every account and service write to them.
for _d in /media /media/Games /media/Recordings /media/Data /media/Backup; do
    [[ -d "$_d" ]] && sudo chown "$USER:" "$_d"
done

# Copy .config folder and .zshrc. Files the desktop changes by itself are kept
# when they already exist, so running this again doesn't reset them: the chosen
# wallpaper, the colors wallust made from it, and settings apps save themselves.
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
cp "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"

# Lock screen: without the YubiKey login it unlocks with your password, so it
# gets a password field (hyprlock.conf has none: with the key there's nothing
# to type). Added once; yubikey-setup.sh --login removes the line again.
HYPRLOCK_PW_LINE='source = $HOME/.config/hypr/hyprlock-password.conf'
if [[ " ${YUBIKEY_ARGS[*]} " != *" --login "* ]] \
    && ! grep -qxF "$HYPRLOCK_PW_LINE" "$HOME/.config/hypr/hyprlock.conf"; then
    printf '\n# password field (no YubiKey login)\n%s\n' "$HYPRLOCK_PW_LINE" >>"$HOME/.config/hypr/hyprlock.conf" \
        || warn "could not add the password field to the lock screen"
fi
# App entries that override the installed ones: hide helper apps from the
# launcher (quickshell/popups/Launcher.qml reads them too), and RapidRAW opens
# RAW photos passed to it (for mimeapps.list)
mkdir -p "$HOME/.local/share/applications"
cp -r "$PROFILE_DIR/.local/share/applications/." "$HOME/.local/share/applications/"
# apps the GTK glass doesn't work in (LACT: no blur behind it; LibreWolf: its
# address bar suggestions had no background) start without it, through
# hypr/scripts/solid-gtk.sh: their own .desktop files with that in front of
# every command
for app in io.github.ilya_zlobintsev.LACT librewolf; do
    src="/usr/share/applications/$app.desktop"
    if [ -r "$src" ]; then
        sed "s|^Exec=|Exec=$HOME/.config/hypr/scripts/solid-gtk.sh |" "$src" \
            > "$HOME/.local/share/applications/$app.desktop"
    else
        warn "$src not found: $app keeps the GTK glass"
    fi
done
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# EasyEffects' presets (Soundbar Bass Boost, Earbuds Flat) and its autoload
# rules: which preset goes with which output (the soundbar on HDMI, the USB
# audio interface's speakers); presets with the same name are replaced
mkdir -p "$HOME/.local/share/easyeffects"
cp -r "$PROFILE_DIR/.local/share/easyeffects/." "$HOME/.local/share/easyeffects/"

# Prism Launcher's icons: the icon packs made for Prism Launcher (its official
# Themes repository: Fluent Dark, Ore UI, OSX, iOS, Twemoji) in Prism's own
# icon theme folder, with Fluent Dark picked in Prism's settings: flat, light
# line icons that fit the dark glass desktop (Settings > Appearance switches
# between them).
PRISM_DIR="$HOME/.local/share/PrismLauncher"
PRISM_TMP=$(mktemp -d)
if git clone -q --depth 1 https://github.com/PrismLauncher/Themes.git "$PRISM_TMP/themes" &&
    mkdir -p "$PRISM_DIR/iconthemes" &&
    cp -r "$PRISM_TMP/themes/icons/." "$PRISM_DIR/iconthemes/"; then
    # (the Papirus theme an earlier version of this script made)
    rm -rf "$PRISM_DIR/iconthemes/papirus"
    if grep -q '^IconTheme=' "$PRISM_DIR/prismlauncher.cfg" 2>/dev/null; then
        sed -i 's/^IconTheme=.*/IconTheme=Fluent-Dark/' "$PRISM_DIR/prismlauncher.cfg"
    else
        echo 'IconTheme=Fluent-Dark' >> "$PRISM_DIR/prismlauncher.cfg"
    fi
else
    warn "could not download Prism Launcher's icon packs"
fi
rm -rf "$PRISM_TMP"

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
         "$HOME"/.config/quickshell/scripts/*.sh

# Orchis for Qt apps: the Kvantum version of the GTK apps' Orchis theme
# (rounded, flat, modern buttons), from its author's repository
# (vinceliuice/Orchis-kde, GPL-3.0), into ~/.config/Kvantum/Orchis
if [[ ! -f "$HOME/.config/Kvantum/Orchis/OrchisDark.svg" ]]; then
    ORCHIS_TMP="$(mktemp -d)"
    if git clone -q --depth 1 https://github.com/vinceliuice/Orchis-kde.git "$ORCHIS_TMP/orchis-kde" &&
        mkdir -p "$HOME/.config/Kvantum" &&
        cp -r "$ORCHIS_TMP/orchis-kde/Kvantum/Orchis" "$HOME/.config/Kvantum/"; then
        echo "Orchis Kvantum theme installed"
    else
        warn "could not download the Orchis Kvantum theme (Qt apps use KvArcDark instead)"
    fi
    rm -rf "$ORCHIS_TMP"
fi

# Frosted glass for Qt apps: the Kvantum theme in the current colors (it's
# made again at every wallpaper change)
"$HOME/.config/hypr/scripts/kvantum-glass.sh" || warn "could not set up the Kvantum glass theme"

# === Post install: kernel, boot and tuning, then the YubiKey setup (if chosen) ===
# Both run as root (sudo is still active from the start of this script). Each one
# runs even if the other reports a failure, and nothing reboots on its own:
# reboot at the end.

echo
echo "== Apps and configs done. Next: run-all-desktop.sh (kernel, boot, tuning) =="
if sudo "$POST_DIR/run-all-desktop.sh"; then
    POST_RESULT="done"
else
    POST_RESULT="finished with failures (see its summary above)"
fi

if [[ ${#YUBIKEY_ARGS[@]} -eq 0 ]]; then
    YUBIKEY_RESULT="skipped (not chosen at the start)"
else
    echo
    echo "== Next: yubikey-setup.sh ${YUBIKEY_ARGS[*]} (have your YubiKey(s) at hand) =="
    if sudo "$POST_DIR/yubikey-setup.sh" "${YUBIKEY_ARGS[@]}"; then
        YUBIKEY_RESULT="done"
    else
        YUBIKEY_RESULT="finished with failures (see above)"
    fi
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
