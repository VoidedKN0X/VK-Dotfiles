#!/usr/bin/env bash
# run-all-laptop.sh
# LAPTOP post-install. Runs the full combined script in order:
#   repo -> CachyOS kernel -> fix UKI -> performance tune -> CachyOS compat
#
# Run it directly:  sudo ./run-all-laptop.sh
# The desktop variant is run-all-desktop.sh. All shared logic lives in
# run-all-common.sh; this file only selects the laptop values.

PROFILE_NAME="laptop"
CPUFREQ_GOVERNOR=""
TUNE_NAME="run-all-laptop.sh"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
