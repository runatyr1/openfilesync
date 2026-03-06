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
            log_info "Local path does not exist, creating: ${local_path}"
            mkdir -p "$local_path"
        fi

        # Ensure RCLONE_TEST check files exist on both sides
        local check_file="RCLONE_TEST"
        if [[ ! -f "${local_path}/${check_file}" ]]; then
            touch "${local_path}/${check_file}"
            log_info "Created check file: ${local_path}/${check_file}"
        fi
        # Create on remote if missing (ignore errors if it already exists)
        if ! rclone lsf "${remote_full}/${check_file}" &>/dev/null; then
            rclone touch "${remote_full}/${check_file}" 2>/dev/null || true
            log_info "Created check file on remote: ${remote_full}/${check_file}"
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

        log_info "Command: ${cmd[*]}"

        local output
        if output="$("${cmd[@]}" 2>&1)"; then
            echo "$output" >> "$LOG_FILE"
            log_info "Completed: ${local_path}"
        else
            local exit_code=$?
            echo "$output" >> "$LOG_FILE"
            # Log the rclone error lines for quick diagnosis
            local errors
            errors="$(echo "$output" | grep -i 'ERROR\|NOTICE.*Failed\|fatal' | head -5)"
            log_error "Failed: ${local_path} (exit code: ${exit_code})"
            if [[ -n "$errors" ]]; then
                while IFS= read -r line; do
                    log_error "  ${line}"
                done <<< "$errors"
            fi
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
