#!/bin/bash
# eid-mw.sh - the Belgian eID middleware and eID Viewer (AUR: eid-mw), built
# with a temporary fix. Run as your normal user (it asks for sudo to install).
# Install.sh runs it after the other AUR apps; it can also run on its own:
#   "Post Install/eid-mw.sh"
#
# Why: the AUR package (5.1.31) doesn't build against OpenSSL 4.0: the eID
# Viewer's verify.c reads ASN1 strings directly, which OpenSSL 4.0 no longer
# allows ("invalid use of incomplete typedef 'ASN1_IA5STRING'"). The eID team
# fixed it upstream in commit 58875f5 (in 5.1.32 and 5.2.x), but the AUR
# package isn't updated yet. This script builds the AUR package and applies
# that upstream patch first, but only while the source still needs it: once
# the AUR package has a fixed version, it builds that one unchanged. Then this
# script (and its call in install-common.sh) can go, and eid-mw can move back
# into the profiles' AUR_PKGS.
#
# Already installed: nothing to do (updates come with yay as usual).

set -uo pipefail

# the upstream fix, kept next to this script (from github.com/Fedict/eid-mw,
# commit 58875f5, LGPL-3.0 like eid-mw), so the build doesn't depend on
# downloading it
PATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/eid-mw-openssl4.patch"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not as root/sudo." >&2
    exit 1
fi
if pacman -Q eid-mw >/dev/null 2>&1; then
    echo "eid-mw is already installed"
    exit 0
fi

# Everything happens in one temporary folder, removed when the script ends
# (also after a failure), so nothing is left behind: makepkg's build, source,
# package and log folders all point into it, whatever makepkg.conf says. The
# build-only dependencies it installs are removed again at the end.
build="$(mktemp -d)"
export BUILDDIR="$build" PKGDEST="$build" SRCDEST="$build" SRCPKGDEST="$build" LOGDEST="$build"
# the packages installed before, to find the build dependencies afterwards
before="$build/installed-before"
pacman -Qq >"$before"
cleanup() {
    # build-only dependencies this script installed (new, installed as a
    # dependency, needed by nothing): removed
    local deps
    mapfile -t deps < <(comm -13 "$before" <(pacman -Qq) | grep -vx eid-mw | grep -Fxf - <(pacman -Qdtq))
    if [[ ${#deps[@]} -gt 0 ]]; then
        echo "eid-mw: removing the build dependencies: ${deps[*]}"
        sudo pacman -Rns --noconfirm "${deps[@]}" >/dev/null || echo "eid-mw: could not remove ${deps[*]}" >&2
    fi
    cd / && rm -rf "$build"
}
trap cleanup EXIT
cd "$build" || exit 1

# the AUR package's build files (PKGBUILD)
if ! yay -G eid-mw >/dev/null || [[ ! -f eid-mw/PKGBUILD ]]; then
    echo "eid-mw: could not download the AUR package" >&2
    exit 1
fi
cd eid-mw || exit 1

# download and unpack the source (and install its build dependencies). The
# source is checked against the AUR's sha256 sums; its PGP signature needs the
# eID signing key: imported from the PKGBUILD's validpgpkeys if it's missing,
# and if that fails (keyserver down) the signature check is skipped (the sha256
# check still applies).
if ! makepkg -so --noconfirm; then
    keys=$(bash -c 'source ./PKGBUILD >/dev/null 2>&1; echo "${validpgpkeys[*]:-}"')
    # shellcheck disable=SC2086  # one argument per key
    [[ -n "$keys" ]] && gpg --recv-keys $keys
    if ! makepkg -so --noconfirm; then
        echo "eid-mw: PGP check failed, building without it (sha256 still checked)" >&2
        makepkg -so --noconfirm --skippgpcheck || { echo "eid-mw: could not get the source" >&2; exit 1; }
    fi
fi

# the OpenSSL 4.0 fix, only if the unpacked source still needs it
verify=$(find src -path '*/plugins_tools/eid-viewer/verify.c' -print -quit)
if [[ -n "$verify" ]] && grep -q 'name->d\.ia5->data' "$verify"; then
    srcroot="${verify%/plugins_tools/eid-viewer/verify.c}"
    echo "eid-mw: applying the upstream OpenSSL 4.0 fix (58875f5)"
    if ! patch -d "$srcroot" -p1 <"$PATCH"; then
        echo "eid-mw: could not apply the OpenSSL 4.0 fix" >&2
        exit 1
    fi
else
    echo "eid-mw: the source doesn't need the OpenSSL 4.0 fix (any more)"
fi

# build from the (patched) source without unpacking it again (-e) and install
# it (the build-only dependencies go in cleanup, at the end)
if ! makepkg -sei --noconfirm; then
    echo "eid-mw: build or install failed" >&2
    exit 1
fi
echo "eid-mw installed"
