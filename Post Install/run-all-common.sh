#!/usr/bin/env bash
# run-all-common.sh
# Runs all Post Install scripts in the correct order from the local folder.
# ALL the shared logic lives here; it is sourced by the two clearly separated
# entry points:
#
#   run-all-desktop.sh   -> sudo ./run-all-desktop.sh
#   run-all-laptop.sh    -> sudo ./run-all-laptop.sh
#
# Do not run this file directly. The entry points set PROFILE_NAME, TUNE_SCRIPT
# and TUNE_LABEL before sourcing it.

# === PROFILE (must be set by the sourcing entry point) ===
if [[ -z "${PROFILE_NAME:-}" ]]; then
  echo "Error: run run-all-desktop.sh or run-all-laptop.sh, not this file." >&2
  exit 2
fi

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

SCRIPTS=(
  "install-cachyos-repo.sh"
  "install-cachyos-kernel.sh"
  "fix-uki.sh"
  "$TUNE_SCRIPT"
  "cachyos-compat.sh"
)

LABELS=(
  "CachyOS Repository Setup"
  "CachyOS Kernel Install"
  "Fix UKI Setup"
  "$TUNE_LABEL"
  "CachyOS Compatibility Fixes"
)

if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi

fail() { printf '%s[ERROR]%s %s\n' "$C_E" "$C_0" "$*"; exit 1; }
info() { printf '\n%s=== [%d/%d] %s ===%s\n' "$C_B" "$1" "$2" "$3" "$C_0"; }

TOTAL=${#SCRIPTS[@]}

echo -e "${C_B}VK-Dotfiles Post Install Runner (${PROFILE_NAME})${C_0}"
echo "Running scripts from: $SCRIPT_DIR"

for i in "${!SCRIPTS[@]}"; do
  NAME="${SCRIPTS[$i]}"
  info "$((i+1))" "$TOTAL" "${LABELS[$i]}"
  [[ -f "$SCRIPT_DIR/$NAME" ]] || fail "Script not found: $SCRIPT_DIR/$NAME"
  chmod +x "$SCRIPT_DIR/$NAME"
  bash "$SCRIPT_DIR/$NAME" || fail "$NAME exited with code $?"
  echo -e "${C_OK}[DONE]${C_0} ${LABELS[$i]} completed"
done

echo -e "\n${C_OK}All scripts completed successfully.${C_0}"
echo "Reboot required for all changes to take effect."
