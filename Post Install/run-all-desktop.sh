#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# run-all-desktop.sh
# DESKTOP post-install. Runs the full combined script in order:
#   CachyOS repo -> CachyOS kernel -> UKI + Secure Boot -> performance tune
#
# Run it directly:  sudo ./run-all-desktop.sh
# The other profiles use run-all-laptop.sh and run-all-steamdeck.sh.
# All shared logic lives in run-all-common.sh; this file only selects the
# desktop values.

PROFILE_NAME="desktop"
CPUFREQ_GOVERNOR=""
TUNE_NAME="run-all-desktop.sh"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
