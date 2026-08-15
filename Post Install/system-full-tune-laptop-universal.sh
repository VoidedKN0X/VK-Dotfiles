#!/usr/bin/env bash
# system-full-tune-laptop.sh
# Comprehensive, self-verifying, reversible performance tune for Arch Linux laptops.
# Derived from system-full-tune.sh (desktop version) with laptop-friendly adjustments.
#
# Changes from desktop version:
#   - Username auto-detected (no hardcoded INSTALL_USER)
#   - Kernel images regenerated for ALL detected presets (mkinitcpio -P)
#   - cpufreq governor: NOT set on the kernel cmdline (auto-cpufreq handles it)
#   - vm.laptop_mode = 5 (allows disk write-back batching to save power)
#   - HDA power-save fix kept (still useful for HDMI output, comment generalized)
#   - split_lock_mitigate=0 kept (safe on modern CPUs, no real downside for laptops)
#
# Groups applied (all approved):
#   A. sysctl + I/O (NVMe scheduler, swappiness, BBR, readahead, dirty pages)
#   B. THP madvise + TCP buffers + netdev backlog
#   C. Install: gamemode, lib32-gamemode, ananicy-cpp, irqbalance, lib32-mangohud
#   D. Enable: gamemoded, irqbalance, ananicy-cpp
#   E. fstab noatime (REBOOT required)
#   F. systemd-boot kernel cmdline: thp=madvise, split_lock_mitigate=0
#      (REBOOT required, UKI regenerated). cpufreq governor is left to
#      auto-cpufreq unless CPUFREQ_GOVERNOR is explicitly set.
#   G. /etc/environment: RADV_PERFTEST=gpl, MESA_NO_ERROR=1 (LOGOUT required)
#   H. Audio: HDA power-save off + rtkit install/enable (REBOOT required for HDA)
#
# Persistence:
#   /etc/sysctl.d/99-perf-tune.conf
#   /etc/udev/rules.d/60-ioschedulers.rules
#   /etc/modules-load.d/bbr.conf
#   /etc/kernel/cmdline          (modified, systemd-boot)
#   /etc/fstab                   (modified)
#   /etc/environment             (modified)
#
# Backup: /var/lib/perf-tune-backup/baseline.env (chmod 600)
# Rollback: see final output, or run "system-full-tune-laptop.sh --rollback"

set -uo pipefail

# === USER CONFIG (edit these on a fresh install) ===
# INSTALL_USER: auto-detected from SUDO_USER, then logname, then $USER.
# Override here only if auto-detection picks the wrong account.
INSTALL_USER="${INSTALL_USER:-}"
# Filesystems to convert relatime->noatime in fstab (space-separated list).
# Auto-detected from fstab (local, non-pseudo fs) if left empty.
FILESYSTEM=""

# Laptop-friendly sysctl/cmdline values
LAPTOP_MODE=5            # was 0 on desktop; 5 lets the kernel batch writes
# CPUFREQ_GOVERNOR: left empty by default. auto-cpufreq dynamically switches
# between performance/powersave based on AC state, so a static kernel-cmdline
# default governor would be redundant. Set this (e.g. "schedutil") if you
# ever stop using auto-cpufreq and want a fixed boot-time governor.
CPUFREQ_GOVERNOR=""

CONF_DIR="/etc/sysctl.d"
UDEV_DIR="/etc/udev/rules.d"
MODPROBE_DIR="/etc/modules-load.d"
FSTAB="/etc/fstab"
ENV_FILE="/etc/environment"
KCMDLINE="/etc/kernel/cmdline"
BACKUP_DIR="/var/lib/perf-tune-backup"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/baseline-$TS.env"

# === AUTO-DETECT non-root user (for gamemoded user service) ===
# Priority: explicit INSTALL_USER override > SUDO_USER > logname > $USER
detect_user() {
  if [[ -n "$INSTALL_USER" ]]; then
    echo "$INSTALL_USER"
    return
  fi
  local u
  u="${SUDO_USER:-}"
  [[ -z "$u" ]] && u="$(logname 2>/dev/null || true)"
  [[ -z "$u" ]] && u="${USER:-}"
  # Fall back to the first human (UID >= 1000) account if we still have nothing
  if [[ -z "$u" || "$u" == "root" ]]; then
    u="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"
  fi
  echo "$u"
}

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
           net.core.rmem_max net.core.wmem_max vm.laptop_mode; do
    v=$(sysctl -n "$k")
    echo "Note: $k was set to $v during this run; manually set it back if needed"
  done

  # Remove our files
  rm -f "$CONF_DIR/99-perf-tune.conf" \
        "$UDEV_DIR/60-ioschedulers.rules" \
        "$MODPROBE_DIR/bbr.conf"
  warn "Manual rollback still required for:"
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
  for k in vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.laptop_mode \
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
  cp -a "$FSTAB" "$BACKUP_DIR/fstab.$TS"
  cp -a "$KCMDLINE" "$BACKUP_DIR/cmdline.$TS" 2>/dev/null
  [[ -f "$ENV_FILE" ]] && cp -a "$ENV_FILE" "$BACKUP_DIR/environment.$TS"
} | tee "$BACKUP_FILE" >/dev/null
chmod 600 "$BACKUP_FILE"
chmod 600 "$BACKUP_DIR/fstab.$TS" "$BACKUP_DIR/cmdline.$TS" "$BACKUP_DIR/environment.$TS" 2>/dev/null
ok "Backup written to $BACKUP_FILE"
ok "fstab/cmdline/environment backups written to $BACKUP_DIR/"

# =====================================================================
head "A. sysctl + I/O"

# A.1 sysctl config
SYSCTL_FILE="$CONF_DIR/99-perf-tune.conf"
cat > "$SYSCTL_FILE" <<EOF
# Generated by system-full-tune-laptop.sh
# VM
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
# I/O
vm.laptop_mode = ${LAPTOP_MODE}
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

# A.3 I/O scheduler + readahead (runtime + udev persistence)
# Detect which schedulers this kernel provides, then only emit rules that
# reference available schedulers (bfq is not built into every kernel).
AVAIL_SCHEDS=""
for d in /sys/block/*; do
  [[ -f "$d/queue/scheduler" ]] || continue
  AVAIL_SCHEDS="$AVAIL_SCHEDS $(cat "$d/queue/scheduler")"
done
HDD_SCHED=""
for s in bfq mq-deadline deadline none; do
  if grep -qw "$s" <<<"$AVAIL_SCHEDS"; then HDD_SCHED="$s"; break; fi
done
if [[ -n "$HDD_SCHED" ]]; then
  ok "HDD scheduler available on this kernel: $HDD_SCHED"
else
  warn "no HDD scheduler candidate (bfq/mq-deadline) found on this kernel"
fi

UDEV_FILE="$UDEV_DIR/60-ioschedulers.rules"
{
  printf '# Generated by system-full-tune-laptop.sh\n'
  printf '# NVMe (multi-queue) -> none scheduler, 256 KiB readahead\n'
  printf 'ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="256"\n'
  if [[ -n "$HDD_SCHED" ]]; then
    printf '# Rotational disks -> %s scheduler, 8 MiB readahead\n' "$HDD_SCHED"
    printf 'ACTION=="add|change", KERNEL=="sd[a-z]*|vd[a-z]*|mmcblk*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="%s", ATTR{queue/read_ahead_kb}="8192"\n' "$HDD_SCHED"
  else
    printf '# No suitable HDD scheduler available on this kernel; rule omitted\n'
  fi
} > "$UDEV_FILE"

for d in /sys/block/nvme[0-9]*n[0-9]*; do
  [[ -d "$d" ]] || continue
  echo none > "$d/queue/scheduler" 2>/dev/null
  echo 256 > "$d/queue/read_ahead_kb" 2>/dev/null
done
if [[ -n "$HDD_SCHED" ]]; then
  for d in /sys/block/sd[a-z]* /sys/block/vd[a-z]* /sys/block/mmcblk*; do
    [[ -d "$d" ]] || continue
    [[ "$(cat "$d/queue/rotational" 2>/dev/null)" == "1" ]] || continue
    echo "$HDD_SCHED" > "$d/queue/scheduler" 2>/dev/null
    echo 8192 > "$d/queue/read_ahead_kb" 2>/dev/null
  done
fi
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

# THP (defer+madvise exists only on newer kernels; fall back to madvise)
THP_DEFRAG_TARGET="defer+madvise"
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null \
  || { THP_DEFRAG_TARGET="madvise"; echo "$THP_DEFRAG_TARGET" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null; }

# Make THP survive reboot via sysctl too (no-op at runtime but documents intent)
cat >> "$SYSCTL_FILE" <<'EOF'
# Mark as user-tunable at runtime; no sysctl key exists, kept here for documentation
EOF

# =====================================================================
head "C. Install packages (official repos)"

PKGS=(ananicy-cpp irqbalance)
# lib32-* packages only exist on x86_64
if [[ "$(uname -m)" == "x86_64" ]]; then
  PKGS+=(lib32-gamemode lib32-mangohud)
fi
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
REAL_USER="$(detect_user)"
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

# Auto-detect local filesystems from fstab (unless FILESYSTEM is set)
if [[ -z "$FILESYSTEM" ]]; then
  _skip_fs='^(proc|sysfs|tmpfs|devtmpfs|devpts|devfs|cgroup[0-9]*|securityfs|debugfs|tracefs|pstore|bpf|autofs|hugetlbfs|mqueue|configfs|fusectl|efivarfs|binfmt_misc|rpc_pipefs|ramfs|overlay)$'
  _skip_net='^(nfs[0-9]?|cifs|smb[0-9]?|sshfs|afs|9p|fuse\.sshfs|fuse\.portal)$'
  FILESYSTEM=$(awk -v s="$_skip_fs" -v n="$_skip_net" \
    '!/^[[:space:]]*#/ && NF>=4 && $3 !~ s && $3 !~ n {print $3}' "$FSTAB" | sort -u | tr '\n' ' ')
  FILESYSTEM="${FILESYSTEM% }"
fi
FS_REGEX="^(${FILESYSTEM// /|})$"

# Convert relatime -> noatime only for the matched filesystems
BEFORE=$(awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,relatime/' "$FSTAB" | wc -l)
TMP=$(mktemp)
awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,relatime/ { sub(/rw,relatime/, "rw,noatime") } { print }' "$FSTAB" > "$TMP"
AFTER=$(awk -v fs="$FS_REGEX" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,noatime/' "$TMP" | wc -l)
if [[ "$AFTER" -gt 0 ]]; then
  cat "$TMP" > "$FSTAB"
  chmod 644 "$FSTAB"
  ok "Added noatime to $AFTER mount(s) [${FILESYSTEM// /, }] in $FSTAB (was $BEFORE with relatime)"
else
  fail "Did not find any relatime entries to change (filesystems: ${FILESYSTEM:-none})"
fi
rm -f "$TMP"

# =====================================================================
head "F. Kernel cmdline (REBOOT required)"

NEW_PARAMS=(transparent_hugepage=madvise split_lock_mitigate=0)
# Only add cpufreq.default_governor= to the cmdline if a value is set.
# On this laptop, auto-cpufreq manages the governor at runtime, so the
# kernel-cmdline default is usually omitted.
[[ -n "$CPUFREQ_GOVERNOR" ]] && NEW_PARAMS+=(cpufreq.default_governor="$CPUFREQ_GOVERNOR")

# systemd-boot: the kernel cmdline lives in /etc/kernel/cmdline
if [[ ! -f "$KCMDLINE" ]]; then
  fail "systemd-boot kernel cmdline file not found: $KCMDLINE"
else
  warn "systemd-boot + UKI detected - updating $KCMDLINE and regenerating images"
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

    # Back up every existing UKI (kernel-agnostic)
    for _u in /boot/EFI/Linux/*.efi; do
      [[ -f "$_u" ]] || continue
      cp -a "$_u" "$BACKUP_DIR/$(basename "$_u").$TS"
      chmod 600 "$BACKUP_DIR/$(basename "$_u").$TS"
    done

    # Regenerate images for ALL detected kernels, not a hardcoded one.
    if command -v mkinitcpio >/dev/null && [[ -n "$(find /etc/mkinitcpio.d -maxdepth 1 -name '*.preset' 2>/dev/null)" ]]; then
      if mkinitcpio -P >/dev/null 2>&1; then
        ok "mkinitcpio regenerated images for all presets"
      else
        fail "mkinitcpio -P failed - images not regenerated; reboot with current params"
      fi
    elif command -v dracut >/dev/null; then
      if dracut --regenerate-all >/dev/null 2>&1; then
        ok "dracut regenerated all initramfs images"
      else
        fail "dracut --regenerate-all failed"
      fi
    else
      fail "no initramfs tool (mkinitcpio/dracut) or presets found - cannot regenerate images"
    fi

    # Re-pick the most recently modified UKI for later verification
    mapfile -t _UKI_ALL < <(find /boot/EFI/Linux -maxdepth 1 -name '*.efi' -type f 2>/dev/null | sort)
    if [[ ${#_UKI_ALL[@]} -gt 0 ]]; then
      UKI=$(ls -1t "${_UKI_ALL[@]}" | head -1)
    fi
    unset _UKI_ALL
  else
    ok "All kernel cmdline params already present"
  fi
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
set_env MESA_NO_ERROR 1
# RADV_PERFTEST=gpl is only meaningful on AMD GPUs (harmless elsewhere)
if command -v lspci >/dev/null && lspci -nn 2>/dev/null | grep -qi '1002:'; then
  set_env RADV_PERFTEST gpl
  ok "AMD GPU detected; RADV_PERFTEST=gpl and MESA_NO_ERROR=1 set in $ENV_FILE"
else
  warn "No AMD GPU detected; only MESA_NO_ERROR=1 set in $ENV_FILE"
fi

# =====================================================================
head "H. Audio (HDA power-save + rtkit) (REBOOT required for HDA)"

# H.1 HDA codec power-save disable - prevents HDMI audio crackle/pop on resume
# Kept for laptop use: relevant when the laptop is hooked up to an external
# display/HDMI/DP output and the HDA codec power-saving otherwise pops.
HDA_CONF="/etc/modprobe.d/audio-disable-power-save.conf"
if [[ -f "$HDA_CONF" ]] && grep -q "power_save=0" "$HDA_CONF"; then
  ok "HDA power-save config already present"
else
  sudo tee "$HDA_CONF" > /dev/null <<'EOF'
# Disable HDA codec power-saving - prevents HDMI audio crackling/popping
# Default power_save=10 lets the HDA codec enter D3 after 10s of silence,
# which can produce an audible pop on resume from HDMI/DP outputs.
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
v_check "vm.laptop_mode"       "$LAPTOP_MODE" "$(sysctl -n vm.laptop_mode)"
v_check "tcp_congestion_control" "bbr"       "$(sysctl -n net.ipv4.tcp_congestion_control)"
v_check "default_qdisc"        "fq"          "$(sysctl -n net.core.default_qdisc)"
v_check "tcp_fastopen"         "3"           "$(sysctl -n net.ipv4.tcp_fastopen)"
v_check "rmem_max"             "16777216"    "$(sysctl -n net.core.rmem_max)"
v_check "wmem_max"             "16777216"    "$(sysctl -n net.core.wmem_max)"
v_check "netdev_max_backlog"   "16384"       "$(sysctl -n net.core.netdev_max_backlog)"
v_check "tcp_max_syn_backlog"  "8192"        "$(sysctl -n net.ipv4.tcp_max_syn_backlog)"

# THP
v_check "THP enabled"          "[madvise]"   "$(cat /sys/kernel/mm/transparent_hugepage/enabled)"
v_check "THP defrag"           "[${THP_DEFRAG_TARGET:-madvise}]" "$(cat /sys/kernel/mm/transparent_hugepage/defrag)"

# NVMe scheduler
for d in /sys/block/nvme[0-9]*n[0-9]*; do
  [[ -d "$d" ]] || continue
  n=$(basename "$d")
  v_check "$n scheduler"        "none"        "$(cat "$d/queue/scheduler")"
  v_check "$n readahead"        "256"         "$(cat "$d/queue/read_ahead_kb")"
done

# Packages
PKG_CHECK=(gamemode ananicy-cpp irqbalance)
if [[ "$(uname -m)" == "x86_64" ]]; then
  PKG_CHECK+=(lib32-gamemode lib32-mangohud)
fi
for p in "${PKG_CHECK[@]}"; do
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
REAL_USER="$(detect_user)"
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
noatime_count=$(awk -v fs="${FS_REGEX:-}" '!/^[[:space:]]*#/ && NF>=4 && $3 ~ fs && $4 ~ /rw,noatime/' "$FSTAB" | wc -l)
if [[ "$noatime_count" -ge 1 ]]; then
  ok "fstab: $noatime_count mount(s) [${FILESYSTEM// /, }] with noatime"
else
  fail "fstab: no mounts have noatime"
fi

# Kernel cmdline (systemd-boot)
gline=""
[[ -f "$KCMDLINE" ]] && gline=$(cat "$KCMDLINE")
VERIFY_PARAMS=(transparent_hugepage=madvise split_lock_mitigate=0)
[[ -n "$CPUFREQ_GOVERNOR" ]] && VERIFY_PARAMS+=(cpufreq.default_governor="$CPUFREQ_GOVERNOR")
for p in "${VERIFY_PARAMS[@]}"; do
  if grep -qw -- "$p" <<<"$gline"; then
    ok "kernel cmdline: $p present"
  else
    fail "kernel cmdline: $p missing"
  fi
done

# UKI: verify cmdline section contains the new params
if [[ -n "$UKI" && -f "$UKI" ]] && command -v objcopy >/dev/null; then
  uki_cmd=$(objcopy -O binary --only-section=.cmdline "$UKI" /tmp/uki-cmdline-$$ 2>/dev/null && tr -d '\0' < /tmp/uki-cmdline-$$; rm -f /tmp/uki-cmdline-$$)
  for p in "${VERIFY_PARAMS[@]}"; do
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
ENV_CHECKS="MESA_NO_ERROR=1"
if command -v lspci >/dev/null && lspci -nn 2>/dev/null | grep -qi '1002:'; then
  ENV_CHECKS="$ENV_CHECKS RADV_PERFTEST=gpl"
fi
for kv in $ENV_CHECKS; do
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
  $KCMDLINE   (modified, systemd-boot)
  $FSTAB      (modified)
  $ENV_FILE   (modified)
Baseline backup:
  $BACKUP_FILE
  $BACKUP_DIR/fstab.$TS
  $BACKUP_DIR/cmdline.$TS
  $BACKUP_DIR/environment.$TS

ACTION REQUIRED (won't take effect until you do):
  1. REBOOT     - fstab noatime + kernel cmdline (thp, split_lock, cpufreq)
                   + HDA power-save (snd_hda_intel module reload)
  2. REBOOT     - same reboot picks up new modules-load and udev rules
  3. LOGOUT     - for RADV_PERFTEST and MESA_NO_ERROR to load

To rollback (after reboot if already done):
  sudo $0 --rollback
  # plus manual revert of fstab/cmdline/environment + pacman -Rns and disable services
EOF

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
