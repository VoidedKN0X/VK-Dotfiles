#!/usr/bin/env bash
# yubikey-setup.sh
# Interactive YubiKey setup. Run it AFTER Install.sh and run-all-<profile>.sh,
# with your YubiKey(s) at hand:
#
#     sudo "Post Install/yubikey-setup.sh"
#
# Steps (each one asks before changing anything):
#   1. Register your YubiKeys in ~/.config/Yubico/u2f_keys. Keys that are
#      already registered stay; new ones (e.g. your 2nd key) are added to them.
#   2. Accept the YubiKey instead of your password for sudo, greetd and logins:
#      ONE line in /etc/pam.d/system-auth, with the password as a fallback.
#      The lock screen (hyprlock) gets its own PAM file that accepts ONLY the
#      YubiKey, no password. Every key registered in step 1 works. Only done
#      after checking that sudo/greetd/logins really include system-auth.
#   3. Unlock your LUKS disk with the YubiKey (systemd-cryptenroll) and tell the
#      initramfs to use it at boot. This adds keys (e.g. your 2nd key as a
#      backup). On the Steam Deck, keys that need a PIN at boot can be enrolled
#      again without one; the PIN slots are then removed (asked first).
#      Needs the sd-encrypt hook (archinstall's HSM option); skipped otherwise.
#
# Your password (sudo, login) and your LUKS passphrase keep working as a
# fallback. The lock screen doesn't: without a key, unlock it from a text
# console (Ctrl+Alt+F3, log in with your password) with: pkill -USR1 hyprlock

set -uo pipefail

# --------------- root + real user -----------------------------------------
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi
REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
  echo "Run this with sudo from your normal user account, not as root directly." >&2
  exit 1
fi
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
REAL_GROUP="$(id -gn "$REAL_USER")"
KEYDIR="$REAL_HOME/.config/Yubico"
KEYFILE="$KEYDIR/u2f_keys"

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
# Copy a system file to <file>.bak-yubikey before its first change. An existing
# backup is kept, so it always holds the original from before this script.
backup()  { [[ -e "$1" && ! -e "$1.bak-yubikey" ]] && cp -a "$1" "$1.bak-yubikey" && ok "backup: $1.bak-yubikey"; return 0; }

for cmd in pamu2fcfg systemd-cryptenroll; do
  command -v "$cmd" >/dev/null || { fail "$cmd not found (Install.sh installs pam-u2f and libfido2)"; exit 1; }
done

# PAM services that accept the key OR the password. All of them have to reach system-auth.
PAM_SERVICES=(sudo greetd system-login)
PAM_LINE="auth       sufficient                  pam_u2f.so           cue"

# The lock screen accepts ONLY the key: its own PAM file, without "include login"
# (which would let the password in through system-auth). "required" = the key
# must succeed; there's nothing after it to fall back to.
HYPRLOCK_PAM_FILE=/etc/pam.d/hyprlock
HYPRLOCK_PAM='# PAM configuration for hyprlock, written by yubikey-setup.sh
# Only a registered YubiKey unlocks the screen; the password is NOT accepted.
# Locked out (no key)? Switch to a text console (Ctrl+Alt+F3), log in with your
# password and run: pkill -USR1 hyprlock
auth       required                    pam_u2f.so           cue'

# =====================================================================
# 1. Register keys
# =====================================================================
# pam_u2f wants ONE line per user: "user:key1:key2:...". `pamu2fcfg -n` prints a
# single key without the username, so each key's output is collected and the
# line is written in one go - no dependency on how the file ends.
register_keys() {
  local -a keys=() existing=()
  local out n line

  section "1. Register YubiKeys for login / sudo / lock screen"

  if [[ -s "$KEYFILE" ]]; then
    # older setups can have a second "user:" line for another key: read them all,
    # they're merged into one line when the file is written below
    while IFS= read -r line; do
      IFS=':' read -ra keys <<<"${line#"${REAL_USER}":}"
      existing+=("${keys[@]}")
    done < <(grep "^${REAL_USER}:" "$KEYFILE")
    keys=()
    if [[ ${#existing[@]} -gt 0 ]]; then
      # the registered keys are always kept; new keys are added after them
      ok "${#existing[@]} key(s) already registered for $REAL_USER (they stay registered)"
      ask "Add another key (e.g. your 2nd YubiKey)?" || return 0
    elif ! ask "Register your YubiKeys for $REAL_USER now?"; then
      return 0
    fi
  elif ! ask "Register your YubiKeys now?"; then
    return 0
  fi

  n=$(( ${#existing[@]} + 1 ))
  while :; do
    echo
    echo "Plug in key #$n (unplug any other key), then touch it when it blinks."
    if out="$(pamu2fcfg -n)" && [[ -n "$out" ]]; then
      keys+=("${out#:}")
      ok "key #$n registered"
      n=$((n + 1))
    else
      warn "registration failed for key #$n (you can try again)"
    fi
    ask "Register another key?" || break
  done

  if [[ $(( ${#existing[@]} + ${#keys[@]} )) -eq 0 ]]; then
    warn "no keys registered - $KEYFILE unchanged"
    return 0
  fi
  # ~/.config must stay the user's if this creates it
  [[ -d "$REAL_HOME/.config" ]] || install -d -o "$REAL_USER" -g "$REAL_GROUP" "$REAL_HOME/.config"
  mkdir -p "$KEYDIR"
  line="$REAL_USER"
  for out in "${existing[@]}" "${keys[@]}"; do line+=":$out"; done
  # keep lines for other users, replace ours
  { [[ -f "$KEYFILE" ]] && grep -v "^${REAL_USER}:" "$KEYFILE"; printf '%s\n' "$line"; } > "$KEYFILE.tmp"
  mv "$KEYFILE.tmp" "$KEYFILE"
  chown -R "$REAL_USER:$REAL_GROUP" "$KEYDIR"
  chmod 700 "$KEYDIR"; chmod 600 "$KEYFILE"
  ok "$(( ${#existing[@]} + ${#keys[@]} )) key(s) saved in $KEYFILE"
}

# =====================================================================
# 2. pam_u2f in system-auth
# =====================================================================
# Does PAM service $1 reach system-auth through its auth include/substack chain?
reaches_system_auth() {
  local svc="$1" depth="${2:-0}" next
  [[ "$svc" == "system-auth" ]] && return 0
  [[ -f "/etc/pam.d/$svc" && $depth -lt 10 ]] || return 1
  while read -r next; do
    reaches_system_auth "$next" $((depth + 1)) && return 0
  done < <(awk '$1 ~ /^-?auth$/ && ($2 == "include" || $2 == "substack") { print $3 }' "/etc/pam.d/$svc")
  return 1
}

setup_pam() {
  local svc missing=() f hyprlock_change=0
  local ins_line ins_mode before head_part

  section "2. YubiKey for sudo, greetd and logins (password fallback), lock screen key-only"

  if ! grep -q "^${REAL_USER}:" "$KEYFILE" 2>/dev/null; then
    warn "no keys registered for $REAL_USER (step 1) - skipping, so you can't lock yourself out"
    return 0
  fi

  # --- coverage check: every service must include system-auth ---
  for svc in "${PAM_SERVICES[@]}"; do
    if reaches_system_auth "$svc"; then
      ok "/etc/pam.d/$svc includes system-auth"
    else
      warn "/etc/pam.d/$svc does NOT include system-auth"
      missing+=("$svc")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "system-auth doesn't cover: ${missing[*]} - PAM left unchanged"
    return 0
  fi

  f=/etc/pam.d/system-auth
  # Insert after "pam_faillock.so preauth" (so locked accounts stay locked), or
  # before the first auth line if there is none. Either way the new line must
  # come before every jump rule like [success=2 ...], because those jump a fixed
  # number of lines and an extra line in between would change where they land.
  if grep -qE '^[[:space:]]*auth[[:space:]].*pam_u2f\.so' "$f"; then
    ok "system-auth already has a pam_u2f line"
  else
    ins_line="$(grep -nE '^[[:space:]]*auth[[:space:]].*pam_faillock\.so.*preauth' "$f" | head -1 | cut -d: -f1)"
    ins_mode=a
    if [[ -z "$ins_line" ]]; then
      ins_line="$(grep -nE '^[[:space:]]*-?auth[[:space:]]' "$f" | head -1 | cut -d: -f1)"
      ins_mode=i
    fi
    if [[ -z "$ins_line" ]]; then
      fail "no auth lines found in $f - PAM left unchanged"; return 0
    fi
    before=$ins_line; [[ $ins_mode == i ]] && before=$((ins_line - 1))
    # (captured first: piping into grep -q can end early and fake a "no match" under pipefail)
    head_part="$(head -n "$before" "$f")"
    if grep -qE '^[[:space:]]*-?auth[[:space:]]+\[' <<<"$head_part"; then
      fail "a jump rule ([success=...]) comes before the insert point in $f - PAM left unchanged"
      return 0
    fi
  fi

  # --- show the plan ---
  echo
  echo "Plan:"
  [[ -n "${ins_line:-}" ]] && echo "  - add to $f (line $ins_line):  $PAM_LINE"
  echo "Everything that uses system-auth (also su, polkit) will accept the key, with your password as a fallback."
  if [[ "$(cat "$HYPRLOCK_PAM_FILE" 2>/dev/null)" == "$HYPRLOCK_PAM" ]]; then
    ok "$HYPRLOCK_PAM_FILE already accepts only the YubiKey"
  else
    hyprlock_change=1
    echo "  - replace $HYPRLOCK_PAM_FILE: the lock screen accepts ONLY the YubiKey, not your password."
    echo "    Without a key: Ctrl+Alt+F3, log in with your password, run: pkill -USR1 hyprlock"
  fi
  ask "Apply this?" || { warn "PAM left unchanged"; return 0; }

  if [[ -n "${ins_line:-}" ]]; then
    backup "$f"
    sed -i "${ins_line}${ins_mode}\\${PAM_LINE}" "$f"
    ok "added pam_u2f to $f"
  fi
  if [[ $hyprlock_change -eq 1 ]]; then
    backup "$HYPRLOCK_PAM_FILE"
    printf '%s\n' "$HYPRLOCK_PAM" > "$HYPRLOCK_PAM_FILE"
    chmod 644 "$HYPRLOCK_PAM_FILE"
    ok "$HYPRLOCK_PAM_FILE now accepts only the YubiKey"
  fi

  ok "pam_u2f active: sudo, greetd and logins accept the key (password as fallback)"
}

# =====================================================================
# 3. LUKS unlock with the YubiKey
# =====================================================================
REBUILD=0

hooks_line() {  # all active HOOKS lines (main config + drop-ins)
  # "|| true": grep exits 2 when the drop-in glob matches no file, which would
  # otherwise make pipefail treat a successful match as a failure
  grep -hE '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf 2>/dev/null || true
}

# Make the initramfs try the YubiKey for device $1 at boot
enable_fido2_at_boot() {
  local dev="$1" uuid cmdline entry
  uuid="$(blkid -s UUID -o value "$dev")"

  # Case 1: the disk is listed in /etc/crypttab.initramfs -> add the option there
  if [[ -f /etc/crypttab.initramfs ]] && grep -qE "^[[:space:]]*[^#[:space:]]+[[:space:]]+(UUID=${uuid}|${dev}|/dev/disk/by-uuid/${uuid})([[:space:]]|$)" /etc/crypttab.initramfs; then
    entry="$(grep -E "^[[:space:]]*[^#[:space:]]+[[:space:]]+(UUID=${uuid}|${dev}|/dev/disk/by-uuid/${uuid})([[:space:]]|$)" /etc/crypttab.initramfs)"
    if grep -q 'fido2-device=' <<<"$entry"; then
      ok "crypttab.initramfs already has fido2-device for this disk"
      return 0
    fi
    backup /etc/crypttab.initramfs
    awk -v u="UUID=${uuid}" -v d="$dev" -v b="/dev/disk/by-uuid/${uuid}" '
      $1 !~ /^#/ && ($2 == u || $2 == d || $2 == b) {
        if (NF < 3) $3 = "none"
        if (NF < 4 || $4 == "-" || $4 == "") $4 = "fido2-device=auto"
        else $4 = $4 ",fido2-device=auto"
      }
      { print }' /etc/crypttab.initramfs > /etc/crypttab.initramfs.tmp \
      && mv /etc/crypttab.initramfs.tmp /etc/crypttab.initramfs
    ok "added fido2-device=auto to /etc/crypttab.initramfs"
    REBUILD=1
    return 0
  fi

  # Case 2: the disk is unlocked via rd.luks.name= / rd.luks.uuid= on the cmdline
  cmdline="$(cat /etc/kernel/cmdline 2>/dev/null)"
  if grep -qE '(^|[[:space:]])rd\.luks\.(name|uuid)=' <<<"$cmdline"; then
    if grep -q 'fido2-device=' <<<"$cmdline"; then
      ok "kernel cmdline already has fido2-device"
    elif grep -qE '(^|[[:space:]])rd\.luks\.options=' <<<"$cmdline"; then
      warn "cmdline already has rd.luks.options= - add ',fido2-device=auto' to it by hand"
    else
      backup /etc/kernel/cmdline
      echo "$cmdline rd.luks.options=fido2-device=auto" > /etc/kernel/cmdline
      ok "added rd.luks.options=fido2-device=auto to /etc/kernel/cmdline"
      REBUILD=1
    fi
    return 0
  fi

  warn "couldn't find how $dev is unlocked at boot (no /etc/crypttab.initramfs entry,"
  warn "no rd.luks.name=/rd.luks.uuid= in /etc/kernel/cmdline) - add fido2-device=auto by hand"
}

# On the Steam Deck (a tablet without keyboard) the key is enrolled WITHOUT a
# PIN: at boot you only plug it in and touch it, because there's no way to type
# a PIN before the desktop (and its on-screen keyboard) has started.
is_steamdeck() {
  [[ "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null) $(cat /sys/class/dmi/id/board_name 2>/dev/null)" == "Valve Jupiter" ]]
}

# Key slots of the FIDO2 keys on LUKS device $1 that need a PIN at boot
# ($2 = pin) or only a touch ($2 = touch), one per line. Read from each token's
# JSON in the LUKS header; a token without the PIN field needs one (systemd's
# default for older enrollments).
fido2_slots() {
  local dev="$1" want="$2" id json kind
  for id in $(seq 0 31); do
    json="$(cryptsetup token export --token-id "$id" "$dev" 2>/dev/null | tr -d '[:space:]')"
    [[ $json == *'"type":"systemd-fido2"'* ]] || continue
    if [[ $json == *'"fido2-clientPin-required":false'* ]]; then kind="touch"; else kind="pin"; fi
    [[ $kind == "$want" ]] || continue
    grep -o '"keyslots":\[[^]]*\]' <<<"$json" | grep -o '[0-9]\+'
  done
}

# On the Steam Deck: report how the disk's keys unlock. A key that needs a PIN
# can't be used at boot (no keyboard yet); setup_luks offers to replace it.
report_deck_keys() {
  local dev="$1" pin touch
  pin="$(fido2_slots "$dev" pin | wc -l)"
  touch="$(fido2_slots "$dev" touch | wc -l)"
  ok "$dev: $touch key(s) unlock with a touch only"
  [[ $pin -gt 0 ]] && warn "$dev: $pin key(s) need a PIN at boot, which can't be typed on the Steam Deck"
  return 0
}

setup_luks() {
  local dev added existing prompt pin_opt pin_text root_luks uuid deck=0
  local -a devs pin_slots

  if is_steamdeck; then
    deck=1
    # Touch only: the Deck has no keyboard at boot, so no PIN. If the key has a
    # PIN set, enrolling may ask for it once (type it on the on-screen keyboard);
    # unlocking at boot never does.
    pin_opt=no
    pin_text="your LUKS passphrase, then a touch (no PIN at boot on the Steam Deck)"
  else
    pin_opt=yes
    pin_text="your LUKS passphrase, the key PIN (if set), then a touch"
  fi

  section "3. Unlock the LUKS disk with the YubiKey"
  mapfile -t devs < <(lsblk -rpno NAME,FSTYPE | awk '$2 == "crypto_LUKS" { print $1 }')
  if [[ ${#devs[@]} -eq 0 ]]; then
    ok "no LUKS partitions found - nothing to do"
    return 0
  fi

  # Only sd-encrypt can use a FIDO2 key at boot; archinstall uses it when its
  # HSM option is set, otherwise the older encrypt hook (cryptdevice=)
  if ! grep -qw 'sd-encrypt' <<<"$(hooks_line)"; then
    fail "your boot image uses the 'encrypt' hook, which can't unlock the disk with a YubiKey."
    warn "  Nothing enrolled. Reinstall with archinstall's HSM option set to your YubiKey to get sd-encrypt."
    return 0
  fi

  # Only the disk the system boots from (the one holding /) is unlocked by the
  # initramfs, so that's the only one the YubiKey is for. archinstall opens every
  # other encrypted disk after it with a key file stored on it (/etc/crypttab):
  # a key enrolled there would never be used.
  root_luks="$(lsblk -nrpso NAME,FSTYPE "$(findmnt -nvo SOURCE /)" 2>/dev/null | awk '$2 == "crypto_LUKS" { print $1; exit }')"
  if [[ -z "$root_luks" ]]; then
    ok "/ isn't on an encrypted disk - nothing to enroll"
    return 0
  fi

  for dev in "${devs[@]}"; do
    if [[ "$dev" != "$root_luks" ]]; then
      uuid="$(blkid -s UUID -o value "$dev")"
      if awk -v u="$uuid" -v d="$dev" '$1 !~ /^#/ && ($2 == "UUID=" u || $2 == "/dev/disk/by-uuid/" u || $2 == d) && $3 != "none" && $3 != "-" && $3 != ""' \
           /etc/crypttab 2>/dev/null | grep -q .; then
        ok "$dev: opened with a key file after the boot disk - nothing to do"
      else
        ok "$dev: not the boot disk - skipped"
      fi
      continue
    fi
    echo
    lsblk -no NAME,SIZE,FSTYPE,UUID "$dev" | head -1 | sed 's/^/  /'
    existing="$(systemd-cryptenroll "$dev" 2>/dev/null | grep -c fido2)"
    echo "  FIDO2 keys already enrolled: $existing"
    pin_slots=()
    if [[ $deck -eq 1 && $existing -gt 0 ]]; then
      report_deck_keys "$dev"
      mapfile -t pin_slots < <(fido2_slots "$dev" pin)
    fi

    # Keys are added; the only ones ever removed are PIN keys on the Deck, and
    # only after a touch-only key was enrolled in their place (asked first)
    if [[ ${#pin_slots[@]} -gt 0 ]]; then
      prompt="Enroll your key(s) again without a PIN, to replace the ${#pin_slots[@]} that need one?"
    elif [[ $existing -eq 0 ]]; then
      prompt="Enroll a YubiKey for $dev?"
    else
      prompt="Enroll another YubiKey for $dev (e.g. your 2nd key as a backup)?"
    fi
    ask "$prompt" || continue

    added=0   # counted per disk
    while :; do
      if [[ ${#pin_slots[@]} -gt 0 ]]; then
        echo "Plug in ONE key (a key enrolled with a PIN can be enrolled again). You'll be asked for $pin_text."
      else
        echo "Plug in ONE key that isn't enrolled yet (unplug the other one). You'll be asked for $pin_text."
      fi
      # a touch (user presence) is always required; a PIN only off the Deck
      if systemd-cryptenroll --fido2-device=auto --fido2-with-client-pin="$pin_opt" \
           --fido2-with-user-presence=yes "$dev"; then
        ok "key enrolled for $dev (touch required, PIN required: $pin_opt)"
        added=$((added + 1))
      else
        fail "enrollment failed for $dev"
      fi
      ask "Enroll another key for $dev?" || break
    done
    # check the result: on the Deck the new key(s) must be touch-only
    [[ $deck -eq 1 && $added -gt 0 ]] && report_deck_keys "$dev"
    # then remove the PIN keys they replace (the passphrase slot stays)
    if [[ ${#pin_slots[@]} -gt 0 && $added -gt 0 && $(fido2_slots "$dev" touch | wc -l) -gt 0 ]]; then
      if ask "Remove the ${#pin_slots[@]} key slot(s) that need a PIN (slot ${pin_slots[*]})? Test the new key first if you're unsure."; then
        if systemd-cryptenroll --wipe-slot="$(IFS=,; echo "${pin_slots[*]}")" "$dev"; then
          ok "removed slot(s) ${pin_slots[*]} from $dev"
        else
          fail "could not remove slot(s) ${pin_slots[*]} from $dev"
        fi
      fi
    fi
    [[ $added -gt 0 ]] && enable_fido2_at_boot "$dev"
  done

  if [[ $REBUILD -eq 1 ]]; then
    section "Rebuilding initramfs / UKIs"
    # sbctl's mkinitcpio hook re-signs the UKIs automatically
    if mkinitcpio -P; then ok "images rebuilt"; else fail "mkinitcpio -P failed"; fi
  fi
}

# =====================================================================
register_keys
setup_pam
setup_luks

section "DONE"
echo "Reboot to test the LUKS unlock. Your passphrase and password still work as a fallback,"
echo "except on the lock screen, which only accepts the YubiKey."
if [[ $FAILS -gt 0 ]]; then
  fail "$FAILS step(s) failed - see the messages above"
  exit 1
fi
