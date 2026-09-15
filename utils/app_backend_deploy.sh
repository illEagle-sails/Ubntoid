#!/data/data/com.termux/files/usr/bin/bash
# app_backend_deploy.sh - Device-Specific Pre-Installation Optimizer
# Architecture: Single-Pass Memory Engine -> Device Profiling -> Fit-For-Device Dependency Set
#
# This is a pre-installation planning pass only: it does NOT compile or run
# `make install`. It profiles the current device (CPU arch/cores, RAM,
# display resolution, GPU driver, NPU presence) and then narrows the
# dependency set down to what actually matches that hardware, so the
# packages selected for install are tailored to the exact device instead of
# a one-size-fits-all list.

LOGFILE="$HOME/app_deploy_$(date +%s).log"
CATDIR="$HOME/app_dependencies"
TARGET_FILE="$HOME/targeted_pkgs.txt"
SIZE_FILE="$HOME/payload_size_kb.txt"
PROFILE_FILE="$HOME/device_profile.env"

mkdir -p "$CATDIR"
: > "$TARGET_FILE"
: > "$SIZE_FILE"
: > "$HOME/failed_pkgs.txt"

# Adapted strictly to the backend's hardware and compilation requirements
CATEGORIES=(
    "core_toolchain_objc"
    "gpu_npu_headers"
    "os_ram_abstraction"
    "screen_probe_display"
)

for cat in "${CATEGORIES[@]}"; do
    : > "$CATDIR/$cat.txt"
done

BATCH_SIZE=15
MAX_BATCH_SIZE=50
MIN_BATCH_SIZE=1
round=0
CORE_PKGS="apt dpkg bash coreutils termux-tools dash grep sed awk ncurses"

log() { echo -e "\033[1;36m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $*" | tee -a "$LOGFILE"; }
is_core_pkg() { echo "$CORE_PKGS" | grep -qw "$1"; }
rdep_count() { apt-cache rdepends --installed "$1" 2>/dev/null | tail -n +3 | grep -vc '^$'; }

resolve_conflict() {
    local newpkg="$1" oldpkg="$2"
    if is_core_pkg "$oldpkg"; then return 1; fi
    local new_score old_score
    new_score=$(rdep_count "$newpkg")
    old_score=$(rdep_count "$oldpkg")
    if [ "$new_score" -gt "$old_score" ]; then
        apt-get remove -y "$oldpkg" >"$LOGFILE" 2>&1
        apt-get install -y "$newpkg" >"$LOGFILE" 2>&1
        return 0
    else
        return 1
    fi
}

batch_install() {
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return
    log "Provisioning batch of ${#pkgs[@]} dependencies..."
    printf "%s\n" "${pkgs[@]}" > "$HOME/current_batch.tmp"

    if errlog=$(apt-get install -y --allow-downgrades --allow-change-held-packages "${pkgs[@]}" 2>&1); then
        echo "$errlog" > "$LOGFILE"
        BATCH_SIZE=$(( BATCH_SIZE + 3 ))
        [ $BATCH_SIZE -gt $MAX_BATCH_SIZE ] && BATCH_SIZE=$MAX_BATCH_SIZE
        grep -Fv -f "$HOME/current_batch.tmp" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp"
        mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
        return
    fi

    echo "$errlog" > "$LOGFILE"
    BATCH_SIZE=$(( BATCH_SIZE / 2 ))
    [ $BATCH_SIZE -lt $MIN_BATCH_SIZE ] && BATCH_SIZE=$MIN_BATCH_SIZE

    for pkg in "${pkgs[@]}"; do
        if single_err=$(apt-get install -y --allow-downgrades --allow-change-held-packages "$pkg" 2>&1); then
            grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
            continue
        fi
        if echo "$single_err" | grep -qiE "conflicts with|trying to overwrite|Breaks:"; then
            conflicting=$(echo "$single_err" | grep -oP '(?<=but )\S+(?=is)' | head -1)
            [ -z "$conflicting" ] && conflicting=$(apt-get install -s "$pkg" 2>&1 | grep -oP "(?<=Conflicts: )\S+" | head -1)
            if [ -n "$conflicting" ] && resolve_conflict "$pkg" "$conflicting"; then
                grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
            fi
        else
            grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
        fi
    done
}

# --- 0. DEVICE PROFILING (pre-installation, device-specific optimization) ---
# Detect the exact hardware this install is targeting so the dependency set
# selected below only includes what this specific device can actually use.

detect_arch() { uname -m 2>/dev/null || echo "unknown"; }

detect_cpu_cores() { nproc 2>/dev/null || echo "1"; }

detect_ram_mb() {
    local kb
    kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
    [ -z "$kb" ] && { echo "0"; return; }
    echo $(( kb / 1024 ))
}

detect_resolution() {
    # Prefer termux-api (termux-display-info) when installed; it works
    # without root and without ADB/system permissions.
    if command -v termux-display-info >/dev/null 2>&1; then
        local w h
        w=$(termux-display-info 2>/dev/null | grep -oP '(?<="width_pixels": )\d+' | head -1)
        h=$(termux-display-info 2>/dev/null | grep -oP '(?<="height_pixels": )\d+' | head -1)
        [ -n "$w" ] && [ -n "$h" ] && { echo "${w}x${h}"; return; }
    fi
    # Fallback: some devices expose the framebuffer's virtual size.
    if [ -r /sys/class/graphics/fb0/virtual_size ]; then
        local raw
        raw=$(tr -d ',' < /sys/class/graphics/fb0/virtual_size 2>/dev/null)
        [ -n "$raw" ] && { echo "$raw" | tr ' ' 'x'; return; }
    fi
    echo "unknown"
}

detect_gpu() {
    # ro.hardware.egl / ro.hardware.vulkan report the vendor GL/Vulkan driver
    # name (e.g. "adreno", "mali", "swiftshader").
    local egl vulkan
    egl=$(getprop ro.hardware.egl 2>/dev/null)
    vulkan=$(getprop ro.hardware.vulkan 2>/dev/null)
    if [ -n "$egl" ] || [ -n "$vulkan" ]; then
        echo "${egl:-unknown}${vulkan:+ / vulkan:$vulkan}"
    else
        echo "unknown"
    fi
}

detect_gpu_vulkan_support() {
    # Presence of a vendor vulkan driver name, or a loadable libvulkan, is
    # treated as "Vulkan available" for package-selection purposes.
    if [ -n "$(getprop ro.hardware.vulkan 2>/dev/null)" ]; then
        echo "yes"
    elif [ -e /system/lib64/libvulkan.so ] || [ -e /system/lib/libvulkan.so ]; then
        echo "yes"
    else
        echo "no"
    fi
}

detect_npu() {
    # Best-effort: look for known NPU/NNAPI vendor properties or HAL
    # libraries. Absence does not guarantee no NPU, but presence is a solid
    # positive signal.
    local hint
    hint=$(getprop 2>/dev/null | grep -iE 'npu|hexagon|neuralnetworks|edgetpu|apu' | head -1)
    if [ -n "$hint" ]; then
        echo "detected"
        return
    fi
    if compgen -G "/vendor/lib*/libneuralnetworks*.so" >/dev/null 2>&1 \
        || compgen -G "/vendor/lib*/*npu*.so" >/dev/null 2>&1; then
        echo "detected"
        return
    fi
    echo "not_detected"
}

detect_soc() { getprop ro.board.platform 2>/dev/null || echo "unknown"; }
detect_model() { getprop ro.product.model 2>/dev/null || echo "unknown"; }

profile_device() {
    log "[*] Profiling target device before selecting dependencies..."

    DEV_MODEL=$(detect_model)
    DEV_SOC=$(detect_soc)
    DEV_ARCH=$(detect_arch)
    DEV_CPU_CORES=$(detect_cpu_cores)
    DEV_RAM_MB=$(detect_ram_mb)
    DEV_RESOLUTION=$(detect_resolution)
    DEV_GPU=$(detect_gpu)
    DEV_GPU_VULKAN=$(detect_gpu_vulkan_support)
    DEV_NPU=$(detect_npu)

    {
        echo "DEV_MODEL=\"$DEV_MODEL\""
        echo "DEV_SOC=\"$DEV_SOC\""
        echo "DEV_ARCH=\"$DEV_ARCH\""
        echo "DEV_CPU_CORES=\"$DEV_CPU_CORES\""
        echo "DEV_RAM_MB=\"$DEV_RAM_MB\""
        echo "DEV_RESOLUTION=\"$DEV_RESOLUTION\""
        echo "DEV_GPU=\"$DEV_GPU\""
        echo "DEV_GPU_VULKAN=\"$DEV_GPU_VULKAN\""
        echo "DEV_NPU=\"$DEV_NPU\""
    } > "$PROFILE_FILE"

    log " -> Model: $DEV_MODEL ($DEV_SOC)"
    log " -> Arch: $DEV_ARCH | CPU cores: $DEV_CPU_CORES | RAM: ${DEV_RAM_MB} MB"
    log " -> Display: $DEV_RESOLUTION"
    log " -> GPU: $DEV_GPU (Vulkan: $DEV_GPU_VULKAN)"
    log " -> NPU: $DEV_NPU"
    log "[*] Device profile written to $PROFILE_FILE"
}

profile_device

# --- 1. SINGLE-PASS SCANNER (APP-SPECIFIC REGEX) ---
log "[*] Syncing remote repository indexes..."
apt-get update 2>&1 | tee -a "$LOGFILE"

log "[*] Identifying specific C/Objective-C/Hardware requirements..."

apt-cache dumpavail 2>/dev/null | awk -v catdir="$CATDIR" -v target_file="$TARGET_FILE" -v size_file="$SIZE_FILE" '
/^Package: / { pkg=$2; size=0; section=""; desc=""; next }
/^Section: / { section=tolower($2); next }
/^Installed-Size: / { size=$2; next }
/^Description: / {
    desc=tolower($0)
    combined = pkg " " section " " desc
    matched = 0

    # 1. Toolchain: Needs Clang/GCC for C, and libobjc/gnustep for the Objective-C bridge
    if (combined ~ /clang|gcc|make|binutils|pkg-config|libobjc2|gnustep-base/) {
        print pkg > catdir "/core_toolchain_objc.txt"
        matched = 1
    }
    # 2. Hardware Interfaces (GPU/NPU): OpenCL, Vulkan, Mesa for gpu_interface.c & npu_interface.c
    else if (combined ~ /opencl-headers|vulkan-headers|mesa|ocl-icd|vulkan-loader|nnapi|libdrm/) {
        print pkg > catdir "/gpu_npu_headers.txt"
        matched = 1
    }
    # 3. Memory & OS Abstraction: POSIX hooks for ram_manager.c & os_abstraction.c
    else if (combined ~ /hwloc|numactl|libevent|jemalloc/) {
        print pkg > catdir "/os_ram_abstraction.txt"
        matched = 1
    }
    # 4. Display Probing: Headers for screen_probe.c (Wayland/X11/EGL)
    else if (combined ~ /wayland-protocols|libx11-dev|libegl|libgles2/) {
        print pkg > catdir "/screen_probe_display.txt"
        matched = 1
    }

    # Restrict to strictly required packages, drop standard user applications
    if (matched && section ~ /devel|libdevel|libs|science/) {
        print pkg > target_file
        total_size += size
    }
}
END { print total_size > size_file }
'

# --- 1b. DEVICE-FIT FILTERING ---
# Drop categories that don't apply to what was actually detected on this
# device, so we don't pull in GPU/Vulkan/NPU headers a device can't use.
filter_target_for_device() {
    log "[*] Narrowing dependency set to fit detected hardware..."
    local tmp="$HOME/targeted_pkgs.device.tmp"
    : > "$tmp"

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue

        # If this package only appears in the GPU/NPU header category, only
        # keep it when the device actually reports a GPU or NPU.
        if grep -qx "$pkg" "$CATDIR/gpu_npu_headers.txt" 2>/dev/null; then
            if [ "$DEV_GPU" = "unknown" ] && [ "$DEV_NPU" = "not_detected" ]; then
                log "   - Skipping $pkg (no GPU/NPU detected on this device)"
                continue
            fi
            if echo "$pkg" | grep -qi vulkan && [ "$DEV_GPU_VULKAN" = "no" ]; then
                log "   - Skipping $pkg (device has no Vulkan driver)"
                continue
            fi
        fi

        # Display-probe packages only matter if a resolution/display was
        # actually detected.
        if grep -qx "$pkg" "$CATDIR/screen_probe_display.txt" 2>/dev/null; then
            if [ "$DEV_RESOLUTION" = "unknown" ]; then
                log "   - Skipping $pkg (no display detected to probe)"
                continue
            fi
        fi

        echo "$pkg" >> "$tmp"
    done < "$TARGET_FILE"

    mv "$tmp" "$TARGET_FILE"
}

filter_target_for_device

# --- 2. STORAGE SAFEGUARD (ADAPTED FOR APP OVERHEAD, SCALED TO DEVICE RAM) ---
TOTAL_TARGETS=$(wc -l < "$TARGET_FILE")
PAYLOAD_KB=$(cat "$SIZE_FILE")
[ -z "$PAYLOAD_KB" ] && PAYLOAD_KB=0

PAYLOAD_MB=$(( PAYLOAD_KB / 1024 ))
ESTIMATED_TOTAL_MB=$(( PAYLOAD_MB + (PAYLOAD_MB / 2) )) # 50% overhead for compiler temporary files

# Scale the safety buffer down on low-RAM devices instead of always
# demanding a flat 32GB, which can be an unreasonable ask on some phones.
if [ "${DEV_RAM_MB:-0}" -gt 0 ] && [ "$DEV_RAM_MB" -lt 6144 ]; then
    BUFFER_MB=8192
    log "[*] Low-RAM device detected (${DEV_RAM_MB} MB) — reducing safety buffer to 8 GB."
else
    BUFFER_MB=32768
fi

REQUIRED_MB=$(( ESTIMATED_TOTAL_MB + BUFFER_MB ))
CURRENT_FREE_MB=$(df -m "$PREFIX" | awk 'NR==2 {print $4}')

log "[*] Missing dependencies identified: $TOTAL_TARGETS packages (after device-fit filtering)."
log " -> Safety Buffer: ${BUFFER_MB} MB"
log " -> Total Space Required: ${REQUIRED_MB} MB | Current Free: ${CURRENT_FREE_MB} MB"

if [ "$CURRENT_FREE_MB" -lt "$REQUIRED_MB" ]; then
    log "FATAL: Insufficient hardware capacity for this device-optimized dependency set."
    exit 1
fi

# --- 3. BATCH DEPLOYMENT ---
while [ -s "$TARGET_FILE" ]; do
    round=$((round+1))
    REMAINING=$(wc -l < "$TARGET_FILE")
    log "=== DEPENDENCY RESOLUTION ROUND $round : $REMAINING targets ==="

    dpkg --configure -a >"$LOGFILE" 2>&1
    apt-get --fix-broken install -y >"$LOGFILE" 2>&1

    mapfile -t pkgs < <(head -n "$BATCH_SIZE" "$TARGET_FILE")
    batch_install "${pkgs[@]}"
done

log "[*] Dependency matrices locked and loaded."

# --- 4. PRE-INSTALLATION SUMMARY ---
# This script stops at dependency provisioning; it intentionally does NOT
# build/compile anything. The device profile plus the trimmed, installed
# dependency set are the deliverable, so a later install/build step can rely
# on both being already fitted to this exact device.
log "===================================================="
log "[*] PRE-INSTALLATION DEVICE-FIT PROVISIONING COMPLETE"
log "===================================================="
log "Device profile: $PROFILE_FILE"
log "Installed/attempted dependency lists: $CATDIR/"
log "Any packages that failed to install: $HOME/failed_pkgs.txt"
log "[*] Operation Complete."
