#!/usr/bin/env bash
# run-all-desktop.sh
# DESKTOP post-install runner. Run this directly:  sudo ./run-all-desktop.sh
#
# Runs every Post Install script in order using the desktop profile. All shared
# logic lives in run-all-common.sh; this file only selects the desktop values.

PROFILE_NAME="desktop"
TUNE_SCRIPT="full-tune-desktop.sh"
TUNE_LABEL="Desktop Performance Tuning"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
