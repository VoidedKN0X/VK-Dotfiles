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
#      after checking that sudo/greetd/logins really include system-auth. If
#      you say a test failed, every PAM file is put back exactly as it was.
#   3. Unlock your LUKS disk with the YubiKey (systemd-cryptenroll) and tell the
#      initramfs to use it at boot. A key that's already enrolled stays
#      enrolled; this only adds keys (e.g. your 2nd key as a backup).
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
fail()    { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; }
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
ask()     { local a; read -rp "$1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }

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
    # Older setups added the 2nd key as a second "user:..." line; merge those.
    if [[ "$(grep -c "^${REAL_USER}:" "$KEYFILE")" -gt 1 ]]; then
      warn "$KEYFILE has several lines for $REAL_USER - pam_u2f expects all keys on one line"
      if ask "Merge them into one line? (no need to touch the keys again)"; then
        awk -v u="$REAL_USER" '
          index($0, u ":") == 1 { k = substr($0, length(u) + 2); keys = (keys == "" ? k : keys ":" k); next }
          { print }
          END { if (keys != "") print u ":" keys }' "$KEYFILE" > "$KEYFILE.tmp" && mv "$KEYFILE.tmp" "$KEYFILE"
        ok "merged into one line"
      fi
    fi
    line="$(grep -m1 "^${REAL_USER}:" "$KEYFILE")"
    if [[ -n "$line" ]]; then
      # the registered keys are always kept; new keys are added after them
      IFS=':' read -ra existing <<<"${line#${REAL_USER}:}"
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
      fail "registration failed for key #$n"
    fi
    ask "Register another key?" || break
  done

  if [[ $(( ${#existing[@]} + ${#keys[@]} )) -eq 0 ]]; then
    warn "no keys registered - $KEYFILE unchanged"
    return 0
  fi
  mkdir -p "$KEYDIR"
  line="$REAL_USER"
  for out in "${existing[@]}" "${keys[@]}"; do line+=":$out"; done
  # keep lines for other users, replace ours
  { [[ -f "$KEYFILE" ]] && grep -v "^${REAL_USER}:" "$KEYFILE"; printf '%s\n' "$line"; } > "$KEYFILE.tmp"
  mv "$KEYFILE.tmp" "$KEYFILE"
  chown -R "$REAL_USER:$REAL_USER" "$KEYDIR"
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
  local svc missing=() f hyprlock_change=0 hyprlock_existed=0
  local ins_line ins_mode before head_part
  local -A saved=()

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
      fail "/etc/pam.d/$svc does NOT include system-auth"
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
  for svc in "${PAM_SERVICES[@]}"; do
    if grep -qE '^[[:space:]]*auth[[:space:]].*pam_u2f\.so' "/etc/pam.d/$svc"; then
      echo "  - remove the old pam_u2f line(s) from /etc/pam.d/$svc (system-auth covers it now):"
      grep -nE '^[[:space:]]*auth[[:space:]].*pam_u2f\.so' "/etc/pam.d/$svc" | sed 's/^/        /'
    fi
  done
  echo "Everything that uses system-auth (also su, polkit) will accept the key, with your password as a fallback."
  if [[ "$(cat "$HYPRLOCK_PAM_FILE" 2>/dev/null)" == "$HYPRLOCK_PAM" ]]; then
    ok "$HYPRLOCK_PAM_FILE already accepts only the YubiKey"
  else
    hyprlock_change=1
    echo "  - replace $HYPRLOCK_PAM_FILE: the lock screen accepts ONLY the YubiKey, not your password."
    echo "    Without a key: Ctrl+Alt+F3, log in with your password, run: pkill -USR1 hyprlock"
  fi
  ask "Apply this?" || { warn "PAM left unchanged"; return 0; }

  # --- keep the originals in memory for an exact rollback ---
  for svc in system-auth "${PAM_SERVICES[@]}"; do
    saved[$svc]="$(cat "/etc/pam.d/$svc"; echo x)"   # trailing x keeps final newlines
  done
  if [[ -f "$HYPRLOCK_PAM_FILE" ]]; then
    hyprlock_existed=1
    saved[hyprlock]="$(cat "$HYPRLOCK_PAM_FILE"; echo x)"
  fi

  if [[ -n "${ins_line:-}" ]]; then
    sed -i "${ins_line}${ins_mode}\\${PAM_LINE}" "$f"
    ok "added pam_u2f to $f"
  fi
  for svc in "${PAM_SERVICES[@]}"; do
    if grep -qE '^[[:space:]]*auth[[:space:]].*pam_u2f\.so' "/etc/pam.d/$svc"; then
      sed -i -E '/^[[:space:]]*auth[[:space:]].*pam_u2f\.so/d' "/etc/pam.d/$svc"
      ok "removed old pam_u2f line from /etc/pam.d/$svc"
    fi
  done
  if [[ $hyprlock_change -eq 1 ]]; then
    printf '%s\n' "$HYPRLOCK_PAM" > "$HYPRLOCK_PAM_FILE"
    chmod 644 "$HYPRLOCK_PAM_FILE"
    ok "$HYPRLOCK_PAM_FILE now accepts only the YubiKey"
  fi

  # --- test, roll back if it doesn't work ---
  local passed=1
  echo
  echo "TEST NOW - keep this window open. In a NEW terminal run:"
  echo "    sudo -k; sudo true"
  echo "It should say 'Please touch the device'. Touch it: sudo must succeed without a password."
  ask "Did sudo accept your key?" || passed=0
  if [[ $passed -eq 1 && $hyprlock_change -eq 1 ]]; then
    echo
    echo "Now the lock screen: press Super+L (or run 'hyprlock' in the new terminal)."
    echo "Typing your password must NOT unlock it. Touch your key: it must unlock."
    echo "If it won't unlock: Ctrl+Alt+F3, log in with your password, run 'pkill -USR1 hyprlock',"
    echo "then switch back to your desktop and answer 'n' below to undo everything."
    ask "Did the lock screen unlock with your key (and not with the password)?" || passed=0
  fi
  if [[ $passed -eq 1 ]]; then
    ok "pam_u2f active"
  else
    for svc in system-auth "${PAM_SERVICES[@]}"; do
      printf '%s' "${saved[$svc]%x}" > "/etc/pam.d/$svc"
    done
    if [[ $hyprlock_existed -eq 1 ]]; then
      printf '%s' "${saved[hyprlock]%x}" > "$HYPRLOCK_PAM_FILE"
    elif [[ $hyprlock_change -eq 1 ]]; then
      rm -f "$HYPRLOCK_PAM_FILE"
    fi
    fail "rolled back: all PAM files restored exactly as they were"
  fi
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
  local dev="$1" uuid cmdline hooks entry
  uuid="$(blkid -s UUID -o value "$dev")"
  hooks="$(hooks_line)"

  if ! grep -qw 'sd-encrypt' <<<"$hooks"; then
    warn "your initramfs doesn't use the sd-encrypt hook - FIDO2 unlock at boot needs it."
    warn "The key is enrolled, but boot will keep asking for the passphrase. HOOKS left unchanged."
    return 0
  fi

  # Case 1: the disk is listed in /etc/crypttab.initramfs -> add the option there
  if [[ -f /etc/crypttab.initramfs ]] && grep -qE "^[[:space:]]*[^#[:space:]]+[[:space:]]+(UUID=${uuid}|${dev}|/dev/disk/by-uuid/${uuid})([[:space:]]|$)" /etc/crypttab.initramfs; then
    entry="$(grep -E "(UUID=${uuid}|${dev}|by-uuid/${uuid})" /etc/crypttab.initramfs)"
    if grep -q 'fido2-device=' <<<"$entry"; then
      ok "crypttab.initramfs already has fido2-device for this disk"
      return 0
    fi
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

# How many FIDO2 keys enrolled on LUKS device $1 need a PIN at boot ($2 = true)
# or only a touch ($2 = false). Read from the token data in the LUKS header;
# luksDump may put the value on the line after the field name, so whitespace is
# squeezed first.
fido2_pin_count() {
  cryptsetup luksDump "$1" 2>/dev/null | tr -s '[:space:]' ' ' \
    | grep -o "fido2-clientPin-required: $2" | wc -l
}

# On the Steam Deck: report how the disk's keys unlock, and warn about any key
# that needs a PIN (it can't be typed at boot). Nothing is removed.
report_deck_keys() {
  local dev="$1" pin touch
  command -v cryptsetup >/dev/null || return 0
  pin="$(fido2_pin_count "$dev" true)"
  touch="$(fido2_pin_count "$dev" false)"
  ok "$dev: $touch key(s) unlock with a touch only"
  if [[ $pin -gt 0 ]]; then
    warn "$dev: $pin key(s) need a PIN at boot, which can't be typed on the Steam Deck."
    warn "  They stay enrolled. See them with: sudo systemd-cryptenroll $dev"
    warn "  Remove one by hand once a touch-only key works: sudo systemd-cryptenroll --wipe-slot=<slot> $dev"
  fi
}

setup_luks() {
  local dev added existing prompt pin_opt pin_text deck=0
  local -a devs

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

  for dev in "${devs[@]}"; do
    echo
    lsblk -no NAME,SIZE,FSTYPE,UUID "$dev" | head -1 | sed 's/^/  /'
    existing="$(systemd-cryptenroll "$dev" 2>/dev/null | grep -c fido2)"
    echo "  FIDO2 keys already enrolled: $existing (they stay enrolled)"
    [[ $deck -eq 1 && $existing -gt 0 ]] && report_deck_keys "$dev"

    # Keys are only ever added: an enrolled key is never removed or replaced.
    if [[ $existing -eq 0 ]]; then
      prompt="Enroll a YubiKey for $dev?"
    else
      prompt="Enroll another YubiKey for $dev (e.g. your 2nd key as a backup)?"
    fi
    ask "$prompt" || continue

    added=0   # counted per disk
    while :; do
      echo "Plug in ONE key that isn't enrolled yet (unplug the other one). You'll be asked for $pin_text."
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
