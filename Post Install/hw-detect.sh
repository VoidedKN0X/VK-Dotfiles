#!/bin/bash
# hw-detect.sh - what hardware this runs on, as functions. Not run on its own:
# install-common.sh and run-all-common.sh source it, so the install and the
# tuning detect the same way. Read-only: it only looks at /proc and /sys.

# The CPU's maker: "amd", "intel" or "other"
hw_cpu_vendor() {
    case $(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo 2>/dev/null) in
    AuthenticAMD) echo amd ;;
    GenuineIntel) echo intel ;;
    *) echo other ;;
    esac
}

# Every graphics chip (PCI display class 0x03xxxx), one line each:
# "<vendor> <device id>", vendor "amd", "intel" or "nvidia". Read from the PCI
# bus, so it also finds a card whose driver isn't loaded (yet).
hw_gpus() {
    local dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        read -r class <"$dev/class" 2>/dev/null || continue
        [[ $class == 0x03* ]] || continue
        read -r vendor <"$dev/vendor" 2>/dev/null || continue
        case $vendor in
        0x1002) echo "amd $(<"$dev/device")" ;;
        0x8086) echo "intel $(<"$dev/device")" ;;
        0x10de) echo "nvidia $(<"$dev/device")" ;;
        esac
    done
}

# The graphics makers, each once: "amd", "intel", "nvidia"
hw_gpu_vendors() {
    hw_gpus | awk '{ print $1 }' | sort -u
}

# An NVIDIA card that the current driver (590 and newer, open kernel modules)
# supports: Turing (GTX 16, RTX 20) or newer, PCI device id 0x1e00 and up.
# Pascal (GTX 10) and older need the legacy nvidia-580xx-dkms from the AUR.
hw_nvidia_supported() {
    local vendor device
    while read -r vendor device; do
        [[ $vendor == nvidia ]] && (( device >= 0x1e00 )) && return 0
    done < <(hw_gpus)
    return 1
}

# A laptop (or another battery-powered PC): a system battery (not a mouse's
# or a controller's: those have scope "Device"), or a portable chassis type
# (8 portable, 9 laptop, 10 notebook, 11 handheld, 14 sub-notebook,
# 30 tablet, 31 convertible, 32 detachable).
hw_is_laptop() {
    local bat
    for bat in /sys/class/power_supply/*; do
        [[ $(cat "$bat/type" 2>/dev/null) == Battery ]] || continue
        [[ $(cat "$bat/scope" 2>/dev/null) == Device ]] && continue
        return 0
    done
    case $(cat /sys/class/dmi/id/chassis_type 2>/dev/null) in
    8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) return 0 ;;
    esac
    return 1
}
