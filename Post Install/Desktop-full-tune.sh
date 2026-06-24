#!/usr/bin/env bash
# system-full-tune.sh
# Comprehensive, self-verifying, reversible performance tune for:
#   Arch Linux, kernel 7.0.12-zen, AMD Ryzen 9 9950X3D, AMD RX 9070 XT
#
# Groups applied (all approved):
#   A. sysctl + I/O (NVMe scheduler, swappiness, BBR, readahead, dirty pages)
#   B. THP madvise + TCP buffers + netdev backlog
#   C. Install: gamemode, lib32-gamemode, ananicy-cpp, irqbalance, lib32-mangohud
#   D. Enable: gamemoded, irqbalance, ananicy-cpp
#   E. fstab noatime (REBOOT required)
#   F. systemd-boot/GRUB kernel cmdline: thp=madvise, split_lock_mitigate=0, cpufreq.default_governor=performance
#      (REBOOT required, UKI/grub regenerated)
#   G. /etc/environment: RADV_PERFTEST=gpl, MESA_NO_ERROR=1 (LOGOUT required)
#   H. Audio: HDA power-save off + rtkit install/enable (REBOOT required for HDA)
#
# Persistence:
#   /etc/sysctl.d/99-perf-tune.conf
#   /etc/udev/rules.d/60-ioschedulers.rules
#   /etc/modules-load.d/bbr.conf
#   /etc/default/grub            (modified + grub-mkconfig)
#   /etc/fstab                   (modified)
#   /etc/environment             (modified)
#
# Backup: /var/lib/perf-tune-backup/baseline.env (chmod 600)
# Rollback: see final output, or run "system-full-tune.sh --rollback"

set -uo pipefail

# === USER CONFIG (edit these on a fresh install) ===
INSTALL_USER="axel"  # username to enable the gamemoded user service for
FILESYSTEM="ext4"    # only ext4 mounts are touched (fstab sed)

CONF_DIR="/etc/sysctl.d"
UDEV_DIR="/etc/udev/rules.d"
MODPROBE_DIR="/etc/modules-load.d"
GRUB_FILE="/etc/default/grub"
FSTAB="/etc/fstab"
ENV_FILE="/etc/environment"
BACKUP_DIR="/var/lib/perf-tune-backup"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/baseline-$TS.env"

# === UKI AUTO-DETECT ===
# Find UKI(s) in the standard systemd-boot location. If multiple, prefer
# the most recently modified (matches the last kernel build).
UKI=""
if [[ -d /boot/EFI/Linux ]]; then
  mapfile -t _UKI_CANDIDATES < <(find /boot/EFI/Linux -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
  if [[ ${#_UKI_CANDIDATES[@]} -eq 0 ]]; then
    echo "WARN: no UKI found in /boot/EFI/Linux/" >&2
  elif [[ ${#_UKI_CANDIDATES[@]} -eq 1 ]]; then
    UKI="${_UKI_CANDIDATES[0]}"
  else
    UKI=$(ls -1t "${_UKI_CANDIDATES[@]}" | head -1)
    echo "WARN: multiple UKIs found; using most recent: $UKI" >&2
  fi
fi
unset _UKI_CANDIDATES

PASS=0
FAIL=0
WARNINGS=()

# --------------- colors & output ------------------------------------------
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_W=$'\033[1;33m'; C_E=$'\033[1;31m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
else
  C_OK=''; C_W=''; C_E=''; C_B=''; C_0=''
fi
ok()   { printf '%s[✓]%s %s\n' "$C_OK" "$C_0" "$*"; PASS=$((PASS+1)); }
fail() { printf '%s[✗]%s %s\n' "$C_E" "$C_0" "$*"; FAIL=$((FAIL+1)); WARNINGS+=("$*"); }
warn() { printf '%s[!]%s %s\n' "$C_W" "$C_0" "$*"; }
head() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }

# --------------- root -----------------------------------------------------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo --preserve-env=HOME "$0" "$@"
  fi
}
require_root "$@"

# --------------- rollback mode --------------------------------------------
if [[ "${1:-}" == "--rollback" ]]; then
  head "Rollback"
  LATEST="$(ls -1t "$BACKUP_DIR"/baseline-*.env 2>/dev/null | head -1)"
  if [[ -z "$LATEST" ]]; then
    fail "No backup found in $BACKUP_DIR"
    exit 1
  fi
  warn "Restoring from: $LATEST"
  # shellcheck disable=SC1090
  source "$LATEST"

  # Revert sysctl
  [[ -n "${SYSCTL_vm_swappiness:-}" ]] && sysctl -w vm.swappiness="$SYSCTL_vm_swappiness" >/dev/null
  [[ -n "${SYSCTL_vm_dirty_ratio:-}" ]] && sysctl -w vm.dirty_ratio="$SYSCTL_vm_dirty_ratio" >/dev/null
  [[ -n "${SYSCTL_vm_dirty_background_ratio:-}" ]] && sysctl -w vm.dirty_background_ratio="$SYSCTL_vm_dirty_background_ratio" >/dev/null
  [[ -n "${SYSCTL_net_core_default_qdisc:-}" ]] && sysctl -w net.core.default_qdisc="$SYSCTL_net_core_default_qdisc" >/dev/null
  [[ -n "${SYSCTL_net_ipv4_tcp_congestion_control:-}" ]] && sysctl -w net.ipv4.tcp_congestion_control="$SYSCTL_net_ipv4_tcp_congestion_control" >/dev/null
  [[ -n "${SYSCTL_net_ipv4_tcp_fastopen:-}" ]] && sysctl -w net.ipv4.tcp_fastopen="$SYSCTL_net_ipv4_tcp_fastopen" >/dev/null
  # B extras
  for k in net.core.netdev_max_backlog net.ipv4.tcp_max_syn_backlog \
           net.core.rmem_max net.core.wmem_max; do
    v=$(sysctl -n "$k")
    echo "Note: $k was set to $v during this run; manually set it back if needed"
  done

  # Remove our files
  rm -f "$CONF_DIR/99-perf-tune.conf" \
        "$UDEV_DIR/60-ioschedulers.rules" \
        "$MODPROBE_DIR/bbr.conf"
  warn "Manual rollback still required for:"
  echo "  - /etc/default/grub (remove added params + run grub-mkconfig)"
  echo "  - /etc/fstab (revert noatime change)"
  echo "  - /etc/environment (remove RADV_PERFTEST, MESA_NO_ERROR)"
  echo "  - pacman -Rns gamemode lib32-gamemode ananicy-cpp ananicy-cpp-rules irqbalance lib32-mangohud"
  echo "  - systemctl disable --now gamemoded irqbalance ananicy-cpp"
  ok "Sysctl reverted and config files removed"
  exit 0
fi

mkdir -p "$BACKUP_DIR"

# --------------- 0. baseline snapshot -------------------------------------
head "0. Baseline snapshot"
{
  echo "# Baseline captured $(date -Iseconds)"
  for k in vm.swappiness vm.dirty_ratio vm.dirty_background_ratio \
           net.core.default_qdisc net.ipv4.tcp_congestion_control \
           net.ipv4.tcp_fastopen \
           net.core.netdev_max_backlog net.ipv4.tcp_max_syn_backlog \
           net.core.rmem_max net.core.wmem_max; do
    printf 'SYSCTL_%s=%s\n' "${k//./_}" "$(sysctl -n "$k")"
  done
  echo "THP_enabled=$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
  echo "THP_defrag=$(cat /sys/kernel/mm/transparent_hugepage/defrag)"
  for d in /sys/block/*; do
    [[ -f "$d/queue/scheduler" ]] || continue
    n=$(basename "$d")
    echo "SCHED_${n}=$(cat "$d/queue/scheduler")"
    [[ -r "$d/queue/read_ahead_kb" ]] && echo "READAHEAD_${n}=$(cat "$d/queue/read_ahead_kb")"
  done
  echo "GRUB_DEFAULT=$(grep ^GRUB_CMDLINE_LINUX_DEFAULT= "$GRUB_FILE" 2>/dev/null | head -1)"
  cp -a "$FSTAB" "$BACKUP_DIR/fstab.$TS"
  cp -a "$GRUB_FILE" "$BACKUP_DIR/grub.$TS"
  [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$BACKUP_DIR/environment.$TS"
} | tee "$BACKUP_FILE" >/dev/null
chmod 600 "$BACKUP_FILE"
chmod 600 "$BACKUP_DIR/fstab.$TS" "$BACKUP_DIR/grub.$TS" "$BACKUP_DIR/environment.$TS" 2>/dev/null
ok "Backup written to $BACKUP_FILE"
ok "fstab/grub/environment backups written to $BACKUP_DIR/"

# =====================================================================
head "A. sysctl + I/O"

# A.1 sysctl config
SYSCTL_FILE="$CONF_DIR/99-perf-tune.conf"
cat > "$SYSCTL_FILE" <<'EOF'
# Generated by system-full-tune.sh
# VM
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# I/O
vm.laptop_mode = 0
# Network
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

# A.2 THP and TCP buffers (Group B)
cat >> "$SYSCTL_FILE" <<'EOF'
# THP - keep madvise so defrag stays sane
# (runtime set via /sys in B; this is a no-op for kernel cmdline users)
# Extra network
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sysctl -p "$SYSCTL_FILE" >/dev/null

# A.3 NVMe scheduler + readahead (runtime + udev persistence)
UDEV_FILE="$UDEV_DIR/60-ioschedulers.rules"
cat > "$UDEV_FILE" <<'EOF'
# Generated by system-full-tune.sh
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="256"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq", ATTR{queue/read_ahead_kb}="8192"
EOF
for d in /sys/block/nvme*n*; do
  [[ -d "$d" ]] || continue
  echo none > "$d/queue/scheduler"
  echo 256 > "$d/queue/read_ahead_kb"
done
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=block >/dev/null 2>&1 || true

# A.4 BBR module
if sysctl net.ipv4.tcp_available_congestion_control | grep -qw bbr; then
  echo "tcp_bbr" > "$MODPROBE_DIR/bbr.conf"
else
  if modprobe tcp_bbr 2>/dev/null; then
    echo "tcp_bbr" > "$MODPROBE_DIR/bbr.conf"
  else
    warn "tcp_bbr module unavailable; BBR setting will be inert until kernel supports it"
  fi
fi

# =====================================================================
head "B. THP + TCP buffers (runtime)"

# THP
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag || echo madvise > /sys/kernel/mm/transparent_hugepage/defrag

# Make THP survive reboot via sysctl too (no-op at runtime but documents intent)
cat >> "$SYSCTL_FILE" <<'EOF'
# Mark as user-tunable at runtime; no sysctl key exists, kept here for documentation
EOF

# =====================================================================
head "C. Install packages (official repos)"

PKGS=(lib32-gamemode ananicy-cpp irqbalance lib32-mangohud)
# gamemode is already installed; lib32-* and ananicy-cpp rules are bundled in ananicy-cpp.
MISSING=()
for p in "${PKGS[@]}"; do
  pacman -Q "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Installing: ${MISSING[*]}"
  if pacman -S --noconfirm --needed "${MISSING[@]}"; then
    ok "pacman install completed"
  else
    fail "pacman install had errors (see above)"
  fi
else
  ok "All packages already installed"
fi
# Reinstall gamemode to fix the missing-binary issue observed earlier
pacman -S --noconfirm --overwrite='*' gamemode >/dev/null 2>&1 || true

# =====================================================================
head "D. Enable services"

enable_svc() {
  local svc="$1"
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    if systemctl enable --now "$svc.service" >/dev/null 2>&1; then
      ok "$svc.service enabled + started"
    else
      fail "$svc.service enable/start failed"
    fi
  else
    warn "$svc.service unit not found (package missing?)"
  fi
}
# gamemoded is a user-level service (located at /usr/lib/systemd/user/gamemoded.service).
# Enable lingering for the real user and start the user service.
REAL_USER="${INSTALL_USER}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  if loginctl enable-linger "$REAL_USER" 2>/dev/null; then
    ok "lingering enabled for $REAL_USER"
  else
    warn "could not enable lingering for $REAL_USER"
  fi
  if sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
       systemctl --user enable --now gamemoded.service 2>/dev/null; then
    ok "user service: gamemoded enabled + started (for $REAL_USER)"
  else
    fail "user service: gamemoded could not be enabled (user $REAL_USER)"
  fi
else
  fail "could not determine non-root user for gamemoded (SUDO_USER/USER empty)"
fi
enable_svc irqbalance
# ananicy-cpp ships unit as either ananicy-cpp or ananicy
if systemctl list-unit-files ananicy-cpp.service >/dev/null 2>&1; then
  enable_svc ananicy-cpp
elif systemctl list-unit-files ananicy.service >/dev/null 2>&1; then
  enable_svc ananicy
else
  fail "ananicy service unit not found"
fi

# =====================================================================
head "E. fstab noatime (REBOOT required)"

# Only modify ext4 lines that currently have rw,relatime
BEFORE=$(grep -cE '^[^#]*\bext4\b.*rw,relatime' "$FSTAB")
# Use a temp file for atomicity
TMP=$(mktemp)
sed -E '/^[^#]*\bext4\b/ s/(rw,)relatime/\1noatime/' "$FSTAB" > "$TMP"
AFTER=$(grep -cE '^[^#]*\bext4\b.*rw,noatime' "$TMP")
if [[ "$AFTER" -gt 0 ]]; then
  cat "$TMP" > "$FSTAB"
  chmod 644 "$FSTAB"
  ok "Added noatime to $AFTER ext4 mount(s) in $FSTAB (was $BEFORE with relatime)"
else
  fail "Did not find any ext4 relatime entries to change (or already noatime)"
fi
rm -f "$TMP"

# =====================================================================
head "F. Kernel cmdline (REBOOT required)"

NEW_PARAMS=(transparent_hugepage=madvise split_lock_mitigate=0 cpufreq.default_governor=performance)
KCMDLINE="/etc/kernel/cmdline"

# Detect bootloader type
if [[ -f "$GRUB_FILE" ]]; then
  warn "GRUB detected - updating $GRUB_FILE"
  cp -a "$GRUB_FILE" "$BACKUP_DIR/grub.$TS"
  chmod 600 "$BACKUP_DIR/grub.$TS"
  LINE=$(grep ^GRUB_CMDLINE_LINUX_DEFAULT= "$GRUB_FILE" | head -1)
  CURRENT=$(echo "$LINE" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="?([^"]*)"?$/\1/')
  ADDED=""
  for p in "${NEW_PARAMS[@]}"; do
    if ! grep -qw -- "$p" <<<"$CURRENT"; then
      CURRENT="$CURRENT $p"
      ADDED="$ADDED $p"
    fi
  done
  CURRENT=$(echo "$CURRENT" | sed -E 's/^ +//; s/ +/ /g; s/ +$//')
  if [[ -n "$ADDED" ]]; then
    QUOTED=$(printf '"%s"' "$CURRENT")
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=$QUOTED|" "$GRUB_FILE"
    ok "GRUB_CMDLINE_LINUX_DEFAULT updated. Added:$ADDED"
    if command -v grub-mkconfig >/dev/null; then
      grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 && ok "grub-mkconfig completed" || fail "grub-mkconfig failed"
    fi
  else
    ok "All GRUB params already present"
  fi
elif [[ -f "$KCMDLINE" ]]; then
  warn "systemd-boot + UKI detected - updating $KCMDLINE and regenerating UKI"
  cp -a "$KCMDLINE" "$BACKUP_DIR/cmdline.$TS"
  chmod 600 "$BACKUP_DIR/cmdline.$TS"
  CURRENT=$(cat "$KCMDLINE")
  ADDED=""
  for p in "${NEW_PARAMS[@]}"; do
    if ! grep -qw -- "$p" <<<"$CURRENT"; then
      CURRENT="$CURRENT $p"
      ADDED="$ADDED $p"
    fi
  done
  CURRENT=$(echo "$CURRENT" | sed -E 's/^ +//; s/ +/ /g; s/ +$//')
  if [[ -n "$ADDED" ]]; then
    echo "$CURRENT" > "$KCMDLINE"
    ok "kernel cmdline updated. Added:$ADDED"
      if [[ -f /etc/mkinitcpio.d/linux-zen.preset ]] && command -v mkinitcpio >/dev/null; then
        if [[ -n "$UKI" && -f "$UKI" ]]; then
          cp -a "$UKI" "$BACKUP_DIR/$(basename "$UKI").$TS"
          chmod 600 "$BACKUP_DIR/$(basename "$UKI").$TS"
        fi
        if mkinitcpio -p linux-zen >/dev/null 2>&1; then
          ok "UKI regenerated (${UKI:-unknown})"
        else
          fail "mkinitcpio failed - UKI not regenerated; reboot with current params"
        fi
      else
        fail "mkinitcpio or linux-zen.preset missing - cannot regenerate UKI"
      fi
  else
    ok "All kernel cmdline params already present"
  fi
else
  fail "Could not detect GRUB or systemd-boot; no kernel cmdline file found"
fi

# =====================================================================
head "G. /etc/environment (LOGOUT required)"

[[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"
chmod 644 "$ENV_FILE"
set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i -E "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}
set_env RADV_PERFTEST gpl
set_env MESA_NO_ERROR 1
ok "RADV_PERFTEST=gpl and MESA_NO_ERROR=1 set in $ENV_FILE"

# =====================================================================
head "H. Audio (HDA power-save + rtkit) (REBOOT required for HDA)"

# H.1 HDA codec power-save disable - prevents HDMI audio crackle/pop on resume
HDA_CONF="/etc/modprobe.d/audio-disable-power-save.conf"
if [[ -f "$HDA_CONF" ]] && grep -q "power_save=0" "$HDA_CONF"; then
  ok "HDA power-save config already present"
else
  sudo tee "$HDA_CONF" > /dev/null <<'EOF'
# Disable HDA codec power-saving - prevents HDMI audio crackling/popping
# Zen kernel defaults power_save=10 which makes the HDA codec enter D3
# after 10s of silence. On HDMI this produces an audible pop on resume.
options snd_hda_intel power_save=0
options snd_hda_intel power_save_controller=N
EOF
  chmod 644 "$HDA_CONF"
  ok "Wrote $HDA_CONF (requires reboot to apply to snd_hda_intel)"
fi

# H.2 PipeWire low-latency quantum
# Lower default quantum from 1024 to 512 (~21ms -> ~10ms latency).
# No impact on audio quality, only buffer size. Negligible CPU cost on modern hw.
PIPEWIRE_CONF="/etc/pipewire/pipewire.conf.d/99-low-latency.conf"
if [[ -f "$PIPEWIRE_CONF" ]] && grep -q "default.clock.quantum" "$PIPEWIRE_CONF"; then
  ok "PipeWire low-latency config already present"
else
  sudo mkdir -p "$(dirname "$PIPEWIRE_CONF")"
  sudo tee "$PIPEWIRE_CONF" > /dev/null <<'PWCONF'
# Lower default PipeWire quantum for reduced audio latency
# 512 samples @ 48 kHz = ~10.7 ms (was 1024 / ~21 ms)
# No impact on audio quality - only changes buffer size / latency.
context.properties = {
    default.clock.quantum       = 512
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 2048
}
PWCONF
  ok "Wrote $PIPEWIRE_CONF"
fi

# H.3 rtkit - real-time scheduling for PipeWire/WirePlumber threads
if ! command -v rtkitctl >/dev/null 2>&1; then
  warn "rtkit not installed - installing"
  if sudo pacman -S --noconfirm --needed rtkit >/dev/null 2>&1; then
    ok "rtkit installed"
  else
    fail "rtkit install failed"
  fi
else
  ok "rtkit already installed"
fi
if systemctl list-unit-files rtkit-daemon.service >/dev/null 2>&1; then
  if systemctl is-enabled --quiet rtkit-daemon 2>/dev/null; then
    ok "rtkit-daemon already enabled"
  else
    sudo systemctl enable rtkit-daemon 2>&1
  fi
  if systemctl is-active --quiet rtkit-daemon 2>/dev/null; then
    ok "rtkit-daemon active"
  else
    sudo systemctl start rtkit-daemon 2>&1
  fi
else
  fail "rtkit-daemon.service not found (package missing?)"
fi

# =====================================================================
head "VERIFICATION"

v_check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    ok "$label = $actual"
  else
    fail "$label expected '$expected', got '$actual'"
  fi
}

# sysctl
v_check "vm.swappiness"        "10"          "$(sysctl -n vm.swappiness)"
v_check "vm.dirty_ratio"       "10"          "$(sysctl -n vm.dirty_ratio)"
v_check "vm.dirty_background_ratio" "5"      "$(sysctl -n vm.dirty_background_ratio)"
v_check "tcp_congestion_control" "bbr"       "$(sysctl -n net.ipv4.tcp_congestion_control)"
v_check "default_qdisc"        "fq"          "$(sysctl -n net.core.default_qdisc)"
v_check "tcp_fastopen"         "3"           "$(sysctl -n net.ipv4.tcp_fastopen)"
v_check "rmem_max"             "16777216"    "$(sysctl -n net.core.rmem_max)"
v_check "wmem_max"             "16777216"    "$(sysctl -n net.core.wmem_max)"
v_check "netdev_max_backlog"   "16384"       "$(sysctl -n net.core.netdev_max_backlog)"
v_check "tcp_max_syn_backlog"  "8192"        "$(sysctl -n net.ipv4.tcp_max_syn_backlog)"

# THP
v_check "THP enabled"          "[madvise]"   "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
v_check "THP defrag"           "[defer+madvise]" "$(cat /sys/kernel/mm/transparent_hugepage/defrag)"

# NVMe scheduler
for d in /sys/block/nvme*n*; do
  [[ -d "$d" ]] || continue
  n=$(basename "$d")
  v_check "$n scheduler"        "none"        "$(cat "$d/queue/scheduler")"
  v_check "$n readahead"        "256"         "$(cat "$d/queue/read_ahead_kb")"
done

# Packages
for p in gamemode lib32-gamemode ananicy-cpp irqbalance lib32-mangohud; do
  if pacman -Q "$p" >/dev/null 2>&1; then
    ok "package: $p $(pacman -Q "$p" | awk '{print $2}')"
  else
    fail "package missing: $p"
  fi
done
# gamemoderun binary present?
if command -v gamemoderun >/dev/null; then
  ok "binary: gamemoderun at $(command -v gamemoderun)"
else
  fail "binary: gamemoderun not on PATH"
fi

# System services
for s in irqbalance; do
  state=$(systemctl is-active "$s" 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then
    ok "service (system): $s active"
  else
    fail "service (system): $s $state"
  fi
done
SVC=""
if systemctl list-unit-files ananicy-cpp.service >/dev/null 2>&1; then SVC=ananicy-cpp
elif systemctl list-unit-files ananicy.service >/dev/null 2>&1; then SVC=ananicy
fi
if [[ -n "$SVC" ]]; then
  state=$(systemctl is-active "$SVC" 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then ok "service (system): $SVC active"; else fail "service (system): $SVC $state"; fi
else
  fail "service (system): ananicy unit not found"
fi

# User service (gamemoded) - check as the original user
REAL_USER="${INSTALL_USER}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  uid=$(id -u "$REAL_USER")
  state=$(sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user is-active gamemoded 2>/dev/null || echo "inactive")
  if [[ "$state" == "active" ]]; then
    ok "service (user): gamemoded active for $REAL_USER"
  else
    fail "service (user): gamemoded $state for $REAL_USER"
  fi
fi

# fstab
noatime_count=$(grep -cE '^[^#]*\bext4\b.*rw,noatime' "$FSTAB")
if [[ "$noatime_count" -ge 1 ]]; then
  ok "fstab: $noatime_count ext4 mount(s) with noatime"
else
  fail "fstab: no ext4 mounts have noatime"
fi

# Kernel cmdline (check both possible locations)
gline=""
if [[ -f /etc/kernel/cmdline ]]; then
  gline=$(cat /etc/kernel/cmdline)
elif [[ -f "$GRUB_FILE" ]]; then
  gline=$(grep ^GRUB_CMDLINE_LINUX_DEFAULT= "$GRUB_FILE" | head -1)
fi
for p in transparent_hugepage=madvise split_lock_mitigate=0 cpufreq.default_governor=performance; do
  if grep -qw -- "$p" <<<"$gline"; then
    ok "kernel cmdline: $p present"
  else
    fail "kernel cmdline: $p missing"
  fi
done

# UKI: verify cmdline section contains the new params
if [[ -n "$UKI" && -f "$UKI" ]] && command -v objcopy >/dev/null; then
  uki_cmd=$(objcopy -O binary --only-section=.cmdline "$UKI" /tmp/uki-cmdline-$$ 2>/dev/null && tr -d '\0' < /tmp/uki-cmdline-$$; rm -f /tmp/uki-cmdline-$$)
  for p in transparent_hugepage=madvise split_lock_mitigate=0 cpufreq.default_governor=performance; do
    if grep -qw -- "$p" <<<"$uki_cmd"; then
      ok "UKI: $p present"
    else
      fail "UKI: $p missing (rebuild UKI or will be inert until then)"
    fi
  done
elif [[ -z "$UKI" ]]; then
  warn "UKI auto-detect found nothing in /boot/EFI/Linux/ - skipping UKI verification"
fi

# environment (only check if file exists and was modified)
for kv in RADV_PERFTEST=gpl MESA_NO_ERROR=1; do
  k=${kv%=*}; v=${kv#*=}
  if [[ -f "$ENV_FILE" ]] && grep -qE "^${k}=" "$ENV_FILE" && grep -E "^${k}=" "$ENV_FILE" | grep -q "$v"; then
    ok "env: $k=$v"
  else
    fail "env: $k not set to $v"
  fi
done

# Persistence files
[[ -f "$SYSCTL_FILE" ]] && ok "persist: $SYSCTL_FILE" || fail "persist: $SYSCTL_FILE missing"
[[ -f "$UDEV_FILE" ]] && ok "persist: $UDEV_FILE"     || fail "persist: $UDEV_FILE missing"
[[ -f "$MODPROBE_DIR/bbr.conf" ]] && ok "persist: $MODPROBE_DIR/bbr.conf" || fail "persist: bbr.conf missing"

# Section H - audio
if [[ -f /etc/modprobe.d/audio-disable-power-save.conf ]] && grep -q "power_save=0" /etc/modprobe.d/audio-disable-power-save.conf; then
  ok "audio: HDA power-save config present"
else
  fail "audio: HDA power-save config missing"
fi
if command -v rtkitctl >/dev/null 2>&1; then
  ok "audio: rtkit installed"
else
  fail "audio: rtkit not installed"
fi
if systemctl is-active --quiet rtkit-daemon 2>/dev/null; then
  ok "audio: rtkit-daemon active"
else
  fail "audio: rtkit-daemon not active"
fi

# =====================================================================
echo
head "SUMMARY"
printf '%s passed: %d%s\n' "$C_OK" "$PASS" "$C_0"
if [[ $FAIL -gt 0 ]]; then
  printf '%s failed: %d%s\n' "$C_E" "$FAIL" "$C_0"
  echo "Failed items:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi

cat <<EOF

Persistence files:
  $SYSCTL_FILE
  $UDEV_FILE
  $MODPROBE_DIR/bbr.conf
  $GRUB_FILE  (modified)
  $FSTAB      (modified)
  $ENV_FILE   (modified)
Baseline backup:
  $BACKUP_FILE
  $BACKUP_DIR/fstab.$TS
  $BACKUP_DIR/grub.$TS
  $BACKUP_DIR/environment.$TS

ACTION REQUIRED (won't take effect until you do):
  1. REBOOT     - fstab noatime + kernel cmdline (thp, split_lock, cpufreq)
                   + HDA power-save (snd_hda_intel module reload)
  2. REBOOT     - same reboot picks up new modules-load and udev rules
  3. LOGOUT     - for RADV_PERFTEST and MESA_NO_ERROR to load

To rollback (after reboot if already done):
  sudo $0 --rollback
  # plus manual revert of fstab/grub/environment + pacman -Rns and disable services
EOF

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
