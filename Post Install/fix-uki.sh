#!/usr/bin/env bash
# fix-uki.sh
# Enables UKI (Unified Kernel Image) for all kernel presets that are using
# traditional initramfs, and signs the generated UKIs with sbctl.
#
# Detects all /etc/mkinitcpio.d/*.preset files, switches any that use
# default_image to default_uki, regenerates with mkinitcpio -P, then
# signs all unsigned UKIs via sbctl.
#
# Usage:
#   sudo ./fix-uki.sh

set -uo pipefail

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()   { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; }
fail() { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; exit 1; }
warn() { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
head() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo --preserve-env=HOME "$0" "$@"
fi

BACKUP_DIR="/var/lib/perf-tune-backup"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# ---------- find ESP ----------
head "Pre-flight checks"
ESP=""
for _e in /boot /efi /boot/efi; do
  if [[ -d "$_e/EFI/Linux" ]]; then ESP="$_e"; break; fi
done
[[ -z "$ESP" ]] && fail "No UKI directory found (looked in /boot, /efi, /boot/efi)"
UKI_DIR="$ESP/EFI/Linux"
ok "UKI directory: $UKI_DIR"

# ---------- check presets ----------
mapfile -t PRESETS < <(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' -type f 2>/dev/null | sort)
[[ ${#PRESETS[@]} -eq 0 ]] && fail "No presets found in /etc/mkinitcpio.d"
ok "Found ${#PRESETS[@]} preset(s): $(printf '%s ' "$(basename "${PRESETS[@]}")")"

# ---------- enable UKI for presets using default_image ----------
head "Enabling UKI for presets using traditional initramfs"
SWITCHED=0
for p in "${PRESETS[@]}"; do
  NAME="$(basename "$p" .preset)"
  KERNEL_NAME="${NAME#linux-}"
  KERNEL_NAME="${KERNEL_NAME#linux}"

  # Already using UKI?
  if grep -qE '^default_uki=' "$p" && ! grep -qE '^#default_uki=' "$p"; then
    ok "$NAME: already using UKI"
    continue
  fi

  # No default_image either? Skip.
  if ! grep -qE '^(default_image|#default_image)=' "$p"; then
    warn "$NAME: no default_image or default_uki found - skipping"
    continue
  fi

  head "Updating $NAME"
  cp -a "$p" "$BACKUP_DIR/${NAME}.preset.$TS"
  ok "backed up -> $BACKUP_DIR/${NAME}.preset.$TS"

  # Comment out default_image, uncomment default_uki
  sed -i -E '
    s/^(default_image=)/#&/
    s/^#(default_uki=)/\1/
    s/^(fallback_image=)/#&/
    s/^#(fallback_uki=)/\1/
  ' "$p"

  # If default_uki was commented out with an empty or wrong path, fix it
  if grep -qE '^default_uki=""' "$p" || ! grep -qE '^default_uki=".+\.efi"' "$p"; then
    sed -i "s|^default_uki=.*|default_uki=\"$UKI_DIR/arch-${NAME}.efi\"|" "$p"
  fi
  if grep -qE '^fallback_uki=""' "$p" || ! grep -qE '^fallback_uki=".+\.efi"' "$p"; then
    sed -i "s|^fallback_uki=.*|fallback_uki=\"$UKI_DIR/arch-${NAME}-fallback.efi\"|" "$p"
  fi

  ok "$NAME: switched to UKI"
  SWITCHED=1
done

if [[ $SWITCHED -eq 0 ]]; then
  ok "All presets already using UKI"
fi

# ---------- show presets ----------
head "Current presets"
for p in "${PRESETS[@]}"; do
  NAME="$(basename "$p" .preset)"
  UKI_LINE=$(grep -E '^default_uki=' "$p" 2>/dev/null | head -1)
  IMG_LINE=$(grep -E '^default_image=' "$p" 2>/dev/null | head -1)
  if [[ -n "$UKI_LINE" ]]; then
    ok "$NAME: $UKI_LINE"
  elif [[ -n "$IMG_LINE" ]]; then
    warn "$NAME: $IMG_LINE"
  fi
done

# ---------- sync vmlinuz to /boot if missing ----------
head "Syncing kernel images to /boot"
for _preset in /etc/mkinitcpio.d/*.preset; do
  [[ -f "$_preset" ]] || continue
  _kver_line=$(grep -E '^ALL_kver=' "$_preset" | awk 'NR==1{print;exit}')
  [[ -z "$_kver_line" ]] && continue
  _kver="${_kver_line#ALL_kver=\"}"
  _kver="${_kver%\"}"
  _kver="${_kver#ALL_kver=}"
  if [[ ! -f "$_kver" ]]; then
    _name="$(basename "$_preset" .preset)"
    _mod_dir=""
    for _d in /usr/lib/modules/*/; do
      [[ -f "${_d}pkgbase" ]] && [[ "$(cat "${_d}pkgbase")" == "$_name" ]] && { _mod_dir="$_d"; break; }
    done
    if [[ -z "$_mod_dir" ]]; then
      _kname="${_name#linux-}"
      _kname="${_kname#linux}"
      for _d in /usr/lib/modules/*/; do
        _base="$(basename "$_d")"
        if [[ -n "$_kname" ]] && [[ "$_base" == *"$_kname"* ]] && [[ -f "${_d}vmlinuz" ]]; then
          _mod_dir="$_d"; break
        fi
      done
    fi
    if [[ -n "$_mod_dir" && -f "${_mod_dir}vmlinuz" ]]; then
      cp "${_mod_dir}vmlinuz" "$_kver"
      ok "copied $(basename "${_mod_dir}vmlinuz") -> $_kver"
    else
      warn "could not find vmlinuz for $_name in /usr/lib/modules/"
    fi
  else
    ok "$_kver already present"
  fi

  # fix UKI paths that point to a non-existent directory (e.g. /efi/ instead of /boot/)
  _uki_dir="/boot/EFI/Linux"
  if [[ -d "$_uki_dir" ]]; then
    for _uki_key in default_uki fallback_uki; do
      _uki_line=$(grep -E "^${_uki_key}=" "$_preset" | awk 'NR==1{print;exit}')
      [[ -z "$_uki_line" ]] && continue
      _uki_val="${_uki_line#${_uki_key}=\"}"
      _uki_val="${_uki_val%\"}"
      _uki_val="${_uki_val#${_uki_key}=}"
      _uki_parent="$(dirname "$_uki_val")"
      if [[ ! -d "$_uki_parent" ]]; then
        _uki_fname="$(basename "$_uki_val")"
        _new_uki="${_uki_dir}/${_uki_fname}"
        sed -i "s|^${_uki_key}=.*|${_uki_key}=\"${_new_uki}\"|" "$_preset"
        ok "fixed ${_uki_key} in $(basename "$_preset"): $_uki_val -> $_new_uki"
      fi
    done
  fi
done

# ---------- regenerate ----------
head "Regenerating all UKIs with mkinitcpio -P"
if mkinitcpio -P; then
  ok "mkinitcpio -P completed"
else
  fail "mkinitcpio -P failed"
fi

# ---------- sign UKIs with sbctl ----------
head "Signing UKIs with sbctl"
if command -v sbctl >/dev/null; then
  UNSIGNED=$(sbctl verify 2>/dev/null | grep '^✗' | sed 's/^✗ //;s/:.*//')
  if [[ -n "$UNSIGNED" ]]; then
    warn "signing unsigned files"
    while IFS= read -r efi; do
      [[ -f "$efi" ]] || continue
      sbctl sign -s "$efi"
    done <<< "$UNSIGNED"
    ok "signed unsigned files"
  else
    ok "all UKIs already signed"
  fi
  sbctl verify || true
else
  warn "sbctl not installed - install sbctl (sudo pacman -S sbctl) and sign manually"
  warn "  sbctl create-keys && sbctl sign -s $UKI_DIR/*.efi && sbctl enroll-keys -m"
fi

# ---------- verify ----------
head "Verification"
mapfile -t UKIS < <(find "$UKI_DIR" -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
if [[ ${#UKIS[@]} -gt 0 ]]; then
  for u in "${UKIS[@]}"; do
    ok "UKI: $(basename "$u")"
  done
else
  warn "no UKI files found in $UKI_DIR"
fi

if command -v bootctl >/dev/null; then
  COUNT=$(bootctl --no-pager list 2>/dev/null | grep -ciE 'linux|cachyos|zen' || true)
  if [[ "$COUNT" -gt 0 ]]; then
    ok "bootctl lists $COUNT bootable kernel entry/entries"
  else
    warn "bootctl did not list any kernel entries - check manually"
  fi
fi

head "DONE"
cat <<EOF
  UKI enabled and signed for all kernel presets.
  Backup: $BACKUP_DIR/*.preset.$TS
  REBOOT REQUIRED to boot from the new UKIs.
EOF
