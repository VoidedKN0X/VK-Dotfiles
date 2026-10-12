#!/usr/bin/env bash
# run-all-steamdeck.sh
# STEAM DECK (LCD) post-install. Runs the full combined script in order:
#   repo -> CachyOS kernel -> fix UKI -> performance tune -> CachyOS compat
#
# Run it directly:  sudo ./run-all-steamdeck.sh
# All shared logic lives in run-all-common.sh; this file only selects the Steam
# Deck values and adds the Deck's hardware support (device_setup below).
#
# Differences from the laptop:
#   - kernel linux-cachyos-deckify: the CachyOS handheld kernel, which has the
#     Steam Deck drivers (fan/sensors, embedded controller, USB-C dock, power LED)
#   - no Secure Boot: the Deck's firmware has no Secure Boot switch; enrolled keys
#     can only be removed with special tools or a BIOS reflash
#   - Valve's fan control and BIOS updater (from the CachyOS repos)

PROFILE_NAME="steamdeck"
LAPTOP_MODE=5
CPUFREQ_GOVERNOR=""
TUNE_NAME="run-all-steamdeck.sh"
KERNEL_FLAVOR="deckify"
SECURE_BOOT=0

STEAMDECK_FILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/steamdeck"

# Called by run-all-common.sh in stage 2, right after the kernel is installed.
device_setup() {
  local board
  board="$(cat /sys/class/dmi/id/board_vendor 2>/dev/null) $(cat /sys/class/dmi/id/board_name 2>/dev/null)"
  if [[ "$board" != "Valve Jupiter" ]]; then
    warn "this isn't an LCD Steam Deck (board: '$board') - skipping Steam Deck hardware support"
    return 0
  fi

  # jupiter-hw-support: Valve's BIOS updater + BIOS files (CachyOS build, patched
  #   for systemd-boot), SD card auto-mount
  # jupiter-fan-control: Valve's fan curve for the LCD Deck (needs the deckify kernel)
  if pacman -S --needed --noconfirm jupiter-hw-support jupiter-fan-control; then
    ok "installed jupiter-hw-support + jupiter-fan-control"
  else
    fail "could not install the Steam Deck packages"; return 0
  fi

  # Fan control. It needs the deckify kernel's driver, so it only works after the
  # reboot into that kernel: enable now, it starts on the next boot.
  if systemctl enable jupiter-fan-control.service >/dev/null 2>&1; then
    ok "jupiter-fan-control enabled (active after the reboot into the deckify kernel)"
  else
    fail "could not enable jupiter-fan-control.service"
  fi

  # Valve's own boot-time services, masked:
  #   jupiter-biosupdate         - flashes AND reboots; replaced by steamdeck-bios-update
  #   jupiter-controller-update  - updates the controller firmware; the controllers are removed
  for unit in jupiter-biosupdate.service jupiter-controller-update.service; do
    systemctl mask "$unit" >/dev/null 2>&1 && ok "masked $unit" || warn "could not mask $unit"
  done

  # BIOS updates: automatic, but never reboots (see steamdeck/steamdeck-bios-update)
  install -Dm755 "$STEAMDECK_FILES/steamdeck-bios-update" /usr/local/bin/steamdeck-bios-update
  install -Dm644 "$STEAMDECK_FILES/steamdeck-bios-update.service" /etc/systemd/system/steamdeck-bios-update.service
  install -Dm644 "$STEAMDECK_FILES/steamdeck-bios-update.timer" /etc/systemd/system/steamdeck-bios-update.timer
  systemctl daemon-reload
  if systemctl enable steamdeck-bios-update.timer >/dev/null 2>&1; then
    ok "steamdeck-bios-update.timer enabled (first check 2 min after the next boot, then hourly)"
  else
    fail "could not enable steamdeck-bios-update.timer"
  fi
}

# shellcheck source=run-all-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-all-common.sh" "$@"
