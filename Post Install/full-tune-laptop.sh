#!/usr/bin/env bash
# full-tune-laptop.sh
# LAPTOP performance tune. Run this directly:  sudo ./full-tune-laptop.sh
#
# All shared logic lives in full-tune-common.sh; this file only holds the
# laptop-specific values so the two profiles stay clearly separated.

PROFILE_NAME="laptop"
LAPTOP_MODE=5
CPUFREQ_GOVERNOR=""
TUNE_NAME="full-tune-laptop.sh"

# shellcheck source=full-tune-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/full-tune-common.sh" "$@"
