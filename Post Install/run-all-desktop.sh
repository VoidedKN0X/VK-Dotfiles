#!/usr/bin/env bash
# run-all-desktop.sh
# DESKTOP post-install. Runs the full combined script in order:
#   repo -> CachyOS kernel -> fix UKI -> performance tune -> CachyOS compat
#
# Run it directly:  sudo ./run-all-desktop.sh
# The laptop variant is run-all-laptop.sh. All shared logic lives in
# run-all-common.sh; this file only selects the desktop values.

PROFILE_NAME="desktop"
CPUFREQ_GOVERNOR=""
TUNE_NAME="run-all-desktop.sh"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
