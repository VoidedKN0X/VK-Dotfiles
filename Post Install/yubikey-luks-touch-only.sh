#!/usr/bin/env bash
# yubikey-luks-touch-only.sh
# Makes the YubiKey unlock the LUKS disk with a touch only (no PIN at boot), for
# the Steam Deck, which has no keyboard before the desktop starts:
#
#     sudo "Post Install/yubikey-luks-touch-only.sh"
#
#   1. Enrolls the plugged-in YubiKey again, touch only (no PIN).
#   2. Removes every OTHER FIDO2 key slot on the disk (e.g. the one archinstall
#      enrolled with a PIN): with a PIN key enrolled, boot asks for the PIN.
#
# Asks before each step. Your LUKS passphrase slot is never touched, and the
# old slots are only removed after the new one is confirmed. To keep a 2nd
# YubiKey as a backup, enroll it afterwards with yubikey-setup.sh.

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

# --------------- output ----------------------------------------------------
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()      { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; }
warn()    { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
FAILS=0
fail()    { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; FAILS=$((FAILS + 1)); }
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
ask()     { local a; read -rp "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }

for cmd in systemd-cryptenroll cryptsetup; do
  command -v "$cmd" >/dev/null || { fail "$cmd not found"; exit 1; }
done

# FIDO2 key slots on LUKS device $1, one "slot kind" per line (kind: pin or
# touch). Read from each token's JSON in the LUKS header; a token without the
# PIN field needs one (systemd's default for older enrollments).
fido2_slots() {
  local id json kind
  for id in $(seq 0 31); do
    json="$(cryptsetup token export --token-id "$id" "$1" 2>/dev/null | tr -d '[:space:]')"
    [[ $json == *'"type":"systemd-fido2"'* ]] || continue
    if [[ $json == *'"fido2-clientPin-required":false'* ]]; then kind="touch"; else kind="pin"; fi
    grep -o '"keyslots":\[[^]]*\]' <<<"$json" | grep -o '[0-9]\+' | sed "s/\$/ $kind/"
  done
}

# Only sd-encrypt can use the key at boot (archinstall's HSM option sets it up)
if ! grep -hsE '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf | grep -qw 'sd-encrypt'; then
  warn "your boot image doesn't use the sd-encrypt hook, so no YubiKey can unlock the disk at boot"
fi

if [[ -z "$(systemd-cryptenroll --fido2-device=list 2>/dev/null)" ]]; then
  fail "no FIDO2 key found - plug in your YubiKey and run this again"
  exit 1
fi

mapfile -t DEVS < <(lsblk -rpno NAME,FSTYPE | awk '$2 == "crypto_LUKS" { print $1 }')
[[ ${#DEVS[@]} -eq 0 ]] && { ok "no LUKS partitions found - nothing to do"; exit 0; }

for dev in "${DEVS[@]}"; do
  section "$dev"
  systemd-cryptenroll "$dev" 2>/dev/null | sed 's/^/  /'
  mapfile -t old < <(fido2_slots "$dev")
  for l in "${old[@]}"; do echo "  slot ${l% *}: FIDO2, ${l#* }"; done

  # the passphrase is the fallback if anything goes wrong: never continue without it
  if ! systemd-cryptenroll "$dev" 2>/dev/null | grep -qw password; then
    fail "$dev has no passphrase slot - not changing anything"
    continue
  fi

  ask "Enroll the plugged-in YubiKey for $dev with a touch only (no PIN)?" || continue
  echo "You'll be asked for your LUKS passphrase (or the PIN of an enrolled key), then a touch."
  if ! systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin=no \
         --fido2-with-user-presence=yes "$dev"; then
    fail "enrollment failed for $dev - nothing removed"
    continue
  fi

  # the new slot = the FIDO2 slot that wasn't there before; it must be touch-only
  new=""
  while read -r slot kind; do
    printf '%s\n' "${old[@]}" | grep -q "^$slot " && continue
    [[ $kind == touch ]] && new="$slot"
  done < <(fido2_slots "$dev")
  if [[ -z $new ]]; then
    fail "couldn't find the new touch-only slot on $dev - nothing removed"
    continue
  fi
  ok "slot $new: YubiKey, touch only"

  [[ ${#old[@]} -eq 0 ]] && { ok "no other FIDO2 slots to remove"; continue; }
  wipe="$(printf '%s\n' "${old[@]}" | cut -d' ' -f1 | paste -sd,)"
  if ask "Remove the other FIDO2 slot(s) $wipe? Slot $new and your passphrase stay."; then
    if systemd-cryptenroll --wipe-slot="$wipe" "$dev"; then
      ok "removed slot(s) $wipe"
    else
      fail "could not remove slot(s) $wipe"
    fi
  fi
  echo
  systemd-cryptenroll "$dev" 2>/dev/null | sed 's/^/  /'
done

# the boot must be told to try the key (yubikey-setup.sh adds this)
if grep -qs 'fido2-device=' /etc/kernel/cmdline /etc/crypttab.initramfs; then
  ok "boot is set to unlock with the YubiKey (fido2-device=)"
else
  warn "no fido2-device= in /etc/kernel/cmdline or /etc/crypttab.initramfs - run yubikey-setup.sh"
fi

section "DONE"
echo "Reboot to test: plug in the YubiKey and touch it when it blinks. Your passphrase still works."
if [[ $FAILS -gt 0 ]]; then
  fail "$FAILS step(s) failed - see the messages above"
  exit 1
fi
