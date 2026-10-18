#!/usr/bin/env bash
# cachyos-repo.sh
# Adds the CachyOS repositories with the official CachyOS installer
# (https://github.com/CachyOS/cachyos-repo-add-script), then checks them.
#
# Install.sh runs this BEFORE it installs your apps, so pacman installs the
# CachyOS builds straight away. The installer ends with `pacman -Syu`, which
# switches the packages that are already installed to the CachyOS builds; run
# first, that's only the base system from archinstall, not all your apps.
# run-all-common.sh (stage 1) runs it again: then the repos are already there
# and it only checks them.
#
#     sudo "Post Install/cachyos-repo.sh"
#
# Exits non-zero if the repos or the CachyOS keyring are missing afterwards.

set -uo pipefail

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_E=''; C_B=''; C_0=''
fi
ok()      { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; }
fail()    { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; }
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo." >&2
  exit 1
fi

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
  ) || { fail "CachyOS repo installer failed"; exit 1; }
else
  ok "CachyOS repo already present in /etc/pacman.conf"
fi

if ! grep -qE '^\[cachyos' /etc/pacman.conf; then
  fail "cachyos repo NOT found in /etc/pacman.conf"
  exit 1
fi
if ! pacman -Q cachyos-keyring >/dev/null 2>&1; then
  fail "cachyos-keyring not installed - run: pacman -Sy cachyos-keyring"
  exit 1
fi
ok "CachyOS repos and keyring are set up"
