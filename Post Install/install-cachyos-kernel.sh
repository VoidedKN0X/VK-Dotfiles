#!/usr/bin/env bash
# install-cachyos-kernel.sh
# Installs the CachyOS kernel (linux-cachyos or a flavor), configures
# systemd-boot + UKI to boot it by default, and can optionally remove the
# old kernel(s).
#
# Requirements:
#   - Arch Linux x86_64
#   - systemd-boot installed with UKIs (EFI/Linux dir present, e.g. /boot/EFI/Linux)
#   - CPU supporting x86-64-v3 or newer (minimum for CachyOS kernels)
#   - CachyOS repositories configured in /etc/pacman.conf
#     If missing, this script aborts. Set them up first with the official installer:
#       curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
#       tar xvf cachyos-repo.tar.xz && cd cachyos-repo
#       sudo ./cachyos-repo.sh
#     (see https://wiki.cachyos.org/features/optimized_repos/)
#
# Usage:
#   sudo ./install-cachyos-kernel.sh [options]
#
# Options:
#   --flavor NAME   kernel variant: bore|bmq|deckify|eevdf|lts|hardened|rc|server|rt-bore
#                   (default: the main linux-cachyos kernel)
#   --no-headers    skip installing the matching -headers package
#   --remove-old    remove old kernels without prompting (running + new kernel always kept)
#   --keep-old      never remove old kernels
#   --yes, -y       non-interactive: --noconfirm pacman, no prompts
#                   (old-kernel removal then only happens with --remove-old)
#   --help, -h      show this help

set -uo pipefail

# ---------- defaults & args ----------
FLAVOR=""
INSTALL_HEADERS=1
REMOVE_MODE=0        # 0 = prompt, 1 = remove, -1 = keep
YES=0
TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  sed -n '2,30p' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)
      if [[ $# -lt 2 ]]; then
        printf 'Error: --flavor requires a value\n' >&2
        exit 1
      fi
      FLAVOR="$2"; shift 2 ;;
    --no-headers) INSTALL_HEADERS=0; shift ;;
    --remove-old) REMOVE_MODE=1; shift ;;
    --keep-old) REMOVE_MODE=-1; shift ;;
    --yes|-y) YES=1; shift ;;
    --help|-h) usage ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage ;;
  esac
done

PKG_BASE="linux-cachyos"
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  PKG_BASE="linux-cachyos-${FLAVOR}"
fi
# loader.conf default glob - matches any version of this kernel's UKI
DEFAULT_MATCH="linux-cachyos${FLAVOR:+-$FLAVOR}"

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

KNOWN_FLAVORS=(bore bmq deckify eevdf lts hardened rc server rt-bore)
if [[ -n "$FLAVOR" && "$FLAVOR" != "default" ]]; then
  if ! printf '%s\n' "${KNOWN_FLAVORS[@]}" | grep -qx "$FLAVOR"; then
    warn "unknown flavor '$FLAVOR' - only proceed if the package linux-cachyos-$FLAVOR exists"
  fi
fi

# ---------- root ----------
if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo --preserve-env=HOME "$0" "$@"
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
  cp -a "$LOADER_CONF" "$LOADER_CONF.bak-$TS"
  warn "backed up existing loader.conf -> loader.conf.bak-$TS"
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

head "Old kernel removal"
if [[ $REMOVE_MODE -eq 0 && $YES -eq 1 ]]; then
  REMOVE_MODE=-1
  warn "non-interactive mode: keeping old kernels (use --remove-old to remove)"
fi

RUN_BASE="$(running_base)"
CANDIDATES=()
while IFS=$'\t' read -r base kver; do
  [[ -z "$base" ]] && continue
  [[ "$base" == "$RUN_BASE" ]] && continue
  [[ "$base" == "$PKG_BASE" ]] && continue
  CANDIDATES+=("$base" "$kver")
done < <(kernels_list)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  ok "No old kernels to remove (keeping running '$RUN_BASE' and new '$PKG_BASE')"
else
  echo "Installed kernels other than running '$RUN_BASE' and new '$PKG_BASE':"
  for ((i=0; i<${#CANDIDATES[@]}; i+=2)); do
    printf '  - %-22s (kernel %s)\n' "${CANDIDATES[$i]}" "${CANDIDATES[$((i+1))]}"
  done
  for ((i=0; i<${#CANDIDATES[@]}; i+=2)); do
    base="${CANDIDATES[$i]}"
    kver="${CANDIDATES[$((i+1))]}"
    if [[ $REMOVE_MODE -eq 1 ]]; then
      remove_one "$base"
    elif [[ $REMOVE_MODE -eq -1 ]]; then
      warn "keeping $base (--keep-old)"
    else
      printf 'Remove %s (%s)? [y/N] ' "$base" "$kver"
      read -r ans
      if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
        remove_one "$base"
      else
        warn "keeping $base"
      fi
    fi
  done
fi

# ---------- summary ----------
head "DONE"
cat <<EOF
  Installed kernel : $PKG_BASE ${NEW_VER:-?}
  Boot default     : systemd-boot -> ${DEFAULT_MATCH}*  ($LOADER_CONF)
  loader.conf backup: ${LOADER_CONF}.bak-${TS}

REBOOT REQUIRED - the CachyOS kernel will load on next boot.
If you removed the old kernel(s), $PKG_BASE is now your only fallback
besides the currently running one. Confirm it boots before removing more.
EOF

exit 0
