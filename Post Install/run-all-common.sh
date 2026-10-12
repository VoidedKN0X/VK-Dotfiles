#!/usr/bin/env bash
# run-all-common.sh
# SINGLE combined Post Install script. It replaces the individual scripts that
# used to be chained by the old run-all wrapper:
#     install-cachyos-repo.sh -> install-cachyos-kernel.sh -> fix-uki.sh
#     -> full-tune (this file) -> cachyos-compat.sh
# Those files no longer exist; everything lives here.
#
# It is sourced by the two clearly separated entry points:
#     run-all-desktop.sh   ->  sudo ./run-all-desktop.sh
#     run-all-laptop.sh    ->  sudo ./run-all-laptop.sh
# Do not run this file directly. The entry point sets PROFILE_NAME, LAPTOP_MODE,
# CPUFREQ_GOVERNOR and TUNE_NAME before sourcing it.
#
# Stages (in order):
#   1. CachyOS repository setup (official installer)
#   2. CachyOS kernel install + systemd-boot default entry
#   3. Fix/enable UKI + Secure Boot (sbctl keys, enroll -m, sign UKIs; sbctl is
#      installed by Install.sh)
#   4. Performance tune (profile-specific: desktop/laptop)
#   5. CachyOS-kernel compatibility overrides
#
# Tune groups (stage 4):
#   A. sysctl + I/O (NVMe scheduler, swappiness, BBR, readahead, dirty pages)
#   B. THP madvise + TCP buffers + netdev backlog
#   C. Install: lib32-gamemode, ananicy-cpp, irqbalance, lib32-mangohud
#   D. Enable: gamemoded, irqbalance, ananicy-cpp
#   E. fstab noatime (REBOOT required)
#   F. systemd-boot kernel cmdline: thp=madvise, split_lock_mitigate=0
#      (REBOOT required, UKI regenerated). A cpufreq governor is only added
#      when CPUFREQ_GOVERNOR is explicitly set.
#   G. /etc/environment: RADV_PERFTEST=gpl, MESA_NO_ERROR=1 (LOGOUT required)
#   H. Audio: HDA power-save off (REBOOT required for HDA)
#
# Persistence:
#   /etc/sysctl.d/99-perf-tune.conf, /etc/sysctl.d/zz-cachyos-compat.conf
#   /etc/udev/rules.d/60-ioschedulers.rules
#   /etc/modules-load.d/bbr.conf
#   /etc/kernel/cmdline (modified, systemd-boot)
#   /etc/fstab           (modified)
#   /etc/environment     (modified)
#
# No backups are made: this script is meant to run once on a clean install, so
# there is nothing worth preserving. It takes no command-line arguments.

# === PROFILE (must be set by the sourcing entry point) ===
if [[ -z "${PROFILE_NAME:-}" ]]; then
  echo "Error: run run-all-desktop.sh or run-all-laptop.sh, not this file." >&2
  exit 2
fi


set -uo pipefail

# === USER CONFIG (edit only if auto-detection misbehaves) ===
# Username to enable the gamemoded user service for.
# Auto-detected from SUDO_USER/logname/USER if left empty.
INSTALL_USER="${INSTALL_USER:-}"
# Filesystems to convert relatime->noatime in fstab (space-separated list).
# Auto-detected from fstab (local, non-pseudo fs) if left empty.
FILESYSTEM=""

# === PROFILE CONFIG (set by the sourcing entry point) ===
# LAPTOP_MODE      : vm.laptop_mode value (0 on desktop, 5 on laptop)
# CPUFREQ_GOVERNOR : optional kernel-cmdline default governor. Empty by default;
#                    auto-cpufreq manages the governor at runtime.
# TUNE_NAME        : name stamped into generated config files
LAPTOP_MODE="${LAPTOP_MODE:-0}"
CPUFREQ_GOVERNOR="${CPUFREQ_GOVERNOR:-}"
TUNE_NAME="${TUNE_NAME:-run-all-${PROFILE_NAME}.sh}"

CONF_DIR="/etc/sysctl.d"
UDEV_DIR="/etc/udev/rules.d"
MODPROBE_DIR="/etc/modules-load.d"
FSTAB="/etc/fstab"
ENV_FILE="/etc/environment"
KCMDLINE="/etc/kernel/cmdline"

# === UKI AUTO-DETECT ===
# Find UKI(s) in the standard systemd-boot location. If multiple, prefer
# the most recently modified (matches the last kernel build).
UKI=""
if [[ -d /boot/EFI/Linux ]]; then
  mapfile -t _UKI_CANDIDATES < <(find /boot/EFI/Linux -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
  if [[ ${#_UKI_CANDIDATES[@]} -eq 0 ]]; then
    echo "WARN: no UKI found in /boot/EFI/Linux/" >&2
  elif [[ ${#_UKI_CANDIDATES[@]} -eq 1 ]]; then
    UKI="${_UKI_CANDIDATES[0]}"
  else
    UKI=$(ls -1t "${_UKI_CANDIDATES[@]}" | head -1)
    echo "WARN: multiple UKIs found; using most recent: $UKI" >&2
  fi
fi
unset _UKI_CANDIDATES

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
head() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
die()  { fail "$@"; exit 1; }
info() { printf '\n%s=== [%d/%d] %s ===%s\n' "$C_B" "$1" "$2" "$3" "$C_0"; }


# === AUTO-DETECT non-root user (for gamemoded user service) ===
# Priority: explicit INSTALL_USER override > SUDO_USER > logname > $USER
detect_user() {
  if [[ -n "$INSTALL_USER" ]]; then
    echo "$INSTALL_USER"
    return
  fi
  local u
  u="${SUDO_USER:-}"
  [[ -z "$u" ]] && u="$(logname 2>/dev/null || true)"
  [[ -z "$u" ]] && u="${USER:-}"
  # Fall back to the first human (UID >= 1000) account if we still have nothing
  if [[ -z "$u" || "$u" == "root" ]]; then
    u="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"
  fi
  echo "$u"
}

# --------------- root -----------------------------------------------------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo --preserve-env=HOME "$0" "$@"
  fi
}
require_root "$@"

# === ARG PARSING (none; the profile comes from the entry point) ===
if [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  exit 2
fi

# Auto-detect the tuning target user (override with INSTALL_USER=...)
INSTALL_USER="$(detect_user)"
[[ -n "$INSTALL_USER" ]] || warn "no non-root user detected for gamemoded (set INSTALL_USER)"

# =====================================================================
info 1 5 "CachyOS Repository Setup"

if ! grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
  head "Adding CachyOS repos (official installer)"
  (
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cd "$TMP" || exit 1
    curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz \
      || { fail "download failed"; exit 1; }
    tar xvf cachyos-repo.tar.xz || { fail "extract failed"; exit 1; }
    cd cachyos-repo || exit 1
    ./cachyos-repo.sh || { fail "official installer failed"; exit 1; }
  ) || die "CachyOS repo installer failed"
else
  ok "CachyOS repo already present in /etc/pacman.conf"
fi

head "Verification"
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

FLAVOR=""
INSTALL_HEADERS=1
YES=0
PKG_BASE="linux-cachyos"
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  PKG_BASE="linux-cachyos-${FLAVOR}"
fi
# loader.conf default glob - matches any version of this kernel's UKI
DEFAULT_MATCH="linux-cachyos${FLAVOR:+-$FLAVOR}"
KNOWN_FLAVORS=(bore bmq deckify eevdf lts hardened rc server rt-bore)
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  if ! printf '%s\n' "${KNOWN_FLAVORS[@]}" | grep -qx "$FLAVOR"; then
    warn "unknown flavor '$FLAVOR' - only proceed if the package linux-cachyos-$FLAVOR exists"
  fi
fi
# ---------- pre-flight checks ----------
head "Pre-flight checks"

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
head "Target"
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
head "Install $PKG_BASE"

# refresh the package DB if the target package isn't known yet
if ! pacman -Si "$PKG_BASE" >/dev/null 2>&1; then
  warn "package not found in sync database - refreshing (pacman -Sy)"
  pacman -Sy --noconfirm || { fail "pacman -Sy failed"; exit 1; }
fi

INSTALL=("$PKG_BASE")
[[ $INSTALL_HEADERS -eq 1 ]] && INSTALL+=("$PKG_BASE-headers")
INSTALL+=("${EXTRA_PKGS[@]}")

PACOPTS=(--needed)
[[ $YES -eq 1 ]] && PACOPTS+=(--noconfirm)
if pacman -S "${PACOPTS[@]}" "${INSTALL[@]}"; then
  ok "install transaction completed"
else
  fail "pacman -S failed (see above)"; exit 1
fi

# ---------- sync vmlinuz to /boot if missing ----------
head "Sync kernel images to /boot"
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
      [[ -z "$_kname" ]] && _kname=""
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
  _uki_dir="$ESP/EFI/Linux"
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

# ---------- regenerate initramfs / UKIs ----------
head "Regenerate initramfs / UKIs"
if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
  if mkinitcpio -P; then
    ok "mkinitcpio -P regenerated all images"
  else
    fail "mkinitcpio -P failed"; exit 1
  fi
elif command -v dracut >/dev/null; then
  if dracut --regenerate-all; then
    ok "dracut regenerated all images"
  else
    fail "dracut --regenerate-all failed"; exit 1
  fi
else
  fail "no initramfs tool (mkinitcpio/dracut) found"; exit 1
fi

# ---------- configure systemd-boot default entry ----------
head "Configure systemd-boot default entry"
LOADER_DIR="$ESP/loader"
LOADER_CONF="$LOADER_DIR/loader.conf"
mkdir -p "$LOADER_DIR"

if [[ -f "$LOADER_CONF" ]]; then
  TMP=$(mktemp)
  grep -vE '^default([[:space:]]|$)' "$LOADER_CONF" > "$TMP"
  printf 'default %s*\n' "$DEFAULT_MATCH" >> "$TMP"
  cat "$TMP" > "$LOADER_CONF"
  rm -f "$TMP"
else
  printf 'default %s*\ntimeout 5\n' "$DEFAULT_MATCH" > "$LOADER_CONF"
fi
chmod 644 "$LOADER_CONF"
ok "loader.conf default entry set to '$DEFAULT_MATCH*'"

# ---------- verification ----------
head "Verification"
NEW_VER="$(pacman -Q "$PKG_BASE" 2>/dev/null | awk '{print $2}')"
ok "installed: $PKG_BASE ${NEW_VER:-?}"

mapfile -t UKI_FILES < <(ls "$ESP"/EFI/Linux/${DEFAULT_MATCH}*.efi "$ESP"/EFI/Linux/arch-${DEFAULT_MATCH}*.efi 2>/dev/null)
if [[ ${#UKI_FILES[@]} -gt 0 ]]; then
  ok "UKI present: $(basename "${UKI_FILES[0]}")"
else
  warn "no UKI matching $DEFAULT_MATCH*.efi or arch-$DEFAULT_MATCH*.efi in $ESP/EFI/Linux"
  warn "check mkinitcpio preset for correct default_uki path"
fi

if command -v bootctl >/dev/null; then
  if bootctl --no-pager list 2>/dev/null | grep -q "$DEFAULT_MATCH"; then
    ok "bootctl lists the $DEFAULT_MATCH entry"
  else
    warn "bootctl list did not show a $DEFAULT_MATCH entry - check manually"
  fi
fi

grep -q "^default $DEFAULT_MATCH" "$LOADER_CONF" \
  && ok "loader.conf default = $DEFAULT_MATCH*" \
  || fail "loader.conf default was not set"

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

head "Old kernel removal"

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
head "DONE"
cat <<EOF
  Installed kernel : $PKG_BASE ${NEW_VER:-?}
  Boot default     : systemd-boot -> ${DEFAULT_MATCH}*  ($LOADER_CONF)

REBOOT REQUIRED - the CachyOS kernel will load on next boot.
If old kernel removal was deferred, it runs automatically on that boot and
the cleanup script then deletes itself. This boot is your last known-good one,
so confirm CachyOS boots before relying on fallback removal only.
EOF

# =====================================================================
info 3 5 "Fix UKI Setup"

# ---------- find ESP ----------
head "Pre-flight checks"
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
head "Enabling UKI for presets using traditional initramfs"
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

  head "Updating $NAME"

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
      NEED_REGEN=1
    else
      warn "could not find vmlinuz for $_name in /usr/lib/modules/"
    fi
  else
    ok "$_kver already present"
  fi

  # fix UKI paths that point to a non-existent directory (e.g. /efi/ instead of /boot/)
  _uki_dir="$UKI_DIR"
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
        NEED_REGEN=1
      fi
    done
  fi
done

# ---------- regenerate (only if a preset was actually changed) ----------
if [[ $NEED_REGEN -eq 1 ]]; then
  head "Regenerating all UKIs with mkinitcpio -P"
  if mkinitcpio -P; then
    ok "mkinitcpio -P completed"
  else
    die "mkinitcpio -P failed"
  fi
else
  ok "No preset changes; skipping UKI regeneration (images already built in stage 2)"
fi

# ---------- secure boot: create keys, enroll (-m), sign (sbctl installed by Install.sh) ----------
head "Secure Boot setup (sbctl)"
if ! command -v sbctl >/dev/null; then
  warn "sbctl not installed (Install.sh installs it) - skipping Secure Boot setup"
else
  if [[ ! -d /var/lib/sbctl/keys ]]; then
    head "Creating Secure Boot keys"
    if sbctl create-keys; then
      ok "created Secure Boot keys in /var/lib/sbctl/keys"
    else
      die "failed to create Secure Boot keys"
    fi
  else
    ok "Secure Boot keys already exist in /var/lib/sbctl/keys"
  fi

  SB_STATUS="$(sbctl status 2>/dev/null || true)"
  if grep -qi 'secure boot:.*enabled' <<< "$SB_STATUS" \
     && grep -qi 'setup mode:.*disabled' <<< "$SB_STATUS"; then
    ok "Secure Boot already active with enrolled keys - skipping enrollment"
  else
    head "Enrolling Secure Boot keys (Microsoft keys included via -m)"
    if sbctl enroll-keys -m; then
      ok "enrolled keys with Microsoft keys (-m)"
      warn "a reboot may be required for the firmware to activate the keys"
    else
      die "failed to enroll Secure Boot keys (-m)"
    fi
  fi

  head "Signing UKIs with sbctl"
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
  UKI enabled; Secure Boot keys ensured and enrolled with -m (when sbctl is present).
  REBOOT REQUIRED to boot from the new UKIs and to finalize key enrollment.
EOF
# =====================================================================
info 4 5 "Performance Tuning"

# =====================================================================
head "A. sysctl + I/O"

# A.1 sysctl config
SYSCTL_FILE="$CONF_DIR/99-perf-tune.conf"
cat > "$SYSCTL_FILE" <<EOF
# Generated by ${TUNE_NAME}
# VM
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# I/O
vm.laptop_mode = ${LAPTOP_MODE}
# Network
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

# A.2 THP and TCP buffers (Group B)
cat >> "$SYSCTL_FILE" <<'EOF'
# THP - keep madvise so defrag stays sane
# (runtime set via /sys in B; this is a no-op for kernel cmdline users)
# Extra network
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

# A.3 I/O scheduler + readahead (runtime + udev persistence)
# Detect which schedulers this kernel provides, then only emit rules that
# reference available schedulers. bfq is intentionally excluded: the CachyOS
# kernels do not ship it, so mq-deadline is the preferred rotational scheduler.
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
  printf '# NVMe (multi-queue) -> none scheduler, 256 KiB readahead\n'
  printf 'ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="256"\n'
  if [[ -n "$HDD_SCHED" ]]; then
    printf '# Rotational disks -> %s scheduler, 8 MiB readahead\n' "$HDD_SCHED"
    printf 'ACTION=="add|change", KERNEL=="sd[a-z]*|vd[a-z]*|mmcblk*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="%s", ATTR{queue/read_ahead_kb}="8192"\n' "$HDD_SCHED"
  else
    printf '# No suitable HDD scheduler available on this kernel; rule omitted\n'
  fi
} > "$UDEV_FILE"

for d in /sys/block/nvme[0-9]*n[0-9]*; do
  [[ -d "$d" ]] || continue
  echo none > "$d/queue/scheduler" 2>/dev/null
  echo 256 > "$d/queue/read_ahead_kb" 2>/dev/null
done
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
head "B. THP + TCP buffers (runtime)"

# THP (defer+madvise exists only on newer kernels; fall back to madvise)
THP_DEFRAG_TARGET="defer+madvise"
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null \
  || { THP_DEFRAG_TARGET="madvise"; echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null; }

# Make THP survive reboot via sysctl too (no-op at runtime but documents intent)
cat >> "$SYSCTL_FILE" <<'EOF'
# Mark as user-tunable at runtime; no sysctl key exists, kept here for documentation
EOF

# =====================================================================
head "C. Install packages (official repos)"

PKGS=(ananicy-cpp irqbalance)
# lib32-* packages only exist on x86_64
if [[ "$(uname -m)" == "x86_64" ]]; then
  PKGS+=(lib32-gamemode lib32-mangohud)
fi
# gamemode and mangohud (native) are installed by Install.sh; only the lib32-*
# variants and ananicy-cpp rules are handled here.
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

# =====================================================================
head "D. Enable services"

enable_svc() {
  local svc="$1"
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    if systemctl enable --now "$svc.service" >/dev/null 2>&1; then
      ok "$svc.service enabled + started"
    else
      fail "$svc.service enable/start failed"
    fi
  else
    warn "$svc.service unit not found (package missing?)"
  fi
}
# gamemoded is a user-level service (located at /usr/lib/systemd/user/gamemoded.service).
# Enable lingering for the real user and start the user service.
REAL_USER="${INSTALL_USER}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  if loginctl enable-linger "$REAL_USER" 2>/dev/null; then
    ok "lingering enabled for $REAL_USER"
  else
    warn "could not enable lingering for $REAL_USER"
  fi
  if sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
       systemctl --user enable --now gamemoded.service 2>/dev/null; then
    ok "user service: gamemoded enabled + started (for $REAL_USER)"
  else
    fail "user service: gamemoded could not be enabled (user $REAL_USER)"
  fi
else
  fail "could not determine non-root user for gamemoded (SUDO_USER/USER empty)"
fi
enable_svc irqbalance
# ananicy-cpp ships unit as either ananicy-cpp or ananicy
if systemctl list-unit-files ananicy-cpp.service >/dev/null 2>&1; then
  enable_svc ananicy-cpp
elif systemctl list-unit-files ananicy.service >/dev/null 2>&1; then
  enable_svc ananicy
else
  fail "ananicy service unit not found"
fi

# =====================================================================
head "E. fstab noatime (REBOOT required)"

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
if [[ "$AFTER" -gt 0 ]]; then
  cat "$TMP" > "$FSTAB"
  chmod 644 "$FSTAB"
  ok "Added noatime to $AFTER mount(s) [${FILESYSTEM// /, }] in $FSTAB (was $BEFORE with relatime)"
else
  fail "Did not find any relatime entries to change (filesystems: ${FILESYSTEM:-none})"
fi
rm -f "$TMP"

# =====================================================================
head "F. Kernel cmdline (REBOOT required)"

NEW_PARAMS=(transparent_hugepage=madvise split_lock_mitigate=0)
# Only add cpufreq.default_governor= to the cmdline if a value is set.
# On laptops auto-cpufreq manages the governor at runtime, so the kernel-cmdline
# default is usually omitted.
[[ -n "$CPUFREQ_GOVERNOR" ]] && NEW_PARAMS+=(cpufreq.default_governor="$CPUFREQ_GOVERNOR")

# systemd-boot: the kernel cmdline lives in /etc/kernel/cmdline
if [[ ! -f "$KCMDLINE" ]]; then
  fail "systemd-boot kernel cmdline file not found: $KCMDLINE"
else
  warn "systemd-boot + UKI detected - updating $KCMDLINE and regenerating images"
  CURRENT=$(cat "$KCMDLINE")
  ADDED=""
  for p in "${NEW_PARAMS[@]}"; do
    if ! grep -qw -- "$p" <<<"$CURRENT"; then
      CURRENT="$CURRENT $p"
      ADDED="$ADDED $p"
    fi
  done
  CURRENT=$(echo "$CURRENT" | sed -E 's/^ +//; s/ +/ /g; s/ +$//')
  if [[ -n "$ADDED" ]]; then
    echo "$CURRENT" > "$KCMDLINE"
    ok "kernel cmdline updated. Added:$ADDED"

    # Regenerate images for ALL detected kernels, not a hardcoded one.
    if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
      if mkinitcpio -P >/dev/null 2>&1; then
        ok "mkinitcpio regenerated images for all presets"
      else
        fail "mkinitcpio -P failed - images not regenerated; reboot with current params"
      fi
    elif command -v dracut >/dev/null; then
      if dracut --regenerate-all >/dev/null 2>&1; then
        ok "dracut regenerated all initramfs images"
      else
        fail "dracut --regenerate-all failed"
      fi
    else
      fail "no initramfs tool (mkinitcpio/dracut) or presets found - cannot regenerate images"
    fi

    # Re-pick the most recently modified UKI for later verification
    mapfile -t _UKI_ALL < <(find /boot/EFI/Linux -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
    if [[ ${#_UKI_ALL[@]} -gt 0 ]]; then
      UKI=$(ls -1t "${_UKI_ALL[@]}" | head -1)
    fi
    unset _UKI_ALL
  else
    ok "All kernel cmdline params already present"
  fi
fi

# =====================================================================
head "G. /etc/environment (LOGOUT required)"

[[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"
chmod 644 "$ENV_FILE"
set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i -E "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}
set_env MESA_NO_ERROR 1
# RADV_PERFTEST=gpl is only meaningful on AMD GPUs (harmless elsewhere)
AMD_GPU=0
if command -v lspci >/dev/null && lspci 2>/dev/null | grep -qiE '1002.*VGA|1002.*Display|VGA.*1002|Display.*1002'; then
  AMD_GPU=1
fi
if [[ $AMD_GPU -eq 0 ]] && [[ -d /sys/class/drm ]]; then
  for v in /sys/class/drm/card*/device/vendor; do
    [[ -f "$v" ]] && grep -q '0x1002' "$v" 2>/dev/null && AMD_GPU=1 && break
  done
fi
if [[ $AMD_GPU -eq 1 ]]; then
  set_env RADV_PERFTEST gpl
  ok "AMD GPU detected; RADV_PERFTEST=gpl and MESA_NO_ERROR=1 set in $ENV_FILE"
else
  warn "No AMD GPU detected; only MESA_NO_ERROR=1 set in $ENV_FILE"
fi

# =====================================================================
head "H. Audio (HDA power-save) (REBOOT required for HDA)"

# H.1 HDA codec power-save disable - prevents HDMI audio crackle/pop on resume
# Kept for laptop use too: relevant when hooked up to an external HDMI/DP output.
HDA_CONF="/etc/modprobe.d/audio-disable-power-save.conf"
if [[ -f "$HDA_CONF" ]] && grep -q "power_save=0" "$HDA_CONF"; then
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

# H.2 PipeWire low-latency quantum
# Lower default quantum from 1024 to 512 (~21ms -> ~10ms latency).
# No impact on audio quality, only buffer size. Negligible CPU cost on modern hw.
PIPEWIRE_CONF="/etc/pipewire/pipewire.conf.d/99-low-latency.conf"
if [[ -f "$PIPEWIRE_CONF" ]] && grep -q "default.clock.quantum" "$PIPEWIRE_CONF"; then
  ok "PipeWire low-latency config already present"
else
  mkdir -p "$(dirname "$PIPEWIRE_CONF")"
  tee "$PIPEWIRE_CONF" > /dev/null <<'PWCONF'
# Lower default PipeWire quantum for reduced audio latency
# 512 samples @ 48 kHz = ~10.7 ms (was 1024 / ~21 ms)
# No impact on audio quality - only changes buffer size / latency.
context.properties = {
    default.clock.quantum       = 512
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 2048
}
PWCONF
  ok "Wrote $PIPEWIRE_CONF"
fi

# (rtkit package + rtkit-daemon service are installed and enabled by Install.sh)

# =====================================================================
head "VERIFICATION"

v_check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    ok "$label = $actual"
  else
    fail "$label expected '$expected', got '$actual'"
  fi
}

# sysctl
v_check "vm.swappiness"        "10"          "$(sysctl -n vm.swappiness)"
v_check "vm.dirty_ratio"       "10"          "$(sysctl -n vm.dirty_ratio)"
v_check "vm.dirty_background_ratio" "5"      "$(sysctl -n vm.dirty_background_ratio)"
v_check "vm.laptop_mode"       "$LAPTOP_MODE" "$(sysctl -n vm.laptop_mode)"
v_check "tcp_congestion_control" "bbr"       "$(sysctl -n net.ipv4.tcp_congestion_control)"
v_check "default_qdisc"        "fq"          "$(sysctl -n net.core.default_qdisc)"
v_check "tcp_fastopen"         "3"           "$(sysctl -n net.ipv4.tcp_fastopen)"
v_check "rmem_max"             "16777216"    "$(sysctl -n net.core.rmem_max)"
v_check "wmem_max"             "16777216"    "$(sysctl -n net.core.wmem_max)"
v_check "netdev_max_backlog"   "16384"       "$(sysctl -n net.core.netdev_max_backlog)"
v_check "tcp_max_syn_backlog"  "8192"        "$(sysctl -n net.ipv4.tcp_max_syn_backlog)"

# THP
v_check "THP enabled"          "[madvise]"   "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
v_check "THP defrag"           "[${THP_DEFRAG_TARGET:-madvise}]" "$(cat /sys/kernel/mm/transparent_hugepage/defrag)"

# NVMe scheduler
for d in /sys/block/nvme[0-9]*n[0-9]*; do
  [[ -d "$d" ]] || continue
  n=$(basename "$d")
  v_check "$n scheduler"        "none"        "$(cat "$d/queue/scheduler")"
  v_check "$n readahead"        "256"         "$(cat "$d/queue/read_ahead_kb")"
done

# Packages
PKG_CHECK=(gamemode ananicy-cpp irqbalance)
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
for s in irqbalance; do
  state=$(systemctl is-active "$s" 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then
    ok "service (system): $s active"
  else
    fail "service (system): $s $state"
  fi
done
SVC=""
if systemctl list-unit-files ananicy-cpp.service >/dev/null 2>&1; then SVC=ananicy-cpp
elif systemctl list-unit-files ananicy.service >/dev/null 2>&1; then SVC=ananicy
fi
if [[ -n "$SVC" ]]; then
  state=$(systemctl is-active "$SVC" 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then ok "service (system): $SVC active"; else fail "service (system): $SVC $state"; fi
else
  fail "service (system): ananicy unit not found"
fi

# User service (gamemoded) - check as the original user
REAL_USER="${INSTALL_USER}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  uid=$(id -u "$REAL_USER")
  state=$(sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active gamemoded 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then
    ok "service (user): gamemoded active for $REAL_USER"
  else
    fail "service (user): gamemoded $state for $REAL_USER"
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
VERIFY_PARAMS=(transparent_hugepage=madvise split_lock_mitigate=0)
[[ -n "$CPUFREQ_GOVERNOR" ]] && VERIFY_PARAMS+=(cpufreq.default_governor="$CPUFREQ_GOVERNOR")
for p in "${VERIFY_PARAMS[@]}"; do
  if grep -qw -- "$p" <<<"$gline"; then
    ok "kernel cmdline: $p present"
  else
    fail "kernel cmdline: $p missing"
  fi
done

# UKI: verify cmdline section contains the new params
if [[ -n "$UKI" && -f "$UKI" ]] && command -v objcopy >/dev/null; then
  uki_cmd=$(objcopy -O binary --only-section=.cmdline "$UKI" /tmp/uki-cmdline-$$ 2>/dev/null && tr -d '\0' < /tmp/uki-cmdline-$$; rm -f /tmp/uki-cmdline-$$)
  for p in "${VERIFY_PARAMS[@]}"; do
    if grep -qw -- "$p" <<<"$uki_cmd"; then
      ok "UKI: $p present"
    else
      fail "UKI: $p missing (rebuild UKI or will be inert until then)"
    fi
  done
elif [[ -z "$UKI" ]]; then
  warn "UKI auto-detect found nothing in /boot/EFI/Linux/ - skipping UKI verification"
fi

# environment (only check if file exists and was modified)
ENV_CHECKS="MESA_NO_ERROR=1"
if command -v lspci >/dev/null && lspci -nn 2>/dev/null | grep -qi '1002:'; then
  ENV_CHECKS="$ENV_CHECKS RADV_PERFTEST=gpl"
fi
for kv in $ENV_CHECKS; do
  k=${kv%=*}; v=${kv#*=}
  if [[ -f "$ENV_FILE" ]] && grep -qE "^${k}=" "$ENV_FILE" && grep -E "^${k}=" "$ENV_FILE" | grep -q "$v"; then
    ok "env: $k=$v"
  else
    fail "env: $k not set to $v"
  fi
done

# Persistence files
[[ -f "$SYSCTL_FILE" ]] && ok "persist: $SYSCTL_FILE" || fail "persist: $SYSCTL_FILE missing"
[[ -f "$UDEV_FILE" ]] && ok "persist: $UDEV_FILE"     || fail "persist: $UDEV_FILE missing"
[[ -f "$MODPROBE_DIR/bbr.conf" ]] && ok "persist: $MODPROBE_DIR/bbr.conf" || fail "persist: bbr.conf missing"

# Section H - audio
if [[ -f /etc/modprobe.d/audio-disable-power-save.conf ]] && grep -q "power_save=0" /etc/modprobe.d/audio-disable-power-save.conf; then
  ok "audio: HDA power-save config present"
else
  fail "audio: HDA power-save config missing"
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
info 5 5 "CachyOS Compatibility Fixes"

UDEV_FILE="/etc/udev/rules.d/60-ioschedulers.rules"
SYSCTL_FILE="/etc/sysctl.d/zz-cachyos-compat.conf"
KCMDLINE="/etc/kernel/cmdline"

# =====================================================================
head "1. I/O scheduler rules (no bfq - CachyOS kernels don't ship it)"

# The tune stage (A.3) already writes these bfq-free rules; just confirm it.
if [[ -f "$UDEV_FILE" ]] && ! grep -v '^#' "$UDEV_FILE" 2>/dev/null | grep -q bfq; then
  ok "$UDEV_FILE present and bfq-free"
else
  fail "$UDEV_FILE missing or still references bfq"
fi

# =====================================================================
head "2. sysctl: fq qdisc + bbr congestion control (CachyOS recommendation)"

# Applied last (zz- prefix) so these win over the tune scripts' defaults.
cat > "$SYSCTL_FILE" <<'EOF'
# Generated by run-all-common.sh (cachyos-compat stage)
# CachyOS networking recommendation: fq qdisc + BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
  if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
    ok "sysctl applied: fq + bbr"
  else
    fail "sysctl -p $SYSCTL_FILE failed (check /etc/sysctl.conf or .d ordering)"
  fi
else
  warn "bbr not available on the running kernel yet - config written, takes effect on CachyOS"
fi

# =====================================================================
head "3. Kernel cmdline: transparent_hugepage=madvise + UKI regeneration"

if [[ ! -f "$KCMDLINE" ]]; then
  warn "no $KCMDLINE (systemd-boot cmdline file) - nothing to align"
else
  CURRENT="$(cat "$KCMDLINE")"
  ADDED=""
  if ! grep -qw -- "transparent_hugepage=madvise" <<<"$CURRENT"; then
    CURRENT="$CURRENT transparent_hugepage=madvise"
    ADDED=" transparent_hugepage=madvise"
  fi
  CURRENT="$(echo "$CURRENT" | sed -E 's/^ +//; s/ +/ /g; s/ +$//')"
  if [[ -n "$ADDED" ]]; then
    echo "$CURRENT" > "$KCMDLINE"
    ok "cmdline updated, added:$ADDED"
  else
    ok "cmdline already contains transparent_hugepage=madvise"
  fi
fi

# Only regenerate if this stage actually changed the cmdline (the tune stage F
# already added transparent_hugepage=madvise, so normally this is a no-op).
if [[ -n "${ADDED:-}" ]]; then
  if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
    if mkinitcpio -P >/dev/null 2>&1; then
      ok "mkinitcpio regenerated all UKIs"
    else
      fail "mkinitcpio -P failed"
    fi
  elif command -v dracut >/dev/null; then
    if dracut --regenerate-all >/dev/null 2>&1; then
      ok "dracut regenerated all images"
    else
      fail "dracut --regenerate-all failed"
    fi
  else
    warn "no mkinitcpio/dracut found - UKIs not regenerated"
  fi
else
  ok "cmdline unchanged; skipping UKI regeneration"
fi

# =====================================================================
head "4. Verification"

check() { if [[ "$2" -eq 0 ]]; then ok "$1"; else fail "$1"; fi; }

QDISK="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
check "qdisc = fq (got '$QDISK')" "$([[ "$QDISK" == "fq" ]]; echo $?)"
check "tcp_congestion_control = bbr (got '$CC')" "$([[ "$CC" == "bbr" ]]; echo $?)"

if grep -v '^#' "$UDEV_FILE" | grep -q bfq; then
  check "udev rules contain no bfq" 1
else
  check "udev rules contain no bfq" 0
fi

if [[ -f "$KCMDLINE" ]] && grep -qw -- "transparent_hugepage=madvise" "$KCMDLINE"; then
  check "cmdline has transparent_hugepage=madvise" 0
else
  check "cmdline has transparent_hugepage=madvise" 1
fi

# UKI carries the param (if a UKI exists)
mapfile -t _UKIS < <(find /boot/EFI/Linux -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
if [[ ${#_UKIS[@]} -gt 0 ]] && command -v objcopy >/dev/null; then
  _UKI="$(ls -1t "${_UKIS[@]}" 2>/dev/null | head -1)"
  if [[ -n "$_UKI" && -f "$_UKI" ]]; then
    _cmd="$(objcopy -O binary --only-section=.cmdline "$_UKI" /tmp/cachyos-uki-cmd-$$ 2>/dev/null && tr -d '\0' < /tmp/cachyos-uki-cmd-$$; rm -f /tmp/cachyos-uki-cmd-$$)"
    if grep -qw -- "transparent_hugepage=madvise" <<<"$_cmd"; then
      check "UKI $(basename "$_UKI") carries transparent_hugepage=madvise" 0
    else
      check "UKI $(basename "$_UKI") carries transparent_hugepage=madvise" 1
    fi
  else
    warn "could not locate a valid UKI file"
  fi
elif [[ ${#_UKIS[@]} -eq 0 ]]; then
  warn "no UKIs found yet - the CachyOS kernel stage should have created one; check stage 2 output"
fi
unset _UKIS

head "DONE"
cat <<EOF
  Applied CachyOS-kernel-safe overrides:
    - $UDEV_FILE (no bfq)
    - $SYSCTL_FILE (fq + bbr, applied last)
    - $KCMDLINE (transparent_hugepage=madvise)

  REBOOT required for the cmdline/udev changes to fully apply.
EOF

# =====================================================================
echo
head "SUMMARY"
printf '%s passed: %d%s\n' "$C_OK" "$PASS" "$C_0"
if [[ $FAIL -gt 0 ]]; then
  printf '%s failed: %d%s\n' "$C_E" "$FAIL" "$C_0"
  echo "Failed items:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi

cat <<EOF

Persistence files:
  /etc/sysctl.d/99-perf-tune.conf
  $SYSCTL_FILE
  $UDEV_FILE
  $MODPROBE_DIR/bbr.conf
  $KCMDLINE   (modified, systemd-boot)
  $FSTAB      (modified)
  $ENV_FILE   (modified)

ACTION REQUIRED (won't take effect until you do):
  1. REBOOT     - fstab noatime + kernel cmdline (thp, split_lock, cpufreq)
                   + HDA power-save (snd_hda_intel module reload)
  2. REBOOT     - same reboot picks up new modules-load and udev rules
  3. LOGOUT     - for RADV_PERFTEST and MESA_NO_ERROR to load
EOF

if [[ $FAIL -gt 0 ]]; then
  printf '\n%sSome checks failed - review the summary above.%s\n' "$C_E" "$C_0"
  exit 1
fi
printf '\n%sAll post-install steps completed successfully.%s\n' "$C_OK" "$C_0"
echo "Reboot required for all changes to take effect."
exit 0
