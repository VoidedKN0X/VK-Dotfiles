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
# AUR builds and the post-install steps don't ask again
sudo -v || { echo "This script needs sudo." >&2; exit 1; }
while sleep 60; do sudo -n true || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

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

    # Hyprland and its lock screen, idle timers and password prompts
    hyprland
    hyprlock
    hypridle
    hyprpolkitagent
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    qt5-wayland
    qt6-wayland
    gnome-keyring

    # login screen
    greetd
    greetd-tuigreet

    # the bar, its popups and the notification center
    waybar
    swaync
    libnotify
    playerctl
    # wpctl: the volume keys (hypr/scripts/osd.sh)
    wireplumber
    cava
    # calendar, music, power menu and volume popups (waybar/scripts/*.py)
    python-gobject
    gtk4-layer-shell
    # brightness keys and the dimming in hypridle.conf (no-op without a backlight)
    brightnessctl
    # battery in the bar and on the lock screen (hidden without a battery)
    upower

    # launcher, terminal, wallpaper, clipboard, screenshots
    rofi
    foot
    awww
    cliphist
    wl-clipboard
    grim
    flameshot

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
    pavucontrol
    blueman
    bluez
    bluez-utils
    # Wi-Fi/network: the swaync Wi-Fi button and the bar (nmcli, nmtui)
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
    adwaita-fonts
    noto-fonts
    noto-fonts-emoji
    ttf-ubuntu-font-family
    ttf-nerd-fonts-symbols
    ttf-jetbrains-mono-nerd
    otf-geist-mono-nerd
    otf-codenewroman-nerd

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
    wallust-git
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

# multilib: the 32-bit packages Steam, the gaming extras and 32-bit drivers
# need. Enable it if it isn't yet (uncomment the stock block, or add it if
# it's missing)
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
# -Syu also refreshes the package lists and avoids installing onto an
# out-of-date system (a partial upgrade).
sudo pacman -Syu --needed "${PACMAN_PKGS[@]}" || { echo "pacman install failed, stopping." >&2; exit 1; }

# === Memory: close the biggest app instead of freezing (earlyoom) ===
# Written after the pacman install: earlyoom's package owns this file, so a
# copy written before it is installed makes pacman refuse the whole install.
# When free memory AND free swap both drop below 10%, earlyoom closes the
# single process using the most memory before the system locks up. The desktop
# itself (Hyprland, bar, notifications, login) is never picked (--ignore).
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
yay -S --needed "${AUR_PKGS[@]}" || warn "some AUR packages failed to install"

# === Shell (as your user) ===
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
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd start-hyprland"
user = "greeter"
GREETD

# === Firewall (ufw) ===
# Blocks everything that comes in unless you allow it (ufw's default). Add
# rules for your own apps with `sudo ufw allow <port or app>`.
if command -v ufw >/dev/null; then
    # --force skips the "may disrupt SSH connections" prompt. Safe to run when
    # already enabled.
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

# Add home directories (Documents, Downloads, Pictures, ...)
xdg-user-dirs-update
# the wallpaper picker (Super + Shift + W) looks here
mkdir -p "$HOME/Pictures/Wallpapers"

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
    hypr/hyprland/border-colors.lua
    hypr/colors/hyprlock-colors.conf
    btop/themes/wallust.theme
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
# An existing .zshrc that isn't this one is kept as .zshrc.bak first
if [[ -f "$HOME/.zshrc" ]] && ! cmp -s "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.bak" && echo "Your old .zshrc is saved as ~/.zshrc.bak"
fi
cp "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"
# App entries that override the installed ones: hide helper apps (settings
# tools, foot server, ...) from the launcher
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
         "$HOME"/.config/swaync/scripts/*.sh \
         "$HOME"/.config/waybar/scripts/*.sh \
         "$HOME"/.config/waybar/scripts/*.py \
         "$HOME"/.config/rofi/launchers/type-2/launcher.sh

# === Post install: CachyOS kernel, boot splash and tuning ===
# Runs as root (sudo is still active from the start of this script). Nothing
# reboots on its own: reboot at the end.
echo
echo "== Apps and configs done. Next: run-all-clean.sh (kernel, boot, tuning) =="
if sudo "$POST_DIR/run-all-clean.sh" "$GAMING_FLAG"; then
    POST_RESULT="done"
else
    POST_RESULT="finished with failures (see its summary above)"
fi

echo
echo "== Setup finished =="
if [[ $WARNINGS -gt 0 ]]; then
    INSTALL_RESULT="done, with $WARNINGS warning(s) (see above)"
else
    INSTALL_RESULT="done"
fi
printf '  %-22s %s\n' "Install.sh:" "$INSTALL_RESULT" \
    "run-all-clean.sh:" "$POST_RESULT"
echo "Put some wallpapers in ~/Pictures/Wallpapers, then reboot to start the"
echo "CachyOS kernel. After logging in, pick a wallpaper with Super + Shift + W."
