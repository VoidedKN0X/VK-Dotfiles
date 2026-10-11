#!/usr/bin/env bash
# full-tune-desktop.sh
# DESKTOP performance tune. Run this directly:  sudo ./full-tune-desktop.sh
#
# All shared logic lives in full-tune-common.sh; this file only holds the
# desktop-specific values so the two profiles stay clearly separated.

PROFILE_NAME="desktop"
LAPTOP_MODE=0
CPUFREQ_GOVERNOR=""
TUNE_NAME="full-tune-desktop.sh"

# shellcheck source=full-tune-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/full-tune-common.sh" "$@"
