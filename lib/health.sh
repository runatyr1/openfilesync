#!/usr/bin/env bash
# health.sh - conflict detection and status reporting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

show_status() {
    ensure_dirs
    load_config
    load_mappings

    echo "OpenFileSync Status"
    echo "==================="
    echo "Remote: ${REMOTE}"
    echo "Mappings: ${#MAPPING_REMOTES[@]}"
    echo ""

    for i in "${!MAPPING_REMOTES[@]}"; do
        echo "  ${MAPPING_LOCALS[$i]} <-> ${REMOTE}:${MAPPING_REMOTES[$i]}"
    done

    echo ""

    # Last sync time from log
    if [[ -f "$LOG_FILE" ]]; then
        local last_sync
        last_sync="$(grep -E '\[INFO\] (Sync finished|All mappings synced|Completed:)' "$LOG_FILE" | tail -1 || true)"
        if [[ -n "$last_sync" ]]; then
            echo "Last sync: ${last_sync}"
        else
            echo "Last sync: no successful sync found in log"
        fi
    else
        echo "Last sync: no log file yet"
    fi

    # Conflict count
    local conflict_count=0
    for i in "${!MAPPING_LOCALS[@]}"; do
        local local_path="${MAPPING_LOCALS[$i]}"
        [[ -d "$local_path" ]] || continue
        local count
        count="$(find "$local_path" -name '*.conflict*' 2>/dev/null | wc -l)"
        conflict_count=$((conflict_count + count))
    done

    if [[ $conflict_count -gt 0 ]]; then
        echo "Conflicts: ${conflict_count} file(s) - run 'openfilesync conflicts' for details"
    else
        echo "Conflicts: none"
    fi
}

list_conflicts() {
    ensure_dirs
    load_config
    load_mappings

    local found=0

    for i in "${!MAPPING_LOCALS[@]}"; do
        local local_path="${MAPPING_LOCALS[$i]}"
        [[ -d "$local_path" ]] || continue

        while IFS= read -r file; do
            [[ -n "$file" ]] || continue
            echo "$file"
            found=$((found + 1))
        done < <(find "$local_path" -name '*.conflict*' 2>/dev/null)
    done

    if [[ $found -eq 0 ]]; then
        echo "No conflicts found."
    else
        echo ""
        echo "${found} conflict file(s) found."
    fi
}
