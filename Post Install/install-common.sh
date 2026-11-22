#!/bin/bash
# install-common.sh - the steps every profile's Install.sh shares, as
# functions. Not run on its own: each profile's Install.sh sets its package
# lists and settings, sources this file and calls the steps it needs, in order.
#
# What a profile sets before calling the steps (all optional unless noted):
#   PROFILE_DIR       the profile's folder (required; set by vk_init)
#   PACMAN_PKGS       official-repo packages (required)
#   AUR_ESSENTIAL_PKGS  AUR packages the desktop itself needs (installed first,
#                     on their own, so a failed big build can't leave them out)
#   AUR_PKGS          the other AUR packages
#   SERVICES          units enabled and started
#   KEEP_IF_EXISTS    files in ~/.config the desktop rewrites itself (colors,
#                     wallpaper, bar position): kept when the configs are copied

POST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WARNINGS=0
warn() { echo "WARNING: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
# hw_cpu_vendor, hw_gpu_vendors, hw_nvidia_supported, hw_is_laptop
# shellcheck source=hw-detect.sh
source "$POST_DIR/hw-detect.sh"

# ── start ─────────────────────────────────────────────────────────────────

# Run as your normal user; ask for the password once and keep sudo active in
# the background, so the long AUR builds and the post-install steps don't ask
# again. $USER is used for services and file ownership.
vk_init() {
    if [[ $EUID -eq 0 ]]; then
        echo "Run this as your normal user, not as root/sudo." >&2
        exit 1
    fi
    USER="${USER:-$(id -un)}"
    sudo -v || { echo "This script needs sudo." >&2; exit 1; }
    while sleep 60; do sudo -n true || exit; done 2>/dev/null &
    SUDO_KEEPALIVE=$!
    trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT
}

# YubiKey (optional): asked now, done at the very end (vk_yubikey). Both are
# off unless you answer y. Your YubiKey(s) are needed at the end (touch them
# when they blink); the disk unlock also needs your LUKS passphrase.
YUBIKEY_ARGS=()
vk_ask_yubikey() {
    local a
    echo
    read -rp "Use a YubiKey for login, sudo and the lock screen? [y/N] " a
    [[ "$a" =~ ^[Yy] ]] && YUBIKEY_ARGS+=(--login)
    read -rp "Unlock the encrypted disk with a YubiKey at boot? [y/N] " a
    [[ "$a" =~ ^[Yy] ]] && YUBIKEY_ARGS+=(--disk)
}

# ── packages ──────────────────────────────────────────────────────────────

# multilib: Steam, Wine and the lib32-* packages (32-bit drivers) come from
# it. Enable it if it isn't yet (uncomment the stock block, or add it).
vk_enable_multilib() {
    if ! grep -qE '^\[multilib\]' /etc/pacman.conf; then
        if grep -qE '^#\[multilib\]' /etc/pacman.conf; then
            sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        else
            printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
        fi
    fi
}

# CachyOS repos first (official installer, as root), so the apps are installed
# as CachyOS builds right away. Added later, the installer's own `pacman -Syu`
# would download and reinstall almost every app a second time to switch it to
# the CachyOS build. Stops here if it fails: installing everything from the
# Arch repos and switching later is exactly that slow path.
vk_cachyos_repos() {
    sudo "$POST_DIR/cachyos-repo.sh" || { echo "CachyOS repo setup failed, stopping." >&2; exit 1; }
}

# The official-repo apps (stops here if this fails: everything after it
# depends on it). -Syu also refreshes the package lists (needed after enabling
# multilib) and avoids installing onto an out-of-date system (a partial
# upgrade).
# Graphics drivers for the chips this PC has (detected, see hw-detect.sh),
# added to PACMAN_PKGS before vk_install_pacman; "lib32": also the 32-bit
# ones (Steam and Wine games).
# - AMD: Vulkan (RADV); OpenGL and video decoding are in mesa already
# - Intel: Vulkan (ANV) and video decoding (intel-media-driver, Broadwell and
#   newer)
# - NVIDIA, GTX 16 / RTX 20 and newer: the driver's libraries and its VA-API
#   video decoding; the kernel module comes with the CachyOS kernel
#   (run-all-common.sh adds linux-cachyos-nvidia-open), and vk_nvidia_sleep
#   sets up sleep. A laptop with built-in graphics plus NVIDIA: also
#   prime-run (nvidia-prime) to start a game on the NVIDIA card; the desktop
#   itself stays on the built-in chip, which drives the screen (battery). Not
#   on a desktop PC, even when its CPU has built-in graphics too (Ryzen
#   7000+, most Intel): there the monitors are on the NVIDIA card, which is
#   the main one.
# - NVIDIA, GTX 10 and older: the current driver no longer supports them, so
#   the open-source driver (nouveau, with NVK for Vulkan) stays; the legacy
#   proprietary one is nvidia-580xx-dkms in the AUR, to install yourself.
# Intel laptops also get thermald (Intel's thermal daemon: cools before the
# CPU has to throttle hard), added to SERVICES.
vk_hw_drivers() {
    local lib32=${1:-} vendors
    vendors=$(hw_gpu_vendors)
    if grep -qx amd <<<"$vendors"; then
        PACMAN_PKGS+=(vulkan-radeon)
        [[ $lib32 == lib32 ]] && PACMAN_PKGS+=(lib32-vulkan-radeon)
    fi
    if grep -qx intel <<<"$vendors"; then
        PACMAN_PKGS+=(vulkan-intel intel-media-driver)
        [[ $lib32 == lib32 ]] && PACMAN_PKGS+=(lib32-vulkan-intel)
    fi
    if grep -qx nvidia <<<"$vendors"; then
        if hw_nvidia_supported; then
            PACMAN_PKGS+=(nvidia-utils libva-nvidia-driver)
            [[ $lib32 == lib32 ]] && PACMAN_PKGS+=(lib32-nvidia-utils)
            grep -qxE 'amd|intel' <<<"$vendors" && hw_is_laptop && PACMAN_PKGS+=(nvidia-prime)
        else
            PACMAN_PKGS+=(vulkan-nouveau)
            [[ $lib32 == lib32 ]] && PACMAN_PKGS+=(lib32-vulkan-nouveau)
            warn "older NVIDIA card (GTX 10 or older): the open-source driver stays; for NVIDIA's own, install nvidia-580xx-dkms from the AUR"
        fi
    fi
    [[ -z $vendors ]] && warn "no graphics chip found: no graphics drivers added"
    if hw_is_laptop && [[ $(hw_cpu_vendor) == intel ]]; then
        PACMAN_PKGS+=(thermald)
        SERVICES+=(thermald.service)
    fi
}

# NVIDIA and sleep: the driver keeps the graphics memory in RAM while asleep
# (else apps and the desktop lose it and show garbage after waking), with its
# suspend/hibernate/resume services. Only when the NVIDIA driver is installed
# (vk_hw_drivers); enabled, not started (starting them prepares a suspend).
vk_nvidia_sleep() {
    pacman -Q nvidia-utils >/dev/null 2>&1 || return 0
    echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" |
        sudo tee /etc/modprobe.d/nvidia-sleep.conf >/dev/null
    sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service ||
        warn "could not enable NVIDIA's sleep services"
}

vk_install_pacman() {
    sudo pacman -Syu --needed "${PACMAN_PKGS[@]}" || { echo "pacman install failed, stopping." >&2; exit 1; }
}

# Memory: close the biggest app instead of freezing (earlyoom). Written after
# the pacman install: earlyoom's package owns this file, so a copy written
# before it is installed makes pacman refuse the whole install.
# When free memory AND free swap (zram) both drop below 10%, earlyoom closes
# the single process using the most memory - usually the game or app that
# filled it - before the system locks up. The desktop itself (Hyprland, login
# and the bar / notifications named in $1, e.g. "qs|quickshell") is never
# picked (--ignore). -r 0: no memory reports in the journal. (No quotes around
# the regex: the service passes it on word by word, quotes would become part
# of it.)
vk_earlyoom() {
    echo "EARLYOOM_ARGS=\"-r 0 --ignore ^(Hyprland|start-hyprland|greetd|systemd|sshd|$1)\$\"" \
        | sudo tee /etc/default/earlyoom >/dev/null
}

# yay (skipped if it's already installed), built in a temp dir; then the AUR
# apps. A failed AUR build doesn't stop the rest. No questions about reviewing
# or cleaning each build (--answerdiff/--answerclean None); build-only
# dependencies are removed again afterwards (--removemake). yay still asks
# before installing.
vk_install_aur() {
    if ! command -v yay >/dev/null; then
        local tmp
        tmp="$(mktemp -d)"
        if git clone https://aur.archlinux.org/yay.git "$tmp/yay" && (cd "$tmp/yay" && makepkg -si); then
            rm -rf "$tmp"
        else
            rm -rf "$tmp"
            echo "yay install failed, stopping." >&2
            exit 1
        fi
    fi
    local flags=(--needed --answerdiff None --answerclean None --removemake)
    if [[ ${#AUR_ESSENTIAL_PKGS[@]} -gt 0 ]]; then
        yay -S "${flags[@]}" "${AUR_ESSENTIAL_PKGS[@]}" || warn "some essential AUR packages failed to install"
    fi
    if [[ ${#AUR_PKGS[@]} -gt 0 ]]; then
        yay -S "${flags[@]}" "${AUR_PKGS[@]}" || warn "some AUR packages failed to install"
    fi
}
AUR_ESSENTIAL_PKGS=()
AUR_PKGS=()

# The Belgian eID middleware and viewer (AUR: eid-mw), built by its own script
# with a temporary fix: the AUR version doesn't build against OpenSSL 4.0 yet
# (see "Post Install/eid-mw.sh"). Skipped when it's already installed.
vk_eid_mw() {
    "$POST_DIR/eid-mw.sh" || warn "eid-mw (Belgian eID) failed to install; run \"Post Install/eid-mw.sh\" again later"
}

# Oh My Zsh (as your user): --keep-zshrc so the installer never replaces your
# .zshrc with its template, --unattended so it doesn't stop to ask questions.
# The installer refuses to run if ~/.oh-my-zsh exists, so it's skipped then.
# Downloaded to a file first, so a failed download is reported as a failure.
# --unattended doesn't change the login shell, so that's done here.
vk_oh_my_zsh() {
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        local installer
        installer="$(mktemp)"
        if curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer"; then
            sh "$installer" --unattended --keep-zshrc || warn "Oh My Zsh install failed"
        else
            warn "Oh My Zsh download failed"
        fi
        rm -f "$installer"
    fi
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]]; then
        sudo chsh -s /usr/bin/zsh "$USER" || warn "could not set zsh as login shell"
    fi
}

# Leftover install files: orphaned dependencies (make-dependencies), then the
# package caches. pacman lists the orphans and asks first: on a re-run the
# list can also hold optional dependencies you installed on purpose.
vk_cleanup() {
    local orphans
    mapfile -t orphans < <(pacman -Qdtq)
    if [[ ${#orphans[@]} -gt 0 ]]; then
        sudo pacman -Rns "${orphans[@]}" || warn "orphan removal skipped or failed"
    fi
    yay -Sc --noconfirm || warn "cache cleanup failed"
}

# ── services ──────────────────────────────────────────────────────────────

# auto-cpufreq sets the CPU governor and power profile itself: stop and mask
# the other daemons that do the same (the CachyOS installer can add them), so
# they don't fight over it. Units that aren't installed are skipped.
vk_mask_power_daemons() {
    local unit
    for unit in power-profiles-daemon.service tuned.service tuned-ppd.service tlp.service; do
        systemctl list-unit-files "$unit" >/dev/null 2>&1 && sudo systemctl mask --now "$unit"
    done
}

# auto-cpufreq's settings (/etc/auto-cpufreq.conf), made for this hardware:
# - on AC: the most performance: governor performance, energy preference
#   performance, boost always on; the firmware's "performance" profile when
#   the laptop has one (higher power limits and fan speeds, e.g. Asus'
#   Performance mode); Intel: energy bias performance and HWP dynamic boost
# - on battery: the longest battery life: governor powersave, energy
#   preference power, boost off (the CPU stays at its base clock: noticeably
#   slower under load, but much cooler and longer on battery); the
#   firmware's low-power (or quiet) profile; Intel: energy bias power, no
#   dynamic boost
# The firmware profiles and Intel's settings are only written when this PC
# has them (/sys/firmware/acpi/platform_profile_choices,
# /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost), so auto-cpufreq
# never tries one that isn't there. auto-cpufreq checks the power source
# every few seconds and switches.
vk_auto_cpufreq() {
    local choices ac_profile="" bat_profile="" p intel=0 hwp=0
    # one profile name per line (exact names: "balanced-performance" isn't
    # "performance")
    choices=$(tr ' ' '\n' 2>/dev/null </sys/firmware/acpi/platform_profile_choices)
    grep -qx performance <<<"$choices" && ac_profile=performance
    for p in low-power quiet cool; do grep -qx "$p" <<<"$choices" && bat_profile=$p && break; done
    [[ $(hw_cpu_vendor) == intel ]] && intel=1
    [[ -e /sys/devices/system/cpu/intel_pstate/hwp_dynamic_boost ]] && hwp=1
    {
        echo "# auto-cpufreq: the most performance on AC, the longest battery life on"
        echo "# battery (written by VK-Dotfiles' install, vk_auto_cpufreq, for this PC)"
        echo
        echo "[charger]"
        echo "governor = performance"
        echo "energy_performance_preference = performance"
        [[ $intel -eq 1 ]] && echo "energy_perf_bias = performance"
        [[ $hwp -eq 1 ]] && echo "hwp_dynamic_boost = 1"
        [[ -n $ac_profile ]] && echo "platform_profile = $ac_profile"
        echo "turbo = always"
        echo
        echo "[battery]"
        echo "governor = powersave"
        echo "energy_performance_preference = power"
        [[ $intel -eq 1 ]] && echo "energy_perf_bias = power"
        [[ $hwp -eq 1 ]] && echo "hwp_dynamic_boost = 0"
        [[ -n $bat_profile ]] && echo "platform_profile = $bat_profile"
        echo "turbo = never"
    } | sudo tee /etc/auto-cpufreq.conf >/dev/null
    systemctl is-active --quiet auto-cpufreq.service && sudo systemctl restart auto-cpufreq.service
    return 0
}

# The YubiKey's "touch me" panel (quickshell/services/YubiKey.qml): the
# detector's socket, for this user (a user service); the detector itself
# starts when the shell connects to it, and keeps running.
vk_touch_detector() {
    pacman -Q yubikey-touch-detector >/dev/null 2>&1 || return 0
    systemctl --user daemon-reload
    systemctl --user enable --now yubikey-touch-detector.socket ||
        warn "could not enable yubikey-touch-detector.socket (systemctl --user enable --now yubikey-touch-detector.socket)"
}

# Enable and start $SERVICES one by one, so one missing unit doesn't skip all
# the others. Then pkgfile's list of files, which zsh's "command not found"
# uses to name the package that has a command (refreshed by
# pkgfile-update.timer).
SERVICES=()
vk_enable_services() {
    local unit
    for unit in "${SERVICES[@]}"; do
        sudo systemctl enable --now "$unit" || warn "could not enable $unit"
    done
    sudo pkgfile --update >/dev/null || warn "could not download the pkgfile database"
}

# ── login screen (greetd + tuigreet) ──────────────────────────────────────

# $1: the greeter command ("" = plain tuigreet); AUTOLOGIN=1 logs you in
# automatically at boot (tuigreet still appears after you log out).
# greetd is only enabled, not started: starting it now would replace this
# session. If another login screen (e.g. sddm) is enabled,
# display-manager.service already points to it and enabling greetd fails:
# switch it over to greetd.
AUTOLOGIN=0
vk_greetd() {
    local cmd="${1:-tuigreet --cmd start-hyprland}"
    if [[ "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" != */greetd.service ]]; then
        sudo systemctl disable display-manager.service 2>/dev/null
    fi
    sudo systemctl enable greetd.service || warn "could not enable greetd.service"
    sudo mkdir -p /etc/greetd
    {
        printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "%s"\nuser = "greeter"\n' "$cmd"
        if [[ $AUTOLOGIN == 1 ]]; then
            printf '\n# Tablet: log in automatically at boot (no keyboard needed). tuigreet still\n'
            printf '# appears after you log out.\n[initial_session]\ncommand = "start-hyprland"\nuser = "%s"\n' "$USER"
        fi
    } | sudo tee /etc/greetd/config.toml >/dev/null
}

# tuigreet on the text console, in the colors of your last wallpaper, made
# pastel (/usr/local/bin/vk-tuigreet; pass it to vk_greetd). wallust writes the
# colors to /var/lib/vk-greeter/palette (wallust/templates/
# console-palette.template) at every wallpaper change, and vk-tuigreet loads
# them into the console before tuigreet starts. The folder is yours (wallust
# runs as you), readable by the greeter. Until the first wallpaper change it
# has the colors in $1 (a colors.json: yours if you have one, else the
# profile's).
vk_tuigreet_pastel() {
    local colors_json="$1" i
    sudo install -d -o "$USER" -g "$(id -gn)" -m 755 /var/lib/vk-greeter
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
}

# ── my network: NAS share and printer ─────────────────────────────────────

# TrueNAS share in /media/TrueNAS (added to fstab only if it isn't there yet)
vk_truenas() {
    local line='192.168.1.9:/mnt/Data/axel    /media/TrueNAS  nfs     noauto,user,_netdev,bg  0       0'
    if ! grep -Eq '^[^#]*[[:space:]]/media/TrueNAS[[:space:]]' /etc/fstab; then
        # shellcheck disable=SC1003  # $a\ appends a newline if the file lacks one
        sudo sed -i -e '$a\' /etc/fstab
        printf '\n# TrueNAS\n%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
        sudo systemctl daemon-reload
    fi
    sudo mkdir -p /media/TrueNAS
}

# Printer: driverless IPP Everywhere, no driver package needed
vk_printer() {
    if lpstat -p Canon_TS5350a >/dev/null 2>&1; then
        echo "Printer Canon_TS5350a already set up"
    elif ! sudo lpadmin -p Canon_TS5350a -E -v ipp://192.168.1.60/ipp/print -m everywhere; then
        warn "could not add the printer (is it switched on?). Rerun later with:"
        echo "  sudo lpadmin -p Canon_TS5350a -E -v ipp://192.168.1.60/ipp/print -m everywhere" >&2
    fi
}

# ── firewall (ufw) ────────────────────────────────────────────────────────

# Blocks everything that comes in, except the rules named as arguments:
#   syncthing   Syncthing (its app profile if it has one, else its ports)
#   orcaslicer  Bambu Lab printers announce themselves over SSDP on UDP 1990
#               and 2021 (Bambu wiki, "printer network ports"); the slicer must
#               receive these to discover the printer. All other printer
#               traffic (MQTT 8883, FTP 990, camera) is opened by the slicer.
#   localsend   LocalSend: discovery (UDP multicast) and transfers (HTTP) both
#               use 53317
#   wivrn       the same profile + rule the WiVRn dashboard's "fix firewall"
#               button creates (dashboard/firewall.cpp); the dashboard checks
#               for this exact file, so it won't ask to fix the firewall again
#   tailscale   everything that comes in over the tailnet (your own devices);
#               41641/udp lets devices connect directly instead of via a relay
#   kdeconnect  KDE Connect: your phone finds this PC and connects on
#               1714-1764 (TCP and UDP)
# Named app profiles, so `ufw status` shows the app instead of a bare port.
# archinstall normally installs ufw; it's installed here if it's missing.
vk_firewall() {
    if ! command -v ufw >/dev/null; then
        sudo pacman -S --needed --noconfirm ufw || warn "could not install ufw"
    fi
    command -v ufw >/dev/null || return
    local rule
    for rule in "$@"; do
        case "$rule" in
        syncthing)
            if sudo ufw app info syncthing >/dev/null 2>&1; then
                sudo ufw allow syncthing
            else
                sudo ufw allow 22000/tcp && sudo ufw allow 22000/udp && sudo ufw allow 21027/udp
            fi
            ;;
        orcaslicer)
            printf '[OrcaSlicer]\ntitle=OrcaSlicer\ndescription=Bambu Lab printer discovery (SSDP)\nports=1990,2021/udp\n' \
                | sudo tee /etc/ufw/applications.d/orcaslicer >/dev/null
            sudo ufw allow OrcaSlicer
            ;;
        localsend)
            printf '[LocalSend]\ntitle=LocalSend\ndescription=LocalSend file sharing\nports=53317\n' \
                | sudo tee /etc/ufw/applications.d/localsend >/dev/null
            sudo ufw allow LocalSend
            ;;
        wivrn)
            printf '[WiVRn]\ntitle=WiVRn server\ndescription=WiVRn OpenXR streaming server\nports=9757\n' \
                | sudo tee /etc/ufw/applications.d/wivrn >/dev/null
            sudo ufw allow wivrn
            ;;
        tailscale)
            sudo ufw allow in on tailscale0
            sudo ufw allow 41641/udp
            ;;
        kdeconnect)
            # (a file name of its own, so it never clashes with one a package
            # might ship)
            printf '[KDEConnect]\ntitle=KDE Connect\ndescription=KDE Connect phone link (discovery and transfers)\nports=1714:1764/tcp|1714:1764/udp\n' \
                | sudo tee /etc/ufw/applications.d/vk-kdeconnect >/dev/null
            sudo ufw allow KDEConnect
            ;;
        *) warn "unknown firewall rule: $rule" ;;
        esac
    done
    # on now and at every boot (--force skips the "may disrupt SSH
    # connections" prompt). Safe to run when already enabled.
    sudo ufw --force enable || warn "could not enable ufw"
    sudo systemctl enable --now ufw.service || warn "could not enable ufw.service"
}

# ── disk health warnings (smartd) ─────────────────────────────────────────

# smartd checks every disk every 30 minutes and runs a short self-test daily
# at 12:00. On a problem (failing health check, bad sectors, self-test or
# error log entries, over $1 °C, default 70) it runs smartd-notify, which shows
# a critical notification in your session: by default smartd only emails
# root, and Arch has no mail set up. "-n standby" skips disks that are spun
# down instead of waking them.
vk_smartd() {
    local max_temp="${1:-70}"
    printf '# Written by Install.sh (VK-Dotfiles)\nDEVICESCAN -a -n standby,24,q -s S/../.././12 -W 0,0,%s -m <nomailer> -M exec /usr/local/bin/smartd-notify\n' "$max_temp" \
        | sudo tee /etc/smartd.conf >/dev/null
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
}

# ── your home ─────────────────────────────────────────────────────────────

# Make the folders in /media writable for you (desktop drives). They're handed
# to your user instead of chmod 777, which let every account and service write
# to them.
vk_media_folders() {
    local d
    for d in /media /media/Games /media/Recordings /media/Data /media/Backup; do
        [[ -d "$d" ]] && sudo chown "$USER:" "$d"
    done
}

# Copy .config and .zshrc. The files in $KEEP_IF_EXISTS (the desktop changes
# them by itself: the chosen wallpaper, the colors wallust made from it,
# settings apps save themselves) are kept when they already exist, so running
# this again doesn't reset them. ZSHRC_BACKUP=1: an existing .zshrc that isn't
# this one is kept as .zshrc.bak first.
KEEP_IF_EXISTS=()
ZSHRC_BACKUP=0
vk_copy_configs() {
    local keep f
    mkdir -p "$HOME/.config"
    keep="$(mktemp -d)"
    for f in "${KEEP_IF_EXISTS[@]}"; do
        if [[ -e "$HOME/.config/$f" ]]; then
            mkdir -p "$keep/$(dirname "$f")" && cp -a "$HOME/.config/$f" "$keep/$f"
        fi
    done
    cp -r "$PROFILE_DIR/.config/." "$HOME/.config/"
    cp -a "$keep/." "$HOME/.config/"
    rm -rf "$keep"
    if [[ $ZSHRC_BACKUP == 1 && -f "$HOME/.zshrc" ]] && ! cmp -s "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"; then
        cp "$HOME/.zshrc" "$HOME/.zshrc.bak" && echo "Your old .zshrc is saved as ~/.zshrc.bak"
    fi
    cp "$PROFILE_DIR/.zshrc" "$HOME/.zshrc"
}

# KDE's color scheme (~/.config/kdeglobals): Breeze Dark. Apps made with KDE's
# Kirigami (the WiVRn dashboard, EasyEffects, Kdenlive, Partition Manager)
# take their colors from it instead of Kvantum, and without it they're light.
# Normal Qt apps keep the Kvantum glass. An existing kdeglobals is kept.
vk_kde_dark() {
    local scheme=/usr/share/color-schemes/BreezeDark.colors
    [[ -e "$HOME/.config/kdeglobals" ]] && return
    if [[ -r "$scheme" ]]; then
        cp "$scheme" "$HOME/.config/kdeglobals"
    else
        warn "$scheme not found (is breeze installed?): KDE apps stay light"
    fi
}

# GameMode (Feral) for games, with ~/.config/gamemode.ini and its hook
# (~/.config/gamemode/hook.sh, both copied with the configs):
# - you in the gamemode group: GameMode may raise a game's CPU priority (the
#   gamemode package allows nice -10 for that group)
# - "vk_gamemode x3d" (the desktop's 9950X3D): a udev rule lets the gamemode
#   group switch the CPU to prefer its 3D V-Cache CCD (amd_x3d_mode), at
#   every boot; the desktop's hook does that while a game runs. Skipped with
#   a warning if the CPU has no such setting (ACPI device AMDI0101).
# - Heroic, when it's set up already (running the install again): GameMode on
#   by default and for every installed game. A new install has no Heroic
#   settings yet, and making that file would lose Heroic's own defaults (its
#   Wine prefix folder), so there it's Heroic's Settings > Game Defaults >
#   Other > Use GameMode.
# Without gamemode (Clean without the gaming extras) its config isn't kept.
vk_gamemode() {
    if ! pacman -Q gamemode >/dev/null 2>&1; then
        rm -f "$HOME/.config/gamemode.ini" "$HOME/.config/gamemode/hook.sh"
        rmdir "$HOME/.config/gamemode" 2>/dev/null
        return 0
    fi
    if getent group gamemode >/dev/null; then
        id -nG "$USER" | tr ' ' '\n' | grep -qx gamemode ||
            sudo usermod -aG gamemode "$USER" || warn "could not add $USER to the gamemode group"
    else
        warn "no gamemode group: GameMode can't raise a game's priority"
    fi
    chmod +x "$HOME/.config/gamemode/hook.sh" 2>/dev/null

    local f
    if [[ ${1:-} == x3d ]] && ! compgen -G "/sys/bus/acpi/devices/AMDI0101:*" >/dev/null; then
        warn "this CPU has no 3D V-Cache setting (amd_x3d_mode): V-Cache switch skipped"
    elif [[ ${1:-} == x3d ]]; then
        sudo tee /etc/udev/rules.d/90-vk-x3d-mode.rules >/dev/null <<'EOF'
# Lets the gamemode group switch the 3D V-Cache preference (amd_x3d_mode:
# cache or frequency); the GameMode hook ~/.config/gamemode/hook.sh uses it.
ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="amd_x3d_vcache", RUN+="/usr/bin/chgrp gamemode /sys%p/amd_x3d_mode", RUN+="/usr/bin/chmod g+w /sys%p/amd_x3d_mode"
EOF
        sudo udevadm control --reload
        # now too, when the driver is loaded already (else from the next boot)
        for f in /sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode; do
            [[ -e $f ]] && sudo chgrp gamemode "$f" && sudo chmod g+w "$f"
        done
    fi

    local heroic="$HOME/.config/heroic"
    if [[ -f $heroic/config.json ]]; then
        if pgrep -x heroic >/dev/null; then
            warn "Heroic is running: GameMode not turned on in it (close it and run the install again)"
        elif ! python3 -I - "$heroic" <<'PY'; then
import glob, json, os, sys
d = sys.argv[1]
def edit(path, change):
    with open(path) as fh:
        data = json.load(fh)
    change(data)
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
edit(os.path.join(d, "config.json"),
     lambda data: data.setdefault("defaultSettings", {}).update(useGameMode=True))
def games(data):
    for value in data.values():
        if isinstance(value, dict):
            value["useGameMode"] = True
for path in glob.glob(os.path.join(d, "GamesConfig", "*.json")):
    edit(path, games)
PY
            warn "could not turn GameMode on in Heroic"
        fi
    fi
}

# Lock screen: without the YubiKey login it unlocks with your password, so it
# gets a password field (hyprlock.conf has none: with the key there's nothing
# to type). Added once; yubikey-setup.sh --login removes the line again.
vk_hyprlock_password() {
    # shellcheck disable=SC2016  # $HOME is for hyprlock, not the shell
    local line='source = $HOME/.config/hypr/hyprlock-password.conf'
    if [[ " ${YUBIKEY_ARGS[*]} " != *" --login "* ]] \
        && ! grep -qxF "$line" "$HOME/.config/hypr/hyprlock.conf"; then
        printf '\n# password field (no YubiKey login)\n%s\n' "$line" >>"$HOME/.config/hypr/hyprlock.conf" \
            || warn "could not add the password field to the lock screen"
    fi
}

# App entries that override the installed ones (.local/share/applications):
# hide helper apps from the launcher, and RapidRAW opens RAW photos passed to
# it (for mimeapps.list). The apps named as arguments start without the GTK
# glass, through hypr/scripts/solid-gtk.sh: their .desktop files (the
# profile's own if it has one, e.g. File Roller's hidden entry, else the
# app's) with that in front of every command.
vk_app_entries() {
    local app src
    mkdir -p "$HOME/.local/share/applications"
    cp -r "$PROFILE_DIR/.local/share/applications/." "$HOME/.local/share/applications/"
    for app in "$@"; do
        src="$PROFILE_DIR/.local/share/applications/$app.desktop"
        [[ -r "$src" ]] || src="/usr/share/applications/$app.desktop"
        if [[ -r "$src" ]]; then
            sed "s|^Exec=|Exec=$HOME/.config/hypr/scripts/solid-gtk.sh |" "$src" \
                > "$HOME/.local/share/applications/$app.desktop.tmp" &&
                mv "$HOME/.local/share/applications/$app.desktop.tmp" "$HOME/.local/share/applications/$app.desktop"
        else
            warn "$src not found: $app keeps the GTK glass"
        fi
    done
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
}

# EasyEffects' presets and autoload rules (which preset goes with which
# output), if the profile has them; presets with the same name are replaced
vk_easyeffects_presets() {
    [[ -d "$PROFILE_DIR/.local/share/easyeffects" ]] || return
    mkdir -p "$HOME/.local/share/easyeffects"
    cp -r "$PROFILE_DIR/.local/share/easyeffects/." "$HOME/.local/share/easyeffects/"
}

# Prism Launcher's look:
# - its icons: the icon packs made for Prism Launcher (its official Themes
#   repository: Fluent Dark, Ore UI, OSX, iOS, Twemoji) in Prism's own icon
#   theme folder, with Fluent Dark picked: flat, light line icons that fit the
#   dark desktop (Settings > Appearance switches between them)
# - its widget theme "System": the Qt style of the desktop (Kvantum, with the
#   frosted glass). Prism's own "Dark" / "Bright" themes and the plain Qt
#   styles bring their own solid colors, so its window has no glass then.
# Set in prismlauncher.cfg (key=value lines). Prism writes that file when it
# closes, so close Prism Launcher before running this.
vk_prism_icons() {
    local dir="$HOME/.local/share/PrismLauncher" tmp
    mkdir -p "$dir"
    tmp=$(mktemp -d)
    if git clone -q --depth 1 https://github.com/PrismLauncher/Themes.git "$tmp/themes" &&
        mkdir -p "$dir/iconthemes" &&
        cp -r "$tmp/themes/icons/." "$dir/iconthemes/"; then
        # (the Papirus theme an earlier version of this script made)
        rm -rf "$dir/iconthemes/papirus"
        vk_prism_set IconTheme Fluent-Dark
    else
        warn "could not download Prism Launcher's icon packs"
    fi
    rm -rf "$tmp"
    vk_prism_set ApplicationTheme system
}
# set a key in prismlauncher.cfg: replaced if it's there, else added on a line
# of its own (also when the file doesn't end with a newline)
vk_prism_set() {
    local cfg="$HOME/.local/share/PrismLauncher/prismlauncher.cfg"
    if grep -q "^$1=" "$cfg" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$cfg"
    else
        [[ -s "$cfg" && -n "$(tail -c1 "$cfg")" ]] && echo >>"$cfg"
        echo "$1=$2" >>"$cfg"
    fi
}

# Prism Launcher for performance (prismlauncher.cfg, close Prism first):
# - GameMode while Minecraft runs (~/.config/gamemode.ini)
# - Java arguments for every instance that doesn't set its own: G1 with short
#   pauses (Aikar's flags: they work on every Java Minecraft uses, 8 to 21+,
#   unlike ZGC's), huge pages where Java asks for them (THP is "madvise") and
#   the starting memory touched at launch instead of during play. Replaces
#   Prism's global Java arguments.
vk_prism_tune() {
    mkdir -p "$HOME/.local/share/PrismLauncher"
    vk_prism_set EnableFeralGamemode true
    vk_prism_set JvmArgs "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -XX:+UseTransparentHugePages"
}

# Thunar sidebar bookmarks (~/.config/gtk-3.0/bookmarks), built from $HOME so
# they work for any username. The folders are created if missing. An existing
# bookmarks file is kept: only missing lines are added, so running this again
# changes nothing.
vk_thunar_bookmarks() {
    local bookmarks="$HOME/.config/gtk-3.0/bookmarks" dir
    if mkdir -p "$HOME/.config/gtk-3.0" && touch "$bookmarks"; then
        # make sure an existing file ends with a newline before adding lines
        [[ -s $bookmarks && -n $(tail -c1 "$bookmarks") ]] && echo >>"$bookmarks"
        for dir in Documents Downloads Music Pictures; do
            mkdir -p "$HOME/$dir" || warn "could not create $HOME/$dir"
            # a line can also carry a label ("file:///home/me/Music My music")
            awk -v u="file://$HOME/$dir" '$1 == u { found = 1 } END { exit !found }' "$bookmarks" ||
                echo "file://$HOME/$dir" >>"$bookmarks" || warn "could not add $dir to $bookmarks"
        done
    else
        warn "could not create $bookmarks (Thunar bookmarks)"
    fi
}

# Orchis for Qt apps: the Kvantum version of the GTK apps' Orchis theme
# (rounded, flat, modern buttons), from its author's repository
# (vinceliuice/Orchis-kde, GPL-3.0), into ~/.config/Kvantum/Orchis; then the
# Kvantum glass theme in the current colors (made again at every wallpaper
# change).
vk_kvantum_glass() {
    if [[ ! -f "$HOME/.config/Kvantum/Orchis/OrchisDark.svg" ]]; then
        local tmp
        tmp="$(mktemp -d)"
        if git clone -q --depth 1 https://github.com/vinceliuice/Orchis-kde.git "$tmp/orchis-kde" &&
            mkdir -p "$HOME/.config/Kvantum" &&
            cp -r "$tmp/orchis-kde/Kvantum/Orchis" "$HOME/.config/Kvantum/"; then
            echo "Orchis Kvantum theme installed"
        else
            warn "could not download the Orchis Kvantum theme (Qt apps use KvArcDark instead)"
        fi
        rm -rf "$tmp"
    fi
    "$HOME/.config/hypr/scripts/kvantum-glass.sh" || warn "could not set up the Kvantum glass theme"
}

# ── post install and summary ──────────────────────────────────────────────

# Kernel, boot and tuning: "Post Install/$1" (with any further arguments), as
# root (sudo is still active). Runs even if something before it failed;
# nothing reboots on its own.
SUMMARY=()
vk_post() {
    local script="$1" result
    shift
    echo
    echo "== Apps and configs done. Next: $script (kernel, boot, tuning) =="
    if sudo "$POST_DIR/$script" "$@"; then
        result="done"
    else
        result="finished with failures (see its summary above)"
    fi
    SUMMARY+=("$script:" "$result")
}

# The YubiKey parts chosen at the start (vk_ask_yubikey), as root
vk_yubikey() {
    local result
    if [[ ${#YUBIKEY_ARGS[@]} -eq 0 ]]; then
        result="skipped (not chosen at the start)"
    else
        echo
        echo "== Next: yubikey-setup.sh ${YUBIKEY_ARGS[*]} (have your YubiKey(s) at hand) =="
        if sudo "$POST_DIR/yubikey-setup.sh" "${YUBIKEY_ARGS[@]}"; then
            result="done"
        else
            result="finished with failures (see above)"
        fi
    fi
    SUMMARY+=("yubikey-setup.sh:" "$result")
}

# What happened, one line per step; the arguments are printed after it
vk_summary() {
    local result="done"
    [[ $WARNINGS -gt 0 ]] && result="done, with $WARNINGS warning(s) (see above)"
    echo
    echo "== Setup finished =="
    printf '  %-22s %s\n' "Install.sh:" "$result" "${SUMMARY[@]}"
    local line
    for line in "$@"; do
        echo "$line"
    done
}
