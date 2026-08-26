#!/usr/bin/env bash
# install-cachyos-repo.sh
# Installs the CachyOS repositories using the official installer
# (commands from Post-Install.txt / CachyOS wiki optimized_repos).
#
# Usage:
#   sudo ./install-cachyos-repo.sh
#   # re-running is safe (idempotent; official script skips existing setup)

set -uo pipefail

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()   { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; }
fail() { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
head() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

if ! grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
  head "Adding CachyOS repos (official installer)"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  cd "$TMP" || exit 1
  curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz \
    || { fail "download failed"; exit 1; }
  tar xvf cachyos-repo.tar.xz || { fail "extract failed"; exit 1; }
  cd cachyos-repo || exit 1
  ./cachyos-repo.sh || { fail "official installer failed"; exit 1; }
else
  ok "CachyOS repo already present in /etc/pacman.conf"
fi

# ---------- verification ----------
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

head "DONE"
cat <<EOF
  Next steps:
    sudo pacman -Syu
    # then install the kernel:
    sudo ./install-cachyos-kernel.sh
EOF
exit "$([[ $OK -eq 1 ]] && echo 0 || echo 1)"
