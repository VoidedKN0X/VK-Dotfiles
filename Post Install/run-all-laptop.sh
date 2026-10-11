#!/usr/bin/env bash
# run-all-laptop.sh
# LAPTOP post-install runner. Run this directly:  sudo ./run-all-laptop.sh
#
# Runs every Post Install script in order using the laptop profile. All shared
# logic lives in run-all-common.sh; this file only selects the laptop values.

PROFILE_NAME="laptop"
TUNE_SCRIPT="full-tune-laptop.sh"
TUNE_LABEL="Laptop Performance Tuning"

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
