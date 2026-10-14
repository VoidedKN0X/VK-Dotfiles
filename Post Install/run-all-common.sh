#!/usr/bin/env bash
# run-all-common.sh
# SINGLE combined Post Install script. It replaces the individual scripts that
# used to be chained by the old run-all wrapper:
#     install-cachyos-repo.sh -> install-cachyos-kernel.sh -> fix-uki.sh
#     -> full-tune (this file) -> cachyos-compat.sh
# Those files no longer exist; everything lives here.
#
# It is sourced by the three entry points (Install.sh runs the right one):
#     run-all-desktop.sh    ->  sudo ./run-all-desktop.sh
#     run-all-laptop.sh     ->  sudo ./run-all-laptop.sh
#     run-all-steamdeck.sh  ->  sudo ./run-all-steamdeck.sh
# Do not run this file directly. The entry point sets PROFILE_NAME,
# CPUFREQ_GOVERNOR and TUNE_NAME before sourcing it. Optional, per device:
#   KERNEL_FLAVOR  CachyOS kernel flavor ("" = linux-cachyos, "deckify" = the
#                  handheld kernel with the Steam Deck drivers)
#   SECURE_BOOT    1 (default) = set up Secure Boot in stage 3, 0 = skip it
#   device_setup() a function; if defined, it runs in stage 2 right after the
#                  kernel install (used by run-all-steamdeck.sh)
#
# Stages (in order):
#   1. CachyOS repository setup (official installer)
#   2. CachyOS kernel install + systemd-boot default entry (boot menu timeout 0)
#      + Plymouth boot splash (cmdline params + mkinitcpio hook)
#   3. Fix/enable UKI + Secure Boot (sbctl keys, enroll -m, sign UKIs; sbctl is
#      installed by Install.sh)
#   4. Performance tune (profile-specific: desktop/laptop/steamdeck)
#   5. CachyOS-kernel compatibility check (verification only; stage 4 already
#      applies the I/O scheduler rules, fq + bbr and transparent_hugepage=madvise)
#
# Tune groups (stage 4):
#   A. sysctl (dirty pages, BBR, TCP buffers, NMI watchdog off, and zram swap
#      tuning when zram is set up) + I/O scheduler and readahead for hard disks
#   B. THP madvise (runtime + tmpfiles for the defrag setting)
#   C. Install: lib32-gamemode, lib32-mangohud, irqbalance on the desktop, and
#      Proton-CachyOS; load the ntsync module at boot
#   D. Enable: irqbalance on the desktop (gamemoded needs no enabling: it's
#      started on demand)
#   E. fstab noatime (REBOOT required)
#   F. systemd-boot kernel cmdline: transparent_hugepage=madvise,
#      quiet splash plymouth.boot-log=/dev/null plymouth.nolog, and
#      zswap.enabled=0 when zram is used
#      (REBOOT required). The cmdline is written in stage 2, before the images
#      are built, so later stages don't have to rebuild for it. A cpufreq
#      governor is only added when CPUFREQ_GOVERNOR is explicitly set.
#   G. /etc/environment: removes RADV_PERFTEST and MESA_NO_ERROR if an older
#      version of this script added them
#   H. Audio: HDA power-save off (desktop only, REBOOT required) and a lower
#      default PipeWire quantum
#
# Persistence:
#   /etc/sysctl.d/99-perf-tune.conf
#   /etc/udev/rules.d/60-ioschedulers.rules
#   /etc/modules-load.d/bbr.conf
#   /etc/tmpfiles.d/thp-defrag.conf
#   /etc/modprobe.d/audio-disable-power-save.conf (desktop)
#   /etc/pipewire/pipewire.conf.d/99-low-latency.conf
#   /etc/kernel/cmdline (modified, systemd-boot)
#   /etc/fstab           (modified)
#
# No backups are made: this script is meant to run once on a clean install, so
# there is nothing worth preserving. It takes no command-line arguments.

# === PROFILE (must be set by the sourcing entry point) ===
if [[ -z "${PROFILE_NAME:-}" ]]; then
  echo "Error: run run-all-desktop.sh, run-all-laptop.sh or run-all-steamdeck.sh, not this file." >&2
  exit 2
fi


set -uo pipefail

# === USER CONFIG (edit only if auto-detection misbehaves) ===
# Filesystems to convert relatime->noatime in fstab (space-separated list).
# Auto-detected from fstab (local, non-pseudo fs) if left empty.
FILESYSTEM=""

# === PROFILE CONFIG (set by the sourcing entry point) ===
# CPUFREQ_GOVERNOR : optional kernel-cmdline default governor. Empty by default;
#                    auto-cpufreq manages the governor at runtime.
# TUNE_NAME        : name stamped into generated config files
CPUFREQ_GOVERNOR="${CPUFREQ_GOVERNOR:-}"
TUNE_NAME="${TUNE_NAME:-run-all-${PROFILE_NAME}.sh}"
KERNEL_FLAVOR="${KERNEL_FLAVOR:-}"
SECURE_BOOT="${SECURE_BOOT:-1}"

CONF_DIR="/etc/sysctl.d"
UDEV_DIR="/etc/udev/rules.d"
MODPROBE_DIR="/etc/modules-load.d"
FSTAB="/etc/fstab"
ENV_FILE="/etc/environment"
KCMDLINE="/etc/kernel/cmdline"

# Kernel cmdline parameters added in stage 2 (and verified in stages 4 and 5)
NEW_PARAMS=(transparent_hugepage=madvise)
# Plymouth: show the splash, hide boot messages, don't write a boot log
NEW_PARAMS+=(quiet splash plymouth.boot-log=/dev/null plymouth.nolog)
# Only add cpufreq.default_governor= if a value is set. auto-cpufreq manages the
# governor at runtime, so the kernel-cmdline default is usually omitted.
[[ -n "$CPUFREQ_GOVERNOR" ]] && NEW_PARAMS+=(cpufreq.default_governor="$CPUFREQ_GOVERNOR")

# Swap on zram (archinstall sets it up by default): zram is used when it's
# active or configured. zswap must be off with zram, or it keeps zram from
# being used effectively (Arch wiki); archinstall already adds the same
# parameter, this makes sure it's there.
ZRAM=0
if grep -q '^/dev/zram' /proc/swaps 2>/dev/null \
   || [[ -f /etc/systemd/zram-generator.conf || -f /usr/lib/systemd/zram-generator.conf ]]; then
  ZRAM=1
  NEW_PARAMS+=(zswap.enabled=0)
fi

PASS=0
FAIL=0
WARNINGS=()

# --------------- colors & output ------------------------------------------
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()   { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; PASS=$((PASS+1)); }
fail() { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; FAIL=$((FAIL+1)); WARNINGS+=("$*"); }
warn() { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
# NOTE: named section(), not head(), so it doesn't shadow /usr/bin/head
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
die()  { fail "$@"; exit 1; }
info() { printf '\n%s=== [%d/%d] %s ===%s\n' "$C_B" "$1" "$2" "$3" "$C_0"; }

# --------------- shared helpers -------------------------------------------
# Newest UKI in the ESP (the one built last), or empty
newest_uki() {
  local dir="${1:-/boot/EFI/Linux}"
  find "$dir" -maxdepth 1 -name '*.efi' -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-
}

# Print the .cmdline section embedded in a UKI
uki_cmdline() {
  local tmp
  tmp="$(mktemp)" || return 1
  if objcopy -O binary --only-section=.cmdline "$1" "$tmp" 2>/dev/null; then
    tr -d '\0' < "$tmp"
  fi
  rm -f "$tmp"
}

# systemd-boot names a UKI's boot entry after its file name (for example
# "arch-linux-cachyos.efi"), so loader.conf's "default" must use that exact name.
# Read it from the kernel's mkinitcpio preset; if the preset has no default_uki
# (yet), use the name stage 3 gives it: arch-<preset name>.efi
uki_entry_name() {
  local pkg="$1" val
  val="$(grep -m1 -E '^default_uki=' "/etc/mkinitcpio.d/${pkg}.preset" 2>/dev/null)"
  val="${val#default_uki=}"
  val="${val//\"/}"; val="${val//\'/}"
  if [[ -n "$val" ]]; then basename "$val"; else echo "arch-${pkg}.efi"; fi
}

# Write "default <entry>" + "timeout 0" to loader.conf, keeping its other lines
set_loader_default() {
  local conf="$1" entry="$2" tmp
  mkdir -p "$(dirname "$conf")"
  tmp="$(mktemp)"
  [[ -f "$conf" ]] && grep -vE '^(default|timeout)([[:space:]]|$)' "$conf" > "$tmp"
  printf 'default %s\ntimeout 0\n' "$entry" >> "$tmp"
  cat "$tmp" > "$conf"
  rm -f "$tmp"
  chmod 644 "$conf"
}

# Check that loader.conf's default really points at a bootable entry.
# $3 = "fail" or "warn": what a missing UKI counts as (stage 2 builds before the
# presets may have been switched to UKI, so there it's only a warning)
check_loader_default() {
  local conf="$1" entry="$2" missing="$3" uki_dir
  uki_dir="$(dirname "$(dirname "$conf")")/EFI/Linux"
  grep -qxF "default $entry" "$conf" \
    && ok "loader.conf default = $entry" \
    || fail "loader.conf default was not set to $entry"
  grep -qx "timeout 0" "$conf" \
    && ok "loader.conf timeout = 0" \
    || fail "loader.conf timeout was not set to 0"
  if [[ -f "$uki_dir/$entry" ]]; then
    ok "UKI present: $uki_dir/$entry"
  else
    "$missing" "default entry $entry has no UKI in $uki_dir"
  fi
  if command -v bootctl >/dev/null; then
    # bootctl prints each entry's name on an "id: <name>" line
    if bootctl --no-pager list 2>/dev/null | awk -v e="$entry" '$1 == "id:" && $2 == e { f = 1 } END { exit !f }'; then
      ok "bootctl lists the default entry $entry"
    else
      "$missing" "bootctl list has no entry with id $entry"
    fi
  fi
}

# Regenerate all initramfs images / UKIs with whichever tool is installed
regenerate_images() {
  if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
    if mkinitcpio -P; then ok "mkinitcpio -P regenerated all images"; else fail "mkinitcpio -P failed"; return 1; fi
  elif command -v dracut >/dev/null; then
    if dracut --regenerate-all; then ok "dracut regenerated all images"; else fail "dracut --regenerate-all failed"; return 1; fi
  else
    fail "no initramfs tool (mkinitcpio/dracut) found"; return 1
  fi
}

# Is $1 one of the space-separated words in $2? (whole words only: "quiet" must
# not match "foo=quiet", and dots aren't wildcards)
has_param() {
  [[ " $(tr -s '[:space:]' ' ' <<<"$2") " == *" $1 "* ]]
}

# Add NEW_PARAMS to /etc/kernel/cmdline. Sets CMDLINE_CHANGED=1 if it wrote anything.
CMDLINE_CHANGED=0
update_kernel_cmdline() {
  if [[ ! -f "$KCMDLINE" ]]; then
    # No cmdline file yet: start from the running kernel's command line, minus
    # the boot loader's own entries, which don't belong in a UKI
    mkdir -p "$(dirname "$KCMDLINE")"
    tr -s '[:space:]' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd ' ' > "$KCMDLINE"
    warn "$KCMDLINE didn't exist - created it from the running kernel's command line"
  fi
  local current added="" p
  current="$(cat "$KCMDLINE")"
  for p in "${NEW_PARAMS[@]}"; do
    if ! has_param "$p" "$current"; then
      current="$current $p"
      added="$added $p"
    fi
  done
  if [[ -n "$added" ]]; then
    current="$(sed -E 's/^ +//; s/ +/ /g; s/ +$//' <<<"$current")"
    echo "$current" > "$KCMDLINE"
    CMDLINE_CHANGED=1
    ok "kernel cmdline updated. Added:$added"
  else
    ok "all kernel cmdline params already present"
  fi
}

# Add the plymouth hook to mkinitcpio.conf. The Arch wiki rule: plymouth must
# come AFTER "systemd" and BEFORE "encrypt"/"sd-encrypt". It's inserted directly
# after "systemd", and the final order is checked before anything is written.
# Every case where the right position isn't certain is skipped with a warning.
ensure_plymouth_hook() {
  local conf=/etc/mkinitcpio.conf line i sys=-1 ply=-1 enc=-1
  local -a hooks new
  if [[ ! -f /usr/lib/initcpio/install/plymouth && ! -f /etc/initcpio/install/plymouth ]]; then
    warn "plymouth mkinitcpio hook not installed (Install.sh installs plymouth) - skipping"
    return 0
  fi
  if grep -qsE '^[[:space:]]*HOOKS=' /etc/mkinitcpio.conf.d/*.conf; then
    warn "HOOKS is overridden in /etc/mkinitcpio.conf.d/ - not touching it, add plymouth there by hand"
    return 0
  fi
  if [[ "$(grep -cE '^[[:space:]]*HOOKS=' "$conf")" -ne 1 ]]; then
    warn "expected exactly one active HOOKS= line in $conf - plymouth hook not added"
    return 0
  fi
  line="$(grep -E '^[[:space:]]*HOOKS=' "$conf")"
  if [[ ! "$line" =~ ^[[:space:]]*HOOKS=\(([^\)]*)\)[[:space:]]*(#.*)?$ ]]; then
    warn "HOOKS line isn't a single-line HOOKS=(...) - plymouth hook not added"
    return 0
  fi
  read -ra hooks <<<"${BASH_REMATCH[1]}"
  for i in "${!hooks[@]}"; do
    case "${hooks[$i]}" in
      systemd)              sys=$i ;;
      plymouth)             ply=$i ;;
      encrypt|sd-encrypt)   [[ $enc -lt 0 ]] && enc=$i ;;
    esac
  done
  if [[ $ply -ge 0 ]]; then
    if [[ $sys -lt $ply && ( $enc -lt 0 || $ply -lt $enc ) ]]; then
      ok "plymouth hook already present in the right position"
    else
      fail "plymouth hook is present but in the wrong position (must be after systemd, before (sd-)encrypt) - fix $conf by hand"
    fi
    return 0
  fi
  if [[ $sys -lt 0 ]]; then
    warn "no systemd hook (udev-based initramfs) - plymouth hook not added, position isn't certain"
    return 0
  fi
  new=("${hooks[@]:0:sys+1}" plymouth "${hooks[@]:sys+1}")
  # re-check the order on the new list before writing
  sys=-1; ply=-1; enc=-1
  for i in "${!new[@]}"; do
    case "${new[$i]}" in
      systemd) sys=$i ;; plymouth) ply=$i ;;
      encrypt|sd-encrypt) [[ $enc -lt 0 ]] && enc=$i ;;
    esac
  done
  if [[ $sys -lt $ply && ( $enc -lt 0 || $ply -lt $enc ) ]]; then
    sed -i -E "s/^([[:space:]]*HOOKS=\()[^)]*\)/\1${new[*]})/" "$conf"
    ok "added plymouth hook: HOOKS=(${new[*]})"
  else
    fail "could not place plymouth safely - $conf left unchanged"
  fi
}

# For every mkinitcpio preset: copy a missing vmlinuz into /boot and repoint
# default_uki/fallback_uki paths that live in a non-existent directory.
# $1 = UKI directory. Sets NEED_REGEN=1 when it changed anything.
NEED_REGEN=0
sync_kernel_images() {
  local uki_dir="$1" preset kver_line kver name mod_dir d kname key line val newpath
  for preset in /etc/mkinitcpio.d/*.preset; do
    [[ -f "$preset" ]] || continue
    kver_line=$(grep -m1 -E '^ALL_kver=' "$preset")
    [[ -z "$kver_line" ]] && continue
    kver="${kver_line#ALL_kver=}"
    kver="${kver#\"}"; kver="${kver%\"}"
    if [[ ! -f "$kver" ]]; then
      name="$(basename "$preset" .preset)"
      mod_dir=""
      for d in /usr/lib/modules/*/; do
        [[ -f "${d}pkgbase" && "$(cat "${d}pkgbase")" == "$name" ]] && { mod_dir="$d"; break; }
      done
      if [[ -z "$mod_dir" ]]; then
        kname="${name#linux-}"; kname="${kname#linux}"
        for d in /usr/lib/modules/*/; do
          if [[ -n "$kname" && "$(basename "$d")" == *"$kname"* && -f "${d}vmlinuz" ]]; then
            mod_dir="$d"; break
          fi
        done
      fi
      if [[ -n "$mod_dir" && -f "${mod_dir}vmlinuz" ]]; then
        cp "${mod_dir}vmlinuz" "$kver"
        ok "copied ${mod_dir}vmlinuz -> $kver"
        NEED_REGEN=1
      else
        warn "could not find vmlinuz for $name in /usr/lib/modules/"
      fi
    else
      ok "$kver already present"
    fi

    # fix UKI paths that point to a non-existent directory (e.g. /efi/ instead of /boot/)
    [[ -d "$uki_dir" ]] || continue
    for key in default_uki fallback_uki; do
      line=$(grep -m1 -E "^${key}=" "$preset")
      [[ -z "$line" ]] && continue
      val="${line#${key}=}"
      val="${val#\"}"; val="${val%\"}"
      if [[ ! -d "$(dirname "$val")" ]]; then
        newpath="${uki_dir}/$(basename "$val")"
        sed -i "s|^${key}=.*|${key}=\"${newpath}\"|" "$preset"
        ok "fixed ${key} in $(basename "$preset"): $val -> $newpath"
        NEED_REGEN=1
      fi
    done
  done
}


# --------------- root -----------------------------------------------------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
  fi
}
require_root "$@"

# === ARG PARSING (none; the profile comes from the entry point) ===
if [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  exit 2
fi

# =====================================================================
info 1 5 "CachyOS Repository Setup"

if ! grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
  section "Adding CachyOS repos (official installer)"
  (
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cd "$TMP" || exit 1
    curl -fsSL --retry 3 https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz \
      || { fail "download failed"; exit 1; }
    tar xf cachyos-repo.tar.xz || { fail "extract failed"; exit 1; }
    cd cachyos-repo || exit 1
    ./cachyos-repo.sh || { fail "official installer failed"; exit 1; }
  ) || die "CachyOS repo installer failed"
else
  ok "CachyOS repo already present in /etc/pacman.conf"
fi

section "Verification"
OK=1
if grep -qE '^\[cachyos' /etc/pacman.conf; then
  ok "cachyos repo enabled in /etc/pacman.conf"
else
  fail "cachyos repo NOT found in /etc/pacman.conf"; OK=0
fi
if pacman -Q cachyos-keyring >/dev/null 2>&1; then
  ok "cachyos-keyring installed"
else
  warn "cachyos-keyring not installed - run: pacman -Sy cachyos-keyring"
fi
if pacman -Q cachyos-mirrorlist >/dev/null 2>&1; then
  ok "cachyos-mirrorlist installed"
fi
[[ $OK -eq 1 ]] || die "CachyOS repository setup incomplete"

# =====================================================================
info 2 5 "CachyOS Kernel Install"

FLAVOR="$KERNEL_FLAVOR"
PKG_BASE="linux-cachyos"
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  PKG_BASE="linux-cachyos-${FLAVOR}"
fi
KNOWN_FLAVORS=(bore bmq deckify eevdf lts hardened rc server rt-bore)
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  if ! printf '%s\n' "${KNOWN_FLAVORS[@]}" | grep -qx "$FLAVOR"; then
    warn "unknown flavor '$FLAVOR' - only proceed if the package linux-cachyos-$FLAVOR exists"
  fi
fi
# ---------- pre-flight checks ----------
section "Pre-flight checks"

[[ "$(uname -m)" == "x86_64" ]] || { fail "CachyOS kernels are x86_64 only"; exit 1; }
command -v pacman >/dev/null || { fail "pacman not found - this script is for Arch Linux"; exit 1; }

if ! grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
  fail "CachyOS repositories not configured in /etc/pacman.conf"
  cat <<'EOF'
  Set them up first with the official installer:
    curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
    tar xvf cachyos-repo.tar.xz && cd cachyos-repo
    sudo ./cachyos-repo.sh
  (see https://wiki.cachyos.org/features/optimized_repos/)
EOF
  exit 1
fi
ok "CachyOS repository present in /etc/pacman.conf"

if ! pacman -Q cachyos-keyring >/dev/null 2>&1; then
  fail "cachyos-keyring not installed - repository setup incomplete"
  exit 1
fi
ok "cachyos-keyring installed"

LD_SO="/usr/lib/ld-linux-x86-64.so.2"
if [[ -x "$LD_SO" ]]; then
  if ! "$LD_SO" --help 2>/dev/null | grep -q 'x86-64-v3 (supported'; then
    fail "CPU does not support x86-64-v3 - required by CachyOS kernels"
    exit 1
  fi
  ok "CPU supports x86-64-v3 (minimum for CachyOS kernels)"
fi

ESP=""
for _e in /boot /efi /boot/efi; do
  if [[ -d "$_e/EFI/Linux" ]]; then ESP="$_e"; break; fi
done
if [[ -z "$ESP" ]]; then
  fail "systemd-boot UKI directory not found (looked in /boot, /efi, /boot/efi)"
  exit 1
fi
[[ -d "$ESP/EFI/systemd" ]] || warn "systemd-boot loader not found in $ESP/EFI/systemd"
ok "systemd-boot + UKI dir found: $ESP/EFI/Linux"

# ---------- target info ----------
section "Target"
warn "Kernel package : $PKG_BASE"
warn "Running kernel : $(uname -r) ($(cat "/usr/lib/modules/$(uname -r)/pkgbase" 2>/dev/null || echo unknown))"
if pacman -Q "$PKG_BASE" >/dev/null 2>&1; then
  warn "$PKG_BASE already installed: $(pacman -Q "$PKG_BASE" | awk '{print $2}') (will be updated)"
fi

# detect driver modules CachyOS ships prebuilt for
EXTRA_PKGS=()
NVIDIA_DRIVER=""
if pacman -Q nvidia-open >/dev/null 2>&1; then NVIDIA_DRIVER="nvidia-open"
elif pacman -Q nvidia >/dev/null 2>&1; then NVIDIA_DRIVER="nvidia"; fi
if [[ -n "$NVIDIA_DRIVER" ]]; then
  EXTRA_PKGS+=("$PKG_BASE-$NVIDIA_DRIVER")
  warn "NVIDIA driver '$NVIDIA_DRIVER' detected -> adding ${PKG_BASE}-${NVIDIA_DRIVER}"
fi
if pacman -Q zfs >/dev/null 2>&1; then
  EXTRA_PKGS+=("$PKG_BASE-zfs")
  warn "zfs detected -> adding ${PKG_BASE}-zfs"
fi

# ---------- install ----------
section "Install $PKG_BASE"

# Refresh the package DB if the target package isn't known yet. A full -Syu,
# never a bare -Sy: that would be a partial upgrade.
if ! pacman -Si "$PKG_BASE" >/dev/null 2>&1; then
  warn "package not found in sync database - refreshing and upgrading (pacman -Syu)"
  pacman -Syu --noconfirm || { fail "pacman -Syu failed"; exit 1; }
fi

INSTALL=("$PKG_BASE" "$PKG_BASE-headers" "${EXTRA_PKGS[@]}")
if pacman -S --needed --noconfirm "${INSTALL[@]}"; then
  ok "install transaction completed"
else
  fail "pacman -S failed (see above)"; exit 1
fi

# ---------- device-specific setup (e.g. Steam Deck hardware support) ----------
if declare -F device_setup >/dev/null; then
  section "Device support ($PROFILE_NAME)"
  device_setup
fi

# ---------- sync vmlinuz to /boot if missing ----------
section "Sync kernel images to /boot"
sync_kernel_images "$ESP/EFI/Linux"

# ---------- kernel cmdline + plymouth hook (BEFORE the images are built) ----------
# Making these changes now means the single build below already includes them,
# so no later stage needs to rebuild everything a second time.
section "Kernel cmdline"
update_kernel_cmdline

section "Plymouth hook"
ensure_plymouth_hook

# ---------- regenerate initramfs / UKIs ----------
section "Regenerate initramfs / UKIs"
regenerate_images || exit 1
NEED_REGEN=0

# ---------- configure systemd-boot default entry ----------
section "Configure systemd-boot default entry"
LOADER_CONF="$ESP/loader/loader.conf"
# Exact entry name (no wildcard): set again in stage 3, after the presets are on UKI
DEFAULT_ENTRY="$(uki_entry_name "$PKG_BASE")"
set_loader_default "$LOADER_CONF" "$DEFAULT_ENTRY"
ok "loader.conf default entry set to '$DEFAULT_ENTRY', timeout 0 (hold Space at boot for the menu)"

# ---------- verification ----------
section "Verification"
NEW_VER="$(pacman -Q "$PKG_BASE" 2>/dev/null | awk '{print $2}')"
ok "installed: $PKG_BASE ${NEW_VER:-?}"
check_loader_default "$LOADER_CONF" "$DEFAULT_ENTRY" warn

# ---------- old kernel removal ----------
# Keeps the newly installed kernel ($PKG_BASE). Every other kernel is removed:
# immediately when none of them is the running one, otherwise deferred to the
# next boot (once $PKG_BASE is actually running). The deferred path installs a
# one-shot systemd unit whose script removes the old kernel(s) and then deletes
# itself, its config and its unit (removed, not just disabled).

running_base() {
  local d="/usr/lib/modules/$(uname -r)"
  if [[ -f "$d/pkgbase" ]]; then
    cat "$d/pkgbase"
  else
    pacman -Qo "$d" 2>/dev/null | awk '{print $5}'
  fi
}

kernels_list() {
  local d kver base
  for d in /usr/lib/modules/*/; do
    [[ -d "$d" ]] || continue
    kver="$(basename "$d")"
    base=""
    if [[ -f "$d/pkgbase" ]]; then
      base="$(cat "$d/pkgbase")"
    else
      base="$(pacman -Qo "$d" 2>/dev/null | awk '{print $5}')"
    fi
    [[ -n "$base" ]] && printf '%s\t%s\n' "$base" "$kver"
  done
}

remove_one() {
  local base="$1" mod
  local pkgs=("$base")
  pacman -Q "$base-headers" >/dev/null 2>&1 && pkgs+=("$base-headers")
  pacman -Q "$base-dbg"     >/dev/null 2>&1 && pkgs+=("$base-dbg")
  for mod in nvidia nvidia-open zfs; do
    pacman -Q "$base-$mod" >/dev/null 2>&1 && pkgs+=("$base-$mod")
  done
  echo "Removing: ${pkgs[*]}"
  if pacman -Rns --noconfirm "${pkgs[@]}"; then
    ok "removed $base"
  else
    fail "failed to remove $base"
  fi
}

# Arm a self-removing one-shot that prunes the old kernels on the next boot.
schedule_old_kernel_removal() {
  local newbase="$1"; shift
  local -a bases=("$@")
  local conf="/etc/remove-old-kernel.conf"
  local unit="/etc/systemd/system/remove-old-kernel.service"
  local helper="/usr/local/bin/remove-old-kernel.sh"

  local q="" b
  for b in "${bases[@]}"; do q+=" $(printf '%q' "$b")"; done

  cat > "$conf" <<EOF
# Generated by run-all-common.sh - kernel(s) to delete after booting $newbase.
# The helper removes these, then deletes itself, this config and its unit.
NEW_BASE=$(printf '%q' "$newbase")
REMOVE=(${q# })
EOF
  chmod 600 "$conf"

  cat > "$helper" <<'HELPER_BODY'
#!/usr/bin/env bash
# One-shot cleanup: remove the old kernel(s) listed in /etc/remove-old-kernel.conf,
# but only once the new kernel is the one actually running. Then delete this
# script, its config and its systemd unit (removed, not just disabled).
set -uo pipefail

CONF="/etc/remove-old-kernel.conf"
UNIT="/etc/systemd/system/remove-old-kernel.service"
SELF="/usr/local/bin/remove-old-kernel.sh"

log() { printf '[remove-old-kernel] %s\n' "$*"; }

[[ -f "$CONF" ]] || { log "no $CONF; nothing to do"; exit 0; }
# shellcheck disable=SC1090
source "$CONF"

RUN_BASE=""
if [[ -f "/usr/lib/modules/$(uname -r)/pkgbase" ]]; then
  RUN_BASE="$(cat "/usr/lib/modules/$(uname -r)/pkgbase")"
else
  RUN_BASE="$(pacman -Qo "/usr/lib/modules/$(uname -r)" 2>/dev/null | awk '{print $5}')"
fi

if [[ -z "${RUN_BASE:-}" || "$RUN_BASE" != "${NEW_BASE:-}" ]]; then
  log "running kernel is '${RUN_BASE:-unknown}', not '${NEW_BASE:-?}' - will retry after the next boot"
  exit 0
fi

failed=0
for base in "${REMOVE[@]}"; do
  [[ -z "$base" || "$base" == "$RUN_BASE" ]] && continue
  pkgs=("$base")
  for suffix in headers dbg nvidia nvidia-open zfs; do
    pacman -Q "$base-$suffix" >/dev/null 2>&1 && pkgs+=("$base-$suffix")
  done
  log "removing: ${pkgs[*]}"
  if pacman -Rns --noconfirm "${pkgs[@]}"; then
    log "removed $base"
  else
    log "failed to remove $base"
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  log "some removals failed - keeping the unit armed for another attempt"
  exit 1
fi

log "cleanup complete - removing unit, config and this script"
systemctl disable remove-old-kernel.service >/dev/null 2>&1 || true
rm -f "$UNIT" "$CONF" "$SELF"
systemctl daemon-reload >/dev/null 2>&1 || true
log "done"
HELPER_BODY
  chmod 755 "$helper"

  cat > "$unit" <<'UNIT_BODY'
[Unit]
Description=Remove old kernel(s) after the kernel switch (one-shot)
After=multi-user.target
ConditionPathExists=/etc/remove-old-kernel.conf

[Service]
Type=oneshot
ExecStart=/usr/local/bin/remove-old-kernel.sh

[Install]
WantedBy=multi-user.target
UNIT_BODY
  chmod 644 "$unit"

  systemctl daemon-reload
  if systemctl enable remove-old-kernel.service >/dev/null 2>&1; then
    ok "old kernel(s) [${bases[*]}] will be removed automatically after the next reboot"
  else
    fail "could not enable post-reboot kernel removal (remove-old-kernel.service)"
  fi
}

section "Old kernel removal"

RUN_BASE="$(running_base)"
TARGETS=()
while IFS=$'\t' read -r base kver; do
  [[ -z "$base" ]] && continue
  [[ "$base" == "$PKG_BASE" ]] && continue
  case " ${TARGETS[*]} " in *" $base "*) continue ;; esac
  TARGETS+=("$base")
done < <(kernels_list)

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  ok "No old kernels to remove (only '$PKG_BASE' present)"
else
  DEFER=0
  [[ -z "$RUN_BASE" ]] && DEFER=1
  for b in "${TARGETS[@]}"; do [[ "$b" == "$RUN_BASE" ]] && DEFER=1; done
  if [[ $DEFER -eq 1 ]]; then
    warn "The running kernel '$RUN_BASE' is among the old kernels; removal is deferred to after reboot"
    schedule_old_kernel_removal "$PKG_BASE" "${TARGETS[@]}"
  else
    echo "Installed kernels to remove now: ${TARGETS[*]}"
    for b in "${TARGETS[@]}"; do remove_one "$b"; done
  fi
fi

# ---------- summary ----------
section "DONE"
cat <<EOF
  Installed kernel : $PKG_BASE ${NEW_VER:-?}
  Boot default     : systemd-boot -> ${DEFAULT_ENTRY}  ($LOADER_CONF)

REBOOT REQUIRED - the CachyOS kernel will load on next boot.
If old kernel removal was deferred, it runs automatically on that boot and
the cleanup script then deletes itself. This boot is your last known-good one,
so confirm CachyOS boots before relying on fallback removal only.
EOF

# =====================================================================
info 3 5 "Fix UKI Setup"

# ---------- find ESP ----------
section "Pre-flight checks"
ESP=""
for _e in /boot /efi /boot/efi; do
  if [[ -d "$_e/EFI/Linux" ]]; then ESP="$_e"; break; fi
done
[[ -z "$ESP" ]] && die "No UKI directory found (looked in /boot, /efi, /boot/efi)"
UKI_DIR="$ESP/EFI/Linux"
ok "UKI directory: $UKI_DIR"

# ---------- check presets ----------
mapfile -t PRESETS < <(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' -type f 2>/dev/null | sort)
[[ ${#PRESETS[@]} -eq 0 ]] && die "No presets found in /etc/mkinitcpio.d"
ok "Found ${#PRESETS[@]} preset(s): $(basename -a "${PRESETS[@]}" | tr '\n' ' ')"

# ---------- enable UKI for presets using default_image ----------
section "Enabling UKI for presets using traditional initramfs"
SWITCHED=0
NEED_REGEN=0
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

  section "Updating $NAME"

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
  NEED_REGEN=1
done

if [[ $SWITCHED -eq 0 ]]; then
  ok "All presets already using UKI"
fi

# ---------- show presets ----------
section "Current presets"
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
section "Syncing kernel images to /boot"
sync_kernel_images "$UKI_DIR"

# ---------- regenerate (only if a preset was actually changed) ----------
if [[ $NEED_REGEN -eq 1 ]]; then
  section "Regenerating all UKIs"
  regenerate_images || die "image regeneration failed"
  NEED_REGEN=0
else
  ok "No preset changes; skipping UKI regeneration (images already built in stage 2)"
fi

# ---------- systemd-boot default entry (again, now that every preset uses UKI) ----------
# Stage 2 set it before this stage switched the presets to UKI, so the entry
# name may only be final now.
section "systemd-boot default entry"
DEFAULT_ENTRY="$(uki_entry_name "$PKG_BASE")"
set_loader_default "$ESP/loader/loader.conf" "$DEFAULT_ENTRY"
ok "loader.conf default entry set to '$DEFAULT_ENTRY'"
check_loader_default "$ESP/loader/loader.conf" "$DEFAULT_ENTRY" fail

# ---------- secure boot: create keys, enroll (-m), sign (sbctl installed by Install.sh) ----------
section "Secure Boot setup (sbctl)"
if [[ "$SECURE_BOOT" != "1" ]]; then
  warn "Secure Boot skipped for this profile ($PROFILE_NAME)"
elif ! command -v sbctl >/dev/null; then
  warn "sbctl not installed (Install.sh installs it) - skipping Secure Boot setup"
else
  # Marker written after a successful enroll, so a re-run can tell enrolled keys
  # from keys that were only created
  SB_ENROLLED=/var/lib/sbctl/.enrolled-by-run-all
  if [[ ! -d /var/lib/sbctl/keys ]]; then
    section "Creating Secure Boot keys"
    if sbctl create-keys; then
      ok "created Secure Boot keys in /var/lib/sbctl/keys"
    else
      die "failed to create Secure Boot keys"
    fi
  else
    ok "Secure Boot keys already exist in /var/lib/sbctl/keys"
  fi

  SB_STATUS="$(sbctl status 2>/dev/null || true)"
  # Keys can only be enrolled while the firmware is in Setup Mode
  if grep -qi 'setup mode:.*disabled' <<< "$SB_STATUS"; then
    if [[ -f "$SB_ENROLLED" ]]; then
      ok "Setup Mode is off - keys were enrolled by an earlier run, nothing to enroll"
    else
      fail "the firmware isn't in Setup Mode, so the keys can't be enrolled - switch Secure Boot to Setup Mode in the firmware settings and run this again"
    fi
  else
    section "Enrolling Secure Boot keys (Microsoft keys included via -m)"
    # Try to enroll; if immutable vars block, unfreeze and retry once
    for f in /sys/firmware/efi/efivars/PK* /sys/firmware/efi/efivars/KEK* /sys/firmware/efi/efivars/db*; do
      [[ -e "$f" ]] && chattr -i "$f" 2>/dev/null || true
    done
    if sbctl enroll-keys -m; then
      touch "$SB_ENROLLED"
      ok "enrolled keys with Microsoft keys (-m)"
      warn "a reboot may be required for the firmware to activate the keys"
    else
      fail "failed to enroll Secure Boot keys (-m) (continuing)"
    fi
    for f in /sys/firmware/efi/efivars/PK* /sys/firmware/efi/efivars/KEK* /sys/firmware/efi/efivars/db*; do
      [[ -e "$f" ]] && chattr +i "$f" 2>/dev/null || true
    done
  fi

  section "Signing EFI binaries with sbctl"
  # `sbctl verify` prints "✗ /path/file.efi is not signed": the path is field 2.
  # Every UKI is also signed explicitly, so nothing depends on that output format.
  # -s saves each file in sbctl's database so its mkinitcpio hook re-signs it
  # automatically whenever the image is rebuilt.
  mapfile -t TO_SIGN < <(
    { sbctl verify 2>/dev/null | awk '/^✗/ {print $2}'
      find "$UKI_DIR" -maxdepth 1 -name '*.efi' -type f 2>/dev/null
    } | sort -u
  )
  SIGN_FAIL=0
  for efi in "${TO_SIGN[@]}"; do
    [[ -f "$efi" ]] || continue
    if sbctl sign -s "$efi" >/dev/null 2>&1; then
      ok "signed: $efi"
    else
      fail "could not sign: $efi"; SIGN_FAIL=1
    fi
  done
  [[ ${#TO_SIGN[@]} -eq 0 ]] && warn "no EFI binaries found to sign"
  # (saved first: piping straight into grep -q can end early and hide a failure)
  SB_VERIFY="$(sbctl verify 2>/dev/null || true)"
  if grep -q '^✗' <<<"$SB_VERIFY"; then
    fail "sbctl verify still reports unsigned files:"
    grep '^✗' <<<"$SB_VERIFY"
  elif [[ $SIGN_FAIL -eq 0 ]]; then
    ok "sbctl verify: everything signed"
  fi
fi

# ---------- verify ----------
section "Verification"
mapfile -t UKIS < <(find "$UKI_DIR" -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
if [[ ${#UKIS[@]} -gt 0 ]]; then
  for u in "${UKIS[@]}"; do
    ok "UKI: $(basename "$u")"
  done
else
  warn "no UKI files found in $UKI_DIR"
fi

if command -v bootctl >/dev/null; then
  # each boot entry has exactly one "id:" line
  COUNT=$(bootctl --no-pager list 2>/dev/null | awk '$1 == "id:"' | wc -l)
  if [[ "$COUNT" -gt 0 ]]; then
    ok "bootctl lists $COUNT boot entry/entries"
  else
    warn "bootctl did not list any kernel entries - check manually"
  fi
fi

section "DONE"
if [[ "$SECURE_BOOT" == "1" ]]; then
  cat <<EOF
  UKI enabled; Secure Boot keys ensured and enrolled with -m (when sbctl is present).
  REBOOT REQUIRED to boot from the new UKIs and to finalize key enrollment.
EOF
else
  cat <<EOF
  UKI enabled; Secure Boot skipped for this profile.
  REBOOT REQUIRED to boot from the new UKIs.
EOF
fi
# =====================================================================
info 4 5 "Performance Tuning"

# =====================================================================
section "A. sysctl + I/O"

# A.1 sysctl config
SYSCTL_FILE="$CONF_DIR/99-perf-tune.conf"
cat > "$SYSCTL_FILE" <<EOF
# Generated by ${TUNE_NAME}
# Write dirty pages out in smaller batches (fewer stalls when copying big files)
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# NMI watchdog off: only used to debug kernel hangs; saves a little CPU and power
kernel.nmi_watchdog = 0
# Network: BBR congestion control with the fq qdisc (affects what you send)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# Bigger buffers for fast long-distance transfers
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
# Swap on zram (compressed RAM): swapping to it is cheap, so the kernel should
# prefer it over dropping file cache. Values from the Arch wiki's zram page
# (what Pop!_OS uses). Only set when zram is set up (ZRAM, detected at the top):
# with swap on a disk these values would be wrong, so the kernel defaults stay.
if [[ $ZRAM -eq 1 ]]; then
  cat >> "$SYSCTL_FILE" <<'EOF'
# Swap on zram
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
  ok "zram swap found - zram swap settings added"
else
  warn "no zram swap found - swap settings left at the kernel defaults"
fi
sysctl -p "$SYSCTL_FILE" >/dev/null
# (THP has no sysctl key: it's set at runtime in B and by the kernel cmdline in F)

# A.3 Hard disks: scheduler + bigger readahead (runtime + udev persistence).
# NVMe and SATA SSDs keep the kernel defaults (already the best choice for them).
# Detect which schedulers this kernel provides, then only emit rules that
# reference available schedulers. mq-deadline is used for rotational disks
# (deadline/none as fallbacks); bfq isn't used.
AVAIL_SCHEDS=""
for d in /sys/block/*; do
  [[ -f "$d/queue/scheduler" ]] || continue
  AVAIL_SCHEDS="$AVAIL_SCHEDS $(cat "$d/queue/scheduler")"
done
HDD_SCHED=""
for s in mq-deadline deadline none; do
  if grep -qw "$s" <<<"$AVAIL_SCHEDS"; then HDD_SCHED="$s"; break; fi
done
if [[ -n "$HDD_SCHED" ]]; then
  ok "HDD scheduler available on this kernel: $HDD_SCHED"
else
  warn "no HDD scheduler candidate (mq-deadline) found on this kernel"
fi

UDEV_FILE="$UDEV_DIR/60-ioschedulers.rules"
{
  printf '# Generated by %s\n' "${TUNE_NAME}"
  if [[ -n "$HDD_SCHED" ]]; then
    printf '# Rotational disks -> %s scheduler, 8 MiB readahead\n' "$HDD_SCHED"
    printf 'ACTION=="add|change", KERNEL=="sd[a-z]*|vd[a-z]*|mmcblk*", ENV{DEVTYPE}=="disk", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="%s", ATTR{queue/read_ahead_kb}="8192"\n' "$HDD_SCHED"
  else
    printf '# No suitable HDD scheduler available on this kernel; rule omitted\n'
  fi
} > "$UDEV_FILE"

if [[ -n "$HDD_SCHED" ]]; then
  for d in /sys/block/sd[a-z]* /sys/block/vd[a-z]* /sys/block/mmcblk*; do
    [[ -d "$d" ]] || continue
    [[ "$(cat "$d/queue/rotational" 2>/dev/null)" == "1" ]] || continue
    echo "$HDD_SCHED" > "$d/queue/scheduler" 2>/dev/null
    echo 8192 > "$d/queue/read_ahead_kb" 2>/dev/null
  done
fi
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=block >/dev/null 2>&1 || true

# A.4 BBR module
if sysctl net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
  echo "tcp_bbr" > "$MODPROBE_DIR/bbr.conf"
else
  if modprobe tcp_bbr 2>/dev/null; then
    echo "tcp_bbr" > "$MODPROBE_DIR/bbr.conf"
  else
    warn "tcp_bbr module unavailable; BBR setting will be inert until kernel supports it"
  fi
fi

# =====================================================================
section "B. THP (runtime + tmpfiles)"

# THP (defer+madvise exists only on newer kernels; fall back to madvise)
THP_DEFRAG_TARGET="defer+madvise"
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null \
  || { THP_DEFRAG_TARGET="madvise"; echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null; }
# The defrag setting has no boot parameter: a tmpfiles entry sets it at every boot
THP_TMPFILES="/etc/tmpfiles.d/thp-defrag.conf"
printf '# Generated by %s\nw /sys/kernel/mm/transparent_hugepage/defrag - - - - %s\n' \
  "$TUNE_NAME" "$THP_DEFRAG_TARGET" > "$THP_TMPFILES"
ok "THP defrag = $THP_DEFRAG_TARGET, kept after reboots via $THP_TMPFILES"

# =====================================================================
section "C. Install packages (official repos)"

# irqbalance only on the desktop: on the laptop and the Deck it wakes the CPU
# for little gain. (ananicy-cpp isn't used: no measurable gain, and the BORE
# scheduler's developer links it to stutter in games.)
PKGS=()
[[ "$PROFILE_NAME" == "desktop" ]] && PKGS+=(irqbalance)
# lib32-* packages only exist on x86_64
if [[ "$(uname -m)" == "x86_64" ]]; then
  PKGS+=(lib32-gamemode lib32-mangohud)
fi
# gamemode and mangohud (native) are installed by Install.sh; only the lib32-*
# variants are handled here.
MISSING=()
for p in "${PKGS[@]}"; do
  pacman -Q "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Installing: ${MISSING[*]}"
  if pacman -S --noconfirm --needed "${MISSING[@]}"; then
    ok "pacman install completed"
  else
    fail "pacman install had errors (see above)"
  fi
else
  ok "All packages already installed"
fi

# Proton-CachyOS (CachyOS repo, added in stage 1): pick it per game in Steam
# (Properties > Compatibility); Valve's Proton stays the default. Installed on
# its own, so a problem with it doesn't block the packages above.
if pacman -Q proton-cachyos-slr >/dev/null 2>&1; then
  ok "proton-cachyos-slr already installed"
elif pacman -S --noconfirm --needed proton-cachyos-slr; then
  ok "installed proton-cachyos-slr (Proton-CachyOS)"
else
  fail "could not install proton-cachyos-slr"
fi

# NTSync: Windows-style synchronization in the kernel (6.14+), used by
# Proton-CachyOS, GE-Proton and Wine 10.16+ for smoother frame times. The module
# isn't loaded automatically, so load it at every boot (and now).
NTSYNC_CONF="$MODPROBE_DIR/ntsync.conf"
echo "ntsync" > "$NTSYNC_CONF"
if modprobe ntsync 2>/dev/null; then
  ok "ntsync loaded, and loaded at every boot via $NTSYNC_CONF"
else
  warn "ntsync can't be loaded on the running kernel - it loads at boot on the CachyOS kernel ($NTSYNC_CONF)"
fi

# =====================================================================
section "D. Enable services"

enable_svc() {
  local svc="$1"
  if systemctl cat "${svc}.service" >/dev/null 2>&1; then
    if systemctl enable --now "$svc.service" >/dev/null 2>&1; then
      ok "$svc.service enabled + started"
    else
      fail "$svc.service enable/start failed"
    fi
  else
    warn "$svc.service unit not found (package missing?)"
  fi
}
# gamemoded needs no enabling: games start it on demand (over D-Bus) through
# gamemoderun, so no lingering user session is kept running for it.
if [[ "$PROFILE_NAME" == "desktop" ]]; then
  enable_svc irqbalance
else
  ok "irqbalance not used on the $PROFILE_NAME (saves battery)"
fi

# =====================================================================
section "E. fstab noatime (REBOOT required)"

# Auto-detect local filesystems from fstab (unless FILESYSTEM is set)
if [[ -z "$FILESYSTEM" ]]; then
  _skip_fs='^(proc|sysfs|tmpfs|devtmpfs|devpts|devfs|cgroup[0-9]*|securityfs|debugfs|tracefs|pstore|bpf|autofs|hugetlbfs|mqueue|configfs|fusectl|efivarfs|binfmt_misc|rpc_pipefs|ramfs|overlay)$'
  _skip_net='^(nfs[0-9]?|cifs|smb[0-9]?|sshfs|afs|9p|fuse[.]sshfs|fuse[.]portal)$'
  FILESYSTEM=$(awk -v s="$_skip_fs" -v n="$_skip_net" \
    '!/^[[:space:]]*#/ && NF>=4 && $3 !~ s && $3 !~ n {print $3}' "$FSTAB" | sort -u | tr '\n' ' ')
  FILESYSTEM="${FILESYSTEM% }"
fi
FS_REGEX="^(${FILESYSTEM// /|})$"

# Convert relatime -> noatime only for the matched filesystems
BEFORE=$(awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,relatime/' "$FSTAB" | wc -l)
TMP=$(mktemp)
awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,relatime/ { sub(/rw,relatime/, "rw,noatime") } { print }' "$FSTAB" > "$TMP"
AFTER=$(awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,noatime/' "$TMP" | wc -l)
if [[ "$BEFORE" -gt 0 ]]; then
  cat "$TMP" > "$FSTAB"
  chmod 644 "$FSTAB"
  ok "Changed $BEFORE mount(s) [${FILESYSTEM// /, }] from relatime to noatime in $FSTAB"
elif [[ "$AFTER" -gt 0 ]]; then
  ok "fstab already uses noatime ($AFTER mount(s)) - nothing to change"
else
  fail "Did not find any relatime entries to change (filesystems: ${FILESYSTEM:-none})"
fi
rm -f "$TMP"

# =====================================================================
section "F. Kernel cmdline (REBOOT required)"

# Normally already done in stage 2 (before the images were built), so this is a
# no-op; it only rebuilds if a param is somehow still missing.
CMDLINE_CHANGED=0
update_kernel_cmdline
if [[ $CMDLINE_CHANGED -eq 1 ]]; then
  regenerate_images
fi

# =====================================================================
section "G. /etc/environment"

# Older versions set RADV_PERFTEST=gpl (Mesa's default since 23.1) and
# MESA_NO_ERROR=1 (no GL error checking for every app, which can turn app bugs
# into crashes) here. Neither is set anymore; remove them if they're present.
if [[ -f "$ENV_FILE" ]] && grep -qE '^(RADV_PERFTEST|MESA_NO_ERROR)=' "$ENV_FILE"; then
  sed -i -E '/^(RADV_PERFTEST|MESA_NO_ERROR)=/d' "$ENV_FILE"
  ok "removed RADV_PERFTEST / MESA_NO_ERROR from $ENV_FILE"
else
  ok "$ENV_FILE has no RADV_PERFTEST / MESA_NO_ERROR"
fi

# =====================================================================
section "H. Audio (HDA power-save) (REBOOT required for HDA)"

# H.1 HDA codec power-save disable - prevents HDMI audio crackle/pop on resume.
# Desktop only: on the laptop and the Deck it would keep the audio chip awake
# and cost battery.
HDA_CONF="/etc/modprobe.d/audio-disable-power-save.conf"
if [[ "$PROFILE_NAME" != "desktop" ]]; then
  ok "HDA power-save left on ($PROFILE_NAME: saves battery)"
elif [[ -f "$HDA_CONF" ]] && grep -q "power_save=0" "$HDA_CONF"; then
  ok "HDA power-save config already present"
else
  tee "$HDA_CONF" > /dev/null <<'EOF'
# Disable HDA codec power-saving - prevents HDMI audio crackling/popping
# Default power_save=10 lets the HDA codec enter D3 after 10s of silence,
# which can produce an audible pop on resume from HDMI/DP outputs.
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
EOF
  chmod 644 "$HDA_CONF"
  ok "Wrote $HDA_CONF (requires reboot to apply to snd_hda_intel)"
fi

# H.2 PipeWire: lower default quantum from 1024 to 512 (~21ms -> ~10ms latency)
# for apps that don't ask for their own buffer size. The min/max limits keep
# PipeWire's defaults, so low-latency apps and power-saving players still work.
# No impact on audio quality, only buffer size. Negligible CPU cost on modern hw.
PIPEWIRE_CONF="/etc/pipewire/pipewire.conf.d/99-low-latency.conf"
mkdir -p "$(dirname "$PIPEWIRE_CONF")"
tee "$PIPEWIRE_CONF" > /dev/null <<'PWCONF'
# Lower default PipeWire quantum for reduced audio latency
# 512 samples @ 48 kHz = ~10.7 ms (was 1024 / ~21 ms)
# No impact on audio quality - only changes buffer size / latency.
context.properties = {
    default.clock.quantum = 512
}
PWCONF
ok "Wrote $PIPEWIRE_CONF"

# (rtkit package + rtkit-daemon service are installed and enabled by Install.sh)

# =====================================================================
section "VERIFICATION"

# exact value (sysctl numbers: "10" must not pass on "100")
v_check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    ok "$label = $actual"
  else
    fail "$label expected '$expected', got '$actual'"
  fi
}
# the selected value in a sysfs list such as "always [madvise] never"
v_selected() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"[$expected]"* ]]; then
    ok "$label = $expected"
  else
    fail "$label expected '[$expected]', got '$actual'"
  fi
}

# sysctl
v_check "vm.dirty_ratio"       "10"          "$(sysctl -n vm.dirty_ratio)"
v_check "vm.dirty_background_ratio" "5"      "$(sysctl -n vm.dirty_background_ratio)"
v_check "kernel.nmi_watchdog"  "0"           "$(sysctl -n kernel.nmi_watchdog)"
v_check "tcp_congestion_control" "bbr"       "$(sysctl -n net.ipv4.tcp_congestion_control)"
v_check "default_qdisc"        "fq"          "$(sysctl -n net.core.default_qdisc)"
v_check "rmem_max"             "16777216"    "$(sysctl -n net.core.rmem_max)"
v_check "wmem_max"             "16777216"    "$(sysctl -n net.core.wmem_max)"
v_check "netdev_max_backlog"   "16384"       "$(sysctl -n net.core.netdev_max_backlog)"
if [[ $ZRAM -eq 1 ]]; then
  v_check "vm.swappiness"           "180"     "$(sysctl -n vm.swappiness)"
  v_check "vm.page-cluster"         "0"       "$(sysctl -n vm.page-cluster)"
  v_check "vm.watermark_boost_factor" "0"     "$(sysctl -n vm.watermark_boost_factor)"
  v_check "vm.watermark_scale_factor" "125"   "$(sysctl -n vm.watermark_scale_factor)"
fi

# THP
v_selected "THP enabled"       "madvise"     "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
v_selected "THP defrag"        "${THP_DEFRAG_TARGET:-madvise}" "$(cat /sys/kernel/mm/transparent_hugepage/defrag)"

# Packages
PKG_CHECK=(gamemode proton-cachyos-slr)
[[ "$PROFILE_NAME" == "desktop" ]] && PKG_CHECK+=(irqbalance)
if [[ "$(uname -m)" == "x86_64" ]]; then
  PKG_CHECK+=(lib32-gamemode lib32-mangohud)
fi
for p in "${PKG_CHECK[@]}"; do
  if pacman -Q "$p" >/dev/null 2>&1; then
    ok "package: $p $(pacman -Q "$p" | awk '{print $2}')"
  else
    fail "package missing: $p"
  fi
done
# gamemoderun binary present?
if command -v gamemoderun >/dev/null; then
  ok "binary: gamemoderun at $(command -v gamemoderun)"
else
  fail "binary: gamemoderun not on PATH"
fi

# System services
if [[ "$PROFILE_NAME" == "desktop" ]]; then
  state=$(systemctl is-active irqbalance 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then
    ok "service (system): irqbalance active"
  else
    fail "service (system): irqbalance $state"
  fi
fi
# fstab
noatime_count=$(awk -v fs="${FS_REGEX:-}" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,noatime/' "$FSTAB" | wc -l)
if [[ "$noatime_count" -ge 1 ]]; then
  ok "fstab: $noatime_count mount(s) [${FILESYSTEM// /, }] with noatime"
else
  fail "fstab: no mounts have noatime"
fi

# Kernel cmdline (systemd-boot)
gline=""
[[ -f "$KCMDLINE" ]] && gline=$(cat "$KCMDLINE")
for p in "${NEW_PARAMS[@]}"; do
  if has_param "$p" "$gline"; then
    ok "kernel cmdline: $p present"
  else
    fail "kernel cmdline: $p missing"
  fi
done

# UKI: verify the default entry's image (the one that boots) carries the new
# params; fall back to the newest image if it isn't there
UKI="$UKI_DIR/$DEFAULT_ENTRY"
[[ -f "$UKI" ]] || UKI="$(newest_uki "$UKI_DIR")"
if [[ -n "$UKI" && -f "$UKI" ]] && command -v objcopy >/dev/null; then
  uki_cmd="$(uki_cmdline "$UKI")"
  for p in "${NEW_PARAMS[@]}"; do
    if has_param "$p" "$uki_cmd"; then
      ok "UKI: $p present"
    else
      fail "UKI: $p missing (rebuild UKI or will be inert until then)"
    fi
  done
elif [[ -z "$UKI" ]]; then
  warn "no UKI found in $UKI_DIR - skipping UKI verification"
fi

# Persistence files
[[ -f "$SYSCTL_FILE" ]] && ok "persist: $SYSCTL_FILE" || fail "persist: $SYSCTL_FILE missing"
[[ -f "$UDEV_FILE" ]] && ok "persist: $UDEV_FILE"     || fail "persist: $UDEV_FILE missing"
[[ -f "$MODPROBE_DIR/bbr.conf" ]] && ok "persist: $MODPROBE_DIR/bbr.conf" || fail "persist: bbr.conf missing"
[[ -f "$THP_TMPFILES" ]] && ok "persist: $THP_TMPFILES" || fail "persist: $THP_TMPFILES missing"
[[ -f "$NTSYNC_CONF" ]] && ok "persist: $NTSYNC_CONF" || fail "persist: $NTSYNC_CONF missing"

# Section H - audio
if [[ "$PROFILE_NAME" == "desktop" ]]; then
  if [[ -f "$HDA_CONF" ]] && grep -q "power_save=0" "$HDA_CONF"; then
    ok "audio: HDA power-save config present"
  else
    fail "audio: HDA power-save config missing"
  fi
fi
if command -v rtkitctl >/dev/null 2>&1; then
  ok "audio: rtkit installed"
else
  fail "audio: rtkit not installed"
fi
if systemctl is-active --quiet rtkit-daemon 2>/dev/null; then
  ok "audio: rtkit-daemon active"
else
  fail "audio: rtkit-daemon not active"
fi

# =====================================================================
info 5 5 "CachyOS Compatibility Check"

# Stage 4 already writes everything the CachyOS kernels need (bfq-free udev
# rules, fq + bbr, transparent_hugepage=madvise in the cmdline/UKI). This stage
# used to write all of it a second time; now it only confirms it.

check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else fail "$1"; fi; }

section "1. I/O scheduler rules (no bfq)"
if [[ -f "$UDEV_FILE" ]] && ! grep -v '^#' "$UDEV_FILE" | grep -q bfq; then
  ok "$UDEV_FILE present and bfq-free"
else
  fail "$UDEV_FILE missing or still references bfq"
fi

section "2. fq qdisc + bbr congestion control"
if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  QDISC="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
  CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
  check "qdisc = fq (got '$QDISC')" "$([[ "$QDISC" == "fq" ]]; echo $?)"
  check "tcp_congestion_control = bbr (got '$CC')" "$([[ "$CC" == "bbr" ]]; echo $?)"
else
  warn "bbr not available on the running kernel yet - $CONF_DIR/99-perf-tune.conf applies it on CachyOS"
fi

section "3. transparent_hugepage=madvise in cmdline and UKI"
if [[ -f "$KCMDLINE" ]] && has_param "transparent_hugepage=madvise" "$(cat "$KCMDLINE")"; then
  check "cmdline has transparent_hugepage=madvise" 0
else
  check "cmdline has transparent_hugepage=madvise" 1
fi
UKI="$UKI_DIR/$DEFAULT_ENTRY"
[[ -f "$UKI" ]] || UKI="$(newest_uki "$UKI_DIR")"
if [[ -n "$UKI" ]] && command -v objcopy >/dev/null; then
  if has_param "transparent_hugepage=madvise" "$(uki_cmdline "$UKI")"; then
    check "UKI $(basename "$UKI") carries transparent_hugepage=madvise" 0
  else
    check "UKI $(basename "$UKI") carries transparent_hugepage=madvise" 1
  fi
elif [[ -z "$UKI" ]]; then
  warn "no UKIs found - the CachyOS kernel stage should have created one; check stage 2 output"
fi

# =====================================================================
echo
section "SUMMARY"
printf '%s passed: %d%s\n' "$C_OK" "$PASS" "$C_0"
if [[ $FAIL -gt 0 ]]; then
  printf '%s failed: %d%s\n' "$C_E" "$FAIL" "$C_0"
  echo "Failed items:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi

cat <<EOF

Persistence files:
  $SYSCTL_FILE
  $UDEV_FILE
  $MODPROBE_DIR/bbr.conf
  $THP_TMPFILES
  $NTSYNC_CONF
  $PIPEWIRE_CONF
  $KCMDLINE   (modified, systemd-boot)
  $FSTAB      (modified)
EOF
[[ "$PROFILE_NAME" == "desktop" ]] && echo "  $HDA_CONF"
cat <<EOF

ACTION REQUIRED (won't take effect until you do):
  REBOOT - fstab noatime, the kernel cmdline (THP, Plymouth), the new
           modules-load and udev rules, and on the desktop the HDA power-save
EOF

if [[ $FAIL -gt 0 ]]; then
  printf '\n%sSome checks failed - review the summary above.%s\n' "$C_E" "$C_0"
  exit 1
fi
printf '\n%sAll post-install steps completed successfully.%s\n' "$C_OK" "$C_0"
echo "Reboot required for all changes to take effect."
exit 0
