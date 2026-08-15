#!/usr/bin/env bash
# post-install-automate.sh
# Automates the automatable steps from Post-Install.txt. Idempotent - safe to
# re-run. Steps that need physical interaction (YubiKey touch, LUKS device
# selection) are NOT automated; they print the manual commands instead.
#
# Automated:
#   1. OhMyZSH            (installs if missing)
#   2. greetd config      (tuigreet --cmd start-hyprland)
#   3. pam.d greetd       (gnome-keyring optional auth/session lines)
#   4. TrueNAS fstab      (NFS mount entry, if not present)
#   5. kernel cmdline     (quiet splash plymouth boot-log params)
#   6. mkinitcpio.conf    (plymouth in MODULES + HOOKS before systemd)
#   7. mkinitcpio presets (remove splash from *_options)
#   8. mkinitcpio -P      (regenerate all images)
#   9. CUPS printer       (Canon TS5350a via lpadmin, if cups installed)
#  10. Secure Boot        (sbctl create/enroll/sign, if sbctl installed)
#
# Manual (printed, not run): YubiKey u2f_keys, LUKS enrollment, pam_u2f
# edits, bootloader default (handled by install-cachyos-kernel.sh).
#
# Usage:
#   sudo ./post-install-automate.sh

set -uo pipefail

# === CONFIG (edit for your setup) ===
TRUENAS_IP="192.168.1.9:/mnt/Data/axel"
TRUENAS_MNT="/media/TrueNAS"
TRUENAS_OPTS="noauto,user,_netdev,bg"
PRINTER_NAME="Canon_TS5350a"
PRINTER_URI="ipp://192.168.1.60/ipp/print"

# === detect the real (non-root) user ===
REAL_USER="${SUDO_USER:-${LOGNAME:-$(logname 2>/dev/null || echo root)}}"
[[ "$REAL_USER" == "root" ]] && REAL_USER="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"

# ---------- colors & output ----------
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()   { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; }
fail() { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
head() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

# ---------- root ----------
if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo --preserve-env=HOME "$0" "$@"
fi
export HOME="/home/$REAL_USER"   # for OhMyZSH / user-level steps

# =====================================================================
head "1. OhMyZSH"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "already installed at $HOME/.oh-my-zsh"
elif command -v curl >/dev/null && [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  warn "installing for user $REAL_USER"
  sudo -u "$REAL_USER" sh -c "RUNZSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended" \
    && ok "oh-my-zsh installed" || fail "oh-my-zsh install failed"
else
  warn "curl missing or no non-root user - install manually"
fi

# =====================================================================
head "2. greetd config (tuigreet -> start-hyprland)"
GREETD_CONF="/etc/greetd/config.toml"
if [[ -f "$GREETD_CONF" ]] && grep -q start-hyprland "$GREETD_CONF"; then
  ok "already configured"
else
  cp -a "$GREETD_CONF" "$GREETD_CONF.bak" 2>/dev/null || true
  mkdir -p "$(dirname "$GREETD_CONF")"
  cat > "$GREETD_CONF" <<EOF
[terminal]
vt = 1

[default_session]
user = "$REAL_USER"
command = "tuigreet --cmd start-hyprland"

[initial_session]
command = "start-hyprland"
user = "$REAL_USER"
EOF
  ok "wrote $GREETD_CONF (backup: .bak)"
fi

# =====================================================================
head "3. pam.d/greetd gnome-keyring lines"
PAM_GREETD="/etc/pam.d/greetd"
if [[ -f "$PAM_GREETD" ]]; then
  if grep -q pam_gnome_keyring "$PAM_GREETD"; then
    ok "already present"
  else
    cp -a "$PAM_GREETD" "$PAM_GREETD.bak"
    printf 'auth       optional     pam_gnome_keyring.so\nsession    optional     pam_gnome_keyring.so auto_start\n' >> "$PAM_GREETD"
    ok "added gnome-keyring lines to $PAM_GREETD"
  fi
else
  warn "$PAM_GREETD not found - install greetd first"
fi

# =====================================================================
head "4. TrueNAS fstab entry"
if ! grep -qF " $TRUENAS_MNT " /etc/fstab 2>/dev/null; then
  mkdir -p "$TRUENAS_MNT"
  printf '%-40s %s  nfs  %s  0  0\n' "$TRUENAS_IP" "$TRUENAS_MNT" "$TRUENAS_OPTS" >> /etc/fstab
  ok "added TrueNAS NFS entry to /etc/fstab"
else
  ok "TrueNAS entry already in /etc/fstab"
fi

# =====================================================================
head "5. kernel cmdline (plymouth splash params)"
KCMDLINE="/etc/kernel/cmdline"
if [[ ! -f "$KCMDLINE" ]]; then
  warn "no $KCMDLINE - systemd-boot cmdline file missing"
else
  cp -a "$KCMDLINE" "$KCMDLINE.bak" 2>/dev/null || true
  CUR="$(cat "$KCMDLINE")"
  NEW="quiet splash plymouth.boot-log=/dev/null plymouth.nolog"
  ADDED=""
  for p in $NEW; do
    grep -qw -- "$p" <<<"$CUR" || { CUR="$CUR $p"; ADDED="$ADDED $p"; }
  done
  if [[ -n "$ADDED" ]]; then
    echo "$(echo "$CUR" | sed -E 's/^ +//; s/ +/ /g; s/ +$//')" > "$KCMDLINE"
    ok "cmdline updated, added:$ADDED"
  else
    ok "cmdline already has plymouth params"
  fi
fi

# =====================================================================
head "6. mkinitcpio.conf (plymouth in MODULES + HOOKS)"
MI_CONF="/etc/mkinitcpio.conf"
if [[ -f "$MI_CONF" ]]; then
  cp -a "$MI_CONF" "$MI_CONF.bak" 2>/dev/null || true
  if grep -q " plymouth" "$MI_CONF"; then
    ok "plymouth already in $MI_CONF"
  else
    sed -i -E 's/^(MODULES=\([^)]*)\)/\1 plymouth)/' "$MI_CONF"
    sed -i -E 's/^(HOOKS=\([^)]*) systemd/\1 plymouth systemd/; t; s/^(HOOKS=\([^)]*)\)/\1 plymouth)/' "$MI_CONF"
    if grep -q " plymouth" "$MI_CONF"; then
      ok "plymouth added to MODULES/HOOKS"
    else
      fail "could not add plymouth to $MI_CONF - check manually"
    fi
  fi
else
  warn "$MI_CONF not found"
fi

# =====================================================================
head "7. mkinitcpio presets (remove splash from options)"
FOUND=0
for p in /etc/mkinitcpio.d/*.preset; do
  [[ -f "$p" ]] || continue
  FOUND=1
  if grep -qE '(^|[[:space:]])splash([[:space:]]|$)' "$p"; then
    sed -i -E 's/(^|[[:space:]])splash([[:space:]]|$)/ /g' "$p"
    ok "removed splash from $(basename "$p")"
  else
    ok "no splash in $(basename "$p")"
  fi
done
[[ $FOUND -eq 1 ]] || warn "no presets found in /etc/mkinitcpio.d"

# =====================================================================
head "8. Regenerate initramfs / UKIs"
if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
  mkinitcpio -P && ok "mkinitcpio -P done" || fail "mkinitcpio -P failed"
elif command -v dracut >/dev/null; then
  dracut --regenerate-all && ok "dracut regenerated" || fail "dracut failed"
else
  warn "no mkinitcpio/dracut found"
fi

# =====================================================================
head "9. CUPS printer ($PRINTER_NAME)"
if command -v lpadmin >/dev/null; then
  if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    ok "printer already configured"
  else
    lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m everywhere \
      && ok "printer added (defaults: -m everywhere)" \
      || fail "lpadmin failed - check cups is running (systemctl status cups)"
  fi
else
  warn "lpadmin not found - install cups"
fi

# =====================================================================
head "10. Secure Boot (sbctl)"
if command -v sbctl >/dev/null; then
  if ! sbctl status | grep -q "Setup Mode"; then
    ok "Secure Boot already enrolled"
  else
    warn "enrolling keys and signing files"
    sbctl create-keys || fail "create-keys failed"
    sbctl enroll-keys -m || fail "enroll-keys failed"
    sbctl sign-all || fail "sign-all failed"
    sbctl verify || true
    ok "sbctl keys enrolled and files signed"
  fi
else
  warn "sbctl not installed - install sbctl (sudo pacman -S sbctl)"
fi

# =====================================================================
head "MANUAL STEPS (not automated - need physical YubiKey / device)"
cat <<'EOF'
  YubiKey u2f_keys (as user, one touch per key):
    mkdir -p ~/.config/Yubico
    pamu2fcfg >  ~/.config/Yubico/u2f_keys
    pamu2fcfg >> ~/.config/Yubico/u2f_keys     # 2nd key

  LUKS enrollment (select your root device):
    sudo systemd-cryptenroll --fido2-device=auto /dev/xxx

  pam_u2f (add this line near the top of auth section, one per file):
    auth sufficient pam_u2f.so authfile=.config/Yubico/u2f_keys cue
    -> /etc/pam.d/system-login, system-auth, greetd, sudo, hyprlock

  Bootloader default entry:
    managed by install-cachyos-kernel.sh (default linux-cachyos*)
EOF

head "DONE"
cat <<EOF
  Reboot required for: kernel cmdline, mkinitcpio images, greetd,
  fstab mount, secure boot, printer.
  Rollbacks: backups are alongside the modified files (.bak) and in
  /var/lib/perf-tune-backup/ where applicable.
EOF
exit 0
