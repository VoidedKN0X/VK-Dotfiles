#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# run-all-clean.sh
# CLEAN profile post-install (any desktop or laptop). Runs, in order:
#   CachyOS repo -> CachyOS kernel + boot splash -> unified kernel images ->
#   performance tune
#
#   sudo ./run-all-clean.sh               asks whether to install the gaming extras
#   sudo ./run-all-clean.sh --gaming      with the gaming extras, no question
#   sudo ./run-all-clean.sh --no-gaming   without them, no question
# (Clean/Install.sh asks at its start and passes the answer on.)
#
# All shared logic lives in run-all-common.sh; this file only selects the
# clean profile's values:
#   - no Secure Boot: enrolling keys needs the firmware in Setup Mode and is
#     hard to undo. To set it up anyway, change SECURE_BOOT to 1 (read the
#     README, step 2, first).
#   - gaming extras (32-bit gamemode and MangoHud, Proton-CachyOS, Heroic and
#     the ntsync module) only if you choose them
#   - HDA audio power-save stays on (that tweak is desktop profile only).

PROFILE_NAME="clean"
SECURE_BOOT=0

# root first, so the answer below isn't asked twice (run-all-common.sh would
# otherwise re-run this file with sudo, without its arguments)
if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

GAMING=""
case "${1:-}" in
  --gaming) GAMING=1 ;;
  --no-gaming) GAMING=0 ;;
  "") ;;
  *) echo "usage: run-all-clean.sh [--gaming | --no-gaming]" >&2; exit 2 ;;
esac
if [[ -z "$GAMING" ]]; then
  GAMING=0
  # only ask when someone can answer (not when run from a script without a terminal)
  if [[ -t 0 ]]; then
    read -r -p "Install the gaming extras (32-bit gamemode/MangoHud, Proton-CachyOS, Heroic, ntsync)? [y/N] " answer
    [[ "$answer" =~ ^[Yy] ]] && GAMING=1
  fi
fi

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh"
