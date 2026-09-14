#!/data/data/com.termux/files/usr/bin/bash
# ius_ultimate.sh - Ultimate Domain-Specific Mass-Installer & Orchestrator
# Targets: LLM/Agents, Multi-lang Compilers, Quantum/Science, Active Defense/Sandboxes, UX Material/Sensory, Admin/Utility

LOGFILE="$HOME/ius_ultimate_$(date +%s).log"
CATDIR="$HOME/ius_categories"
mkdir -p "$CATDIR"

# Domain-specific category text files
CATEGORIES=(
    "llm_agents_servers"
    "compilers_runtimes"
    "quantum_science_simulators"
    "active_defense_sandboxes"
    "material_sensory_ux"
    "optimization_admin_utility"
)

# Initialize files
for cat in "${CATEGORIES[@]}"; do
    : > "$CATDIR/$cat.txt"
done
: > "$HOME/failed_pkgs.txt"

# Orchestration parameters
BATCH_SIZE=15
MAX_BATCH_SIZE=50
MIN_BATCH_SIZE=1
round=0
CORE_PKGS="apt dpkg bash coreutils termux-tools dash grep sed awk ncurses"

log() {
    echo -e "\033[1;32m[$(date '+%Y-%m-%d %H:%M:%S')]\033[0m $*" | tee -a "$LOGFILE"
}

is_core_pkg() {
    echo "$CORE_PKGS" | grep -qw "$1"
}

rdep_count() {
    apt-cache rdepends --installed "$1" 2>/dev/null | tail -n +3 | grep -vc '^$'
}

resolve_conflict() {
    local newpkg="$1" oldpkg="$2"
    if is_core_pkg "$oldpkg"; then
        log "CRITICAL: $newpkg conflicts with core package $oldpkg. Skipping."
        echo "$newpkg : conflict with core $oldpkg" >> "$HOME/failed_pkgs.txt"
        return 1
    fi

    local new_score old_score
    new_score=$(rdep_count "$newpkg")
    old_score=$(rdep_count "$oldpkg")

    log "Conflict: $newpkg (rdeps=$new_score) vs $oldpkg (rdeps=$old_score)"
    if [ "$new_score" -gt "$old_score" ]; then
        log "Removing $oldpkg in favor of $newpkg"
        apt-get remove -y "$oldpkg" >>"$LOGFILE" 2>&1
        apt-get install -y "$newpkg" >>"$LOGFILE" 2>&1
        return 0
    else
        log "Keeping $oldpkg, skipping $newpkg"
        echo "$newpkg : conflict with $oldpkg (skipped)" >> "$HOME/failed_pkgs.txt"
        return 1
    fi
}

evaluate_and_route() {
    local pkg="$1"
    local meta section desc name_lc combined

    meta=$(apt-cache show "$pkg" 2>/dev/null)
    [ -z "$meta" ] && return 1 # Package doesn't exist or is unavailable

    section=$(echo "$meta" | awk '/^Section:/ {print $2; exit}')
    desc=$(echo "$meta" | awk '/^Description/ {print; exit}' | tr '[:upper:]' '[:lower:]')
    name_lc="${pkg,,}"
    combined="$name_lc $desc $section"

    # Rule 1: LLM, AI Agents, Local Model Servers
    if [[ "$combined" =~ llm|llama|ollama|pytorch|tensorflow|huggingface|transformer|inference|agent|gpt|langchain|onnx|openblas ]]; then
        echo "$pkg" >> "$CATDIR/llm_agents_servers.txt"
        return 0
    fi

    # Rule 2: Advanced Compilers and Cross-Platform Runtimes
    if [[ "$section" =~ ^(devel|libdevel|interpreters|haskell|python|golang|rust|java|ruby)$ ]] || \
       [[ "$combined" =~ compiler|clang|gcc|llvm|make|cmake|nodejs|openjdk|python|golang|rustc|elixir|lua|perl|php|nim|zig|fortran ]]; then
        echo "$pkg" >> "$CATDIR/compilers_runtimes.txt"
        return 0
    fi

    # Rule 3: Quantum, Computations, Physical Simulators & Science
    if [[ "$section" =~ ^(science|math)$ ]] || \
       [[ "$combined" =~ quantum|physics|simulation|matrix|lapack|numpy|scipy|octave|gnuplot|fft|graphviz|calc ]]; then
        echo "$pkg" >> "$CATDIR/quantum_science_simulators.txt"
        return 0
    fi

    # Rule 4: Active Defense, Security Evaluation, Cracking, Sandboxes & Virtualization
    if [[ "$combined" =~ exploit|pentest|nmap|metasploit|password|crack|hashcat|hydra|aircrack|wireshark|tshark|sandbox|proot|chroot|docker|jail|firejail|strace|ltrace|gdb|radare2|frida ]]; then
        echo "$pkg" >> "$CATDIR/active_defense_sandboxes.txt"
        return 0
    fi

    # Rule 5: UI/Material, Icons, Audio/Sensory Engines, Telemetry, Graphic Buffers & Custom Headers
    if [[ "$combined" =~ icon|theme|font|fontconfig|menu|ncurses-utils|sensory|telemetry|sensor|audio|pulseaudio|alsa|wayland|x11|opengl|vulkan|mesa|harfbuzz|freetype|sdl ]]; then
        echo "$pkg" >> "$CATDIR/material_sensory_ux.txt"
        return 0
    fi

    # Rule 6: Systems Optimization, Administration, Visualization & Advanced Utilities
    if [[ "$section" =~ ^(admin|utils|sysutils)$ ]] || \
       [[ "$combined" =~ top|htop|btop|tmux|screen|iotop|sysstat|ncdu|rclone|rsync|git|curl|wget|neofetch|fastfetch|fzf|ripgrep|bat ]]; then
        echo "$pkg" >> "$CATDIR/optimization_admin_utility.txt"
        return 0
    fi

    return 1 # Doesn't fit the curated profile
}

batch_install() {
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return

    log "Deploying batch of ${#pkgs[@]} items... (Current Batch Step Size: $BATCH_SIZE)"
    printf "%s\n" "${pkgs[@]}" > "$HOME/current_batch.tmp"

    if errlog=$(apt-get install -y --allow-downgrades --allow-change-held-packages "${pkgs[@]}" 2>&1); then
        # SUCCESS: Scale up batch window dynamically
        echo "$errlog" >> "$LOGFILE"
        BATCH_SIZE=$(( BATCH_SIZE + 3 ))
        [ $BATCH_SIZE -gt $MAX_BATCH_SIZE ] && BATCH_SIZE=$MAX_BATCH_SIZE

        grep -Fv -f "$HOME/current_batch.tmp" "$HOME/targeted_pkgs.txt" > "$HOME/targeted_pkgs.tmp"
        mv "$HOME/targeted_pkgs.tmp" "$HOME/targeted_pkgs.txt"
        return
    fi

    # FAILURE: Scale down batch window, switch to discrete error handling
    echo "$errlog" >> "$LOGFILE"
    BATCH_SIZE=$(( BATCH_SIZE / 2 ))
    [ $BATCH_SIZE -lt $MIN_BATCH_SIZE ] && BATCH_SIZE=$MIN_BATCH_SIZE

    log "Batch collision detected. Initiating narrow isolation matrix..."
    for pkg in "${pkgs[@]}"; do
        if single_err=$(apt-get install -y --allow-downgrades --allow-change-held-packages "$pkg" 2>&1); then
            grep -vx "$pkg" "$HOME/targeted_pkgs.txt" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$HOME/targeted_pkgs.txt"
            continue
        fi

        echo "$single_err" >> "$LOGFILE"
        if echo "$single_err" | grep -qiE "conflicts with|trying to overwrite|Breaks:"; then
            conflicting=$(echo "$single_err" | grep -oP '(?<=but )\S+(?=is)' | head -1)
            [ -z "$conflicting" ] && conflicting=$(apt-get install -s "$pkg" 2>&1 | grep -oP "(?<=Conflicts: )\S+" | head -1)

            if [ -n "$conflicting" ] && resolve_conflict "$pkg" "$conflicting"; then
                grep -vx "$pkg" "$HOME/targeted_pkgs.txt" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$HOME/targeted_pkgs.txt"
            fi
        else
            echo "$pkg : install failed" >> "$HOME/failed_pkgs.txt"
            grep -vx "$pkg" "$HOME/targeted_pkgs.txt" > "$HOME/targeted_pkgs.tmp" && mv "$HOME/targeted_pkgs.tmp" "$HOME/targeted_pkgs.txt"
        fi
    done
}

# --- MAIN EXECUTION MATRIX ---
log "[*] Syncing remote Termux repository indexes..."
apt-get update 2>&1 | tee -a "$LOGFILE"

log "[*] Scanning repository metadata universe for curated target vectors..."
: > "$HOME/targeted_pkgs.txt"

# Get all names, then parse them through our classification pipeline
all_raw_pkgs=$(apt-cache pkgnames | sort -u)

for pkg in $all_raw_pkgs; do
    if evaluate_and_route "$pkg"; then
        echo "$pkg" >> "$HOME/targeted_pkgs.txt"
    fi
done

TOTAL_TARGETS=$(wc -l < "$HOME/targeted_pkgs.txt")
log "[*] Universe scan complete. Identified $TOTAL_TARGETS highly relevant packages matching your parameters."

while [ -s "$HOME/targeted_pkgs.txt" ]; do
    round=$((round+1))
    REMAINING=$(wc -l < "$HOME/targeted_pkgs.txt")
    log "=== TARGET ENFORCEMENT ROUND $round : $REMAINING targets remaining ==="

    dpkg --configure -a >>"$LOGFILE" 2>&1
    apt-get --fix-broken install -y >>"$LOGFILE" 2>&1

    mapfile -t pkgs < <(head -n "$BATCH_SIZE" "$HOME/targeted_pkgs.txt")
    batch_install "${pkgs[@]}"

    if apt-get autoremove -y --dry-run 2>/dev/null | grep -q "^Remv"; then
        log "[*] Purging orphaned structures..."
        apt-get autoremove -y >>"$LOGFILE" 2>&1
    fi
done

log "===================================================="
log "[*] SPECIFIED STACK DEPLOYMENT COMPLETE"
log "===================================================="
for cat in "${CATEGORIES[@]}"; do
    log " -> ${cat}: $(wc -l < "$CATDIR/${cat}.txt") structures deployed."
done
log "[*] Reference system logs written to $LOGFILE"
