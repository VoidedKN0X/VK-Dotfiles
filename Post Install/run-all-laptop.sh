#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# run-all-laptop.sh
# LAPTOP post-install. Runs the full combined script in order:
#   CachyOS repo -> CachyOS kernel -> UKI + Secure Boot -> performance tune
#
# Run it directly:  sudo ./run-all-laptop.sh
# The other profiles use run-all-desktop.sh and run-all-steamdeck.sh.
# All shared logic lives in run-all-common.sh; this file only selects the
# laptop values.

PROFILE_NAME="laptop"
CPUFREQ_GOVERNOR=""
TUNE_NAME="run-all-laptop.sh"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
