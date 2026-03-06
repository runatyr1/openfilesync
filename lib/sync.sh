#!/usr/bin/env bash
# sync.sh - rclone bisync wrapper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

run_sync() {
    local dry_run="${1:-false}"
    local resync="${2:-false}"

    ensure_dirs
    trim_log
    load_config
    load_mappings

    acquire_lock
    trap release_lock EXIT

    local failed=0
    local total=${#MAPPING_REMOTES[@]}

    for i in "${!MAPPING_REMOTES[@]}"; do
        local remote_path="${MAPPING_REMOTES[$i]}"
        local local_path="${MAPPING_LOCALS[$i]}"
        local remote_full="${REMOTE}:${remote_path}"

        if [[ ! -e "$local_path" ]]; then
            log_warn "Local path does not exist, skipping: ${local_path}"
            continue
        fi

        log_info "Syncing: ${local_path} <-> ${remote_full}"

        local cmd=(
            rclone bisync
            "$local_path" "$remote_full"
            --resilient --recover --max-lock 2m
            --conflict-resolve "$CONFLICT_RESOLVE"
            --conflict-loser num
            --compare size,modtime
            --max-delete "$MAX_DELETE"
            --check-access
            --create-empty-src-dirs
            -v
        )

        if [[ -f "$FILTERS_FILE" ]]; then
            cmd+=(--filters-file "$FILTERS_FILE")
        fi

        if [[ "$resync" == "true" ]]; then
            cmd+=(--resync)
        fi

        if [[ "$dry_run" == "true" ]]; then
            cmd+=(--dry-run)
        fi

        if "${cmd[@]}" >> "$LOG_FILE" 2>&1; then
            log_info "Completed: ${local_path}"
        else
            log_error "Failed: ${local_path}"
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_error "Sync finished with ${failed}/${total} failures."
        return 1
    else
        log_info "Sync finished successfully (${total} mappings)."
    fi
}
