#!/data/data/com.termux/files/usr/bin/bash
# ius_accelerated_v2.sh - High-Performance Domain Mass-Installer
# Architecture: Single-Pass Memory Engine with 32GB Storage Safeguard

LOGFILE="$HOME/ius_accelerated_$(date +%s).log"
CATDIR="$HOME/ius_categories"
TARGET_FILE="$HOME/targeted_pkgs.txt"
SIZE_FILE="$HOME/payload_size_kb.txt"

mkdir -p "$CATDIR"
: > "$TARGET_FILE"
: > "$SIZE_FILE"
: > "$HOME/failed_pkgs.txt"

CATEGORIES=(
    "llm_compute_and_drivers"
    "compilers_runtimes"
    "quantum_science_simulators"
    "active_defense_sandboxes"
    "material_sensory_ux"
    "optimization_admin_utility"
)

for cat in "${CATEGORIES[@]}"; do
    : > "$CATDIR/$cat.txt"
done

# Orchestration parameters
BATCH_SIZE=15
MAX_BATCH_SIZE=50
MIN_BATCH_SIZE=1
round=0
CORE_PKGS="apt dpkg bash coreutils termux-tools dash grep sed awk ncurses"

log() {
    echo -e "\033[1;36m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $*" | tee -a "$LOGFILE"
}

is_core_pkg() { echo "$CORE_PKGS" | grep -qw "$1"; }
rdep_count() { apt-cache rdepends --installed "$1" 2>/dev/null | tail -n +3 | grep -vc '^$'; }

resolve_conflict() {
    local newpkg="$1" oldpkg="$2"
    if is_core_pkg "$oldpkg"; then
        log "CRITICAL: $newpkg conflicts with core package $oldpkg. Skipping."
        return 1
    fi
    local new_score old_score
    new_score=$(rdep_count "$newpkg")
    old_score=$(rdep_count "$oldpkg")
    if [ "$new_score" -gt "$old_score" ]; then
        log "Removing $oldpkg in favor of $newpkg (rdep: $new_score > $old_score)"
        apt-get remove -y "$oldpkg" >"$LOGFILE" 2>&1
        apt-get install -y "$newpkg" >"$LOGFILE" 2>&1
        return 0
    else
        log "Keeping $oldpkg, skipping $newpkg"
        return 1
    fi
}

batch_install() {
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return
    log "Deploying accelerated batch of ${#pkgs[@]} items... (Batch Limit: $BATCH_SIZE)"
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

    log "Batch collision detected. Isolating conflicts..."
    for pkg in "${pkgs[@]}"; do
        if single_err=$(apt-get install -y --allow-downgrades --allow-change-held-packages "$pkg" 2>&1); then
            grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
            continue
        fi
        echo "$single_err" > "$LOGFILE"
        if echo "$single_err" | grep -qiE "conflicts with|trying to overwrite|Breaks:"; then
            conflicting=$(echo "$single_err" | grep -oP '(?<=but )\S+(?=is)' | head -1)
            [ -z "$conflicting" ] && conflicting=$(apt-get install -s "$pkg" 2>&1 | grep -oP "(?<=Conflicts: )\S+" | head -1)
            if [ -n "$conflicting" ] && resolve_conflict "$pkg" "$conflicting"; then
                grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
            fi
        else
            echo "$pkg : install failed" > "$HOME/failed_pkgs.txt"
            grep -vx "$pkg" "$TARGET_FILE" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$TARGET_FILE"
        fi
    done
}

# --- 1. THE SINGLE-PASS SCANNER ENGINE ---
log "[*] Syncing remote Termux repository indexes..."
apt-get update 2>&1 | tee -a "$LOGFILE"

log "[*] Initiating single-pass memory sweep of package database..."

# apt-cache dumpavail streams the whole DB. awk parses it natively in milliseconds.
apt-cache dumpavail 2>/dev/null | awk -v catdir="$CATDIR" -v target_file="$TARGET_FILE" -v size_file="$SIZE_FILE" '
/^Package: / { pkg=$2; size=0; section=""; desc=""; next }
/^Section: / { section=tolower($2); next }
/^Installed-Size: / { size=$2; next }
/^Description: / {
    desc=tolower($0)
    combined = pkg " " section " " desc
    matched = 0

    # Rule 1: LLM, AI Agents, AND Hardware Acceleration
    if (combined ~ /llm|llama|ollama|pytorch|tensorflow|huggingface|inference|agent|gpt|langchain|onnx|openblas|mesa|turnip|freedreno|vulkan|opencl|ocl-icd|clinfo|clblast|kgsl|zink|virgl|gpu|compute|acceleration/) {
        print pkg > catdir "/llm_compute_and_drivers.txt"
        matched = 1
    }
    # Rule 2: Advanced Compilers and Cross-Platform Runtimes
    else if (combined ~ /compiler|clang|gcc|llvm|make|cmake|nodejs|openjdk|python|golang|rustc|elixir|lua|perl|php|nim|zig|fortran/ || section ~ /^(devel|libdevel|interpreters|haskell|python|golang|rust|java|ruby)$/) {
        print pkg > catdir "/compilers_runtimes.txt"
        matched = 1
    }
    # Rule 3: Quantum, Computations, Physical Simulators & Science
    else if (combined ~ /quantum|physics|simulation|matrix|lapack|numpy|scipy|octave|gnuplot|fft|graphviz|calc/ || section ~ /^(science|math)$/) {
        print pkg > catdir "/quantum_science_simulators.txt"
        matched = 1
    }
    # Rule 4: Active Defense & Sandboxes
    else if (combined ~ /exploit|pentest|nmap|metasploit|password|crack|hashcat|hydra|aircrack|wireshark|tshark|sandbox|proot|chroot|docker|jail|firejail|strace|ltrace|gdb|radare2|frida/) {
        print pkg > catdir "/active_defense_sandboxes.txt"
        matched = 1
    }
    # Rule 5: UI/Material & Rendering Layers
    else if (combined ~ /icon|theme|font|fontconfig|menu|ncurses-utils|sensory|telemetry|sensor|audio|pulseaudio|alsa|wayland|x11|opengl|egl|gles|vulkan|mesa|harfbuzz|freetype|sdl|xwayland/) {
        print pkg > catdir "/material_sensory_ux.txt"
        matched = 1
    }
    # Rule 6: Systems Optimization & Admin
    else if (combined ~ /top|htop|btop|tmux|screen|iotop|sysstat|ncdu|rclone|rsync|git|curl|wget|neofetch|fastfetch|fzf|ripgrep|bat/ || section ~ /^(admin|utils|sysutils)$/) {
        print pkg > catdir "/optimization_admin_utility.txt"
        matched = 1
    }

    if (matched) {
        print pkg > target_file
        total_size += size
    }
}
END {
    print total_size > size_file
}
'

# --- 2. THE STORAGE SAFEGUARD CALCULATION ---
TOTAL_TARGETS=$(wc -l < "$TARGET_FILE")
PAYLOAD_KB=$(cat "$SIZE_FILE")
[ -z "$PAYLOAD_KB" ] && PAYLOAD_KB=0

PAYLOAD_MB=$(( PAYLOAD_KB / 1024 ))
ESTIMATED_TOTAL_MB=$(( PAYLOAD_MB + (PAYLOAD_MB / 3) )) # Add 33% overhead for dependencies
BUFFER_MB=32768 # 32 GB Buffer
REQUIRED_MB=$(( ESTIMATED_TOTAL_MB + BUFFER_MB ))
CURRENT_FREE_MB=$(df -m "$PREFIX" | awk 'NR==2 {print $4}')

log "[*] Universe scan complete. Identified $TOTAL_TARGETS hardware/compute targets."
log " -> Raw Package Footprint: ${PAYLOAD_MB} MB"
log " -> Expected Footprint (w/ dependencies): ${ESTIMATED_TOTAL_MB} MB"
log " -> Mandatory Safety Buffer: 32 GB"
log " -> Total Space Required: ${REQUIRED_MB} MB"
log " -> Current Free Space: ${CURRENT_FREE_MB} MB"

if [ "$CURRENT_FREE_MB" -lt "$REQUIRED_MB" ]; then
    log "FATAL: Insufficient hardware capacity for a full deployment."
    log "Aborting operation. We don't do half-measures."
    exit 1
fi
log "[*] Storage requirements met. Initiating full execution matrix."

# --- 3. BATCH DEPLOYMENT ---
while [ -s "$TARGET_FILE" ]; do
    round=$((round+1))
    REMAINING=$(wc -l < "$TARGET_FILE")
    log "=== TARGET ENFORCEMENT ROUND $round : $REMAINING targets remaining ==="

    dpkg --configure -a >"$LOGFILE" 2>&1
    apt-get --fix-broken install -y >"$LOGFILE" 2>&1

    mapfile -t pkgs < <(head -n "$BATCH_SIZE" "$TARGET_FILE")
    batch_install "${pkgs[@]}"

    if apt-get autoremove -y --dry-run 2>/dev/null | grep -q "^Remv"; then
        log "[*] Purging orphaned structures..."
        apt-get autoremove -y >"$LOGFILE" 2>&1
    fi
done

log "===================================================="
log "[*] HARDWARE-ACCELERATED STACK DEPLOYMENT COMPLETE"
log "===================================================="
