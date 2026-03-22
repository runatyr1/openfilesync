#!/usr/bin/env bash
# sync.sh - rclone bisync wrapper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

cleanup_empty_dirs() {
    local local_path="$1"
    local remote_full="$2"

    log_info "Cleaning empty directories..."

    # Remote
    local remote_output
    remote_output="$(rclone rmdirs "${remote_full}" --leave-root -v 2>&1)"
    if [[ -n "$remote_output" ]]; then
        echo "$remote_output" | tee -a "$LOG_FILE"
    else
        log_info "No empty remote directories to clean."
    fi

    # Local (skip filtered directories — they're not synced, their structure must be preserved)
    local local_output
    local_output="$(find "$local_path" -mindepth 1 \
        -not -path '*/.git/*' -not -name '.git' \
        -not -path '*/node_modules/*' -not -name 'node_modules' \
        -not -path '*/.gradle/*' -not -name '.gradle' \
        -not -path '*/.cache/*' -not -name '.cache' \
        -not -path '*/.cxx/*' -not -name '.cxx' \
        -not -path '*/CMakeFiles/*' -not -name 'CMakeFiles' \
        -not -path '*/.idea/*' -not -name '.idea' \
        -not -path '*/ios/Pods/*' \
        -type d -empty -delete -print 2>&1)"
    if [[ -n "$local_output" ]]; then
        echo "$local_output" | tee -a "$LOG_FILE"
        log_info "Cleaned local empty directories."
    else
        log_info "No empty local directories to clean."
    fi
}

refresh_check_files() {
    local check_file="RCLONE_TEST"
    local cache_dir="${HOME}/.cache/rclone/bisync"

    # Remove all RCLONE_TEST entries from bisync listing cache
    for lst_file in "${cache_dir}"/*.lst*; do
        [[ -f "$lst_file" ]] || continue
        if grep -q "RCLONE_TEST" "$lst_file" 2>/dev/null; then
            sed -i '/RCLONE_TEST/d' "$lst_file"
        fi
    done

    # Delete all stale RCLONE_TEST files locally and on remote
    for i in "${!MAPPING_REMOTES[@]}"; do
        local remote_path="${MAPPING_REMOTES[$i]}"
        local local_path="${MAPPING_LOCALS[$i]}"
        local remote_full="${REMOTE}:${remote_path}"

        # Remove any RCLONE_TEST files in subdirs locally
        find "$local_path" -name "$check_file" -type f -delete 2>/dev/null || true

        # Recreate only at mapping root
        touch "${local_path}/${check_file}"
        rclone touch "${remote_full}/${check_file}" 2>/dev/null || true
    done

    log_info "Check files refreshed for ${#MAPPING_REMOTES[@]} mapping(s)."
}

run_sync() {
    local dry_run="${1:-false}"
    local resync="${2:-false}"
    local force="${3:-false}"

    ensure_dirs
    trim_log
    load_config
    load_mappings

    acquire_lock
    trap release_lock EXIT

    # Refresh RCLONE_TEST files: remove all from cache, recreate only for current mappings
    refresh_check_files

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

        if [[ "$force" == "true" ]]; then
            cmd+=(--force)
        fi

        log_info "Command: ${cmd[*]}"

        # Stream output to both screen and log file, capture for error detection
        local sync_output
        sync_output="$(mktemp)"
        if "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE" "$sync_output"; then
            cleanup_empty_dirs "$local_path" "$remote_full"
            log_info "Completed: ${local_path}"
        else
            local exit_code=${PIPESTATUS[0]}
            # Don't auto-resync on max-delete safety abort — that would restore deleted files
            if grep -q "too many deletes" "$sync_output" 2>/dev/null; then
                log_error "Too many deletes for: ${local_path}. Run 'ofs sync --force' to allow."
            elif [[ "$resync" != "true" ]]; then
                log_info "Sync failed (exit code: ${exit_code}), retrying with --resync for: ${local_path}"
                cmd+=(--resync)
                if "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                    cleanup_empty_dirs "$local_path" "$remote_full"
                    log_info "Completed (resync): ${local_path}"
                    rm -f "$sync_output"
                    continue
                fi
                exit_code=${PIPESTATUS[0]}
            fi
            log_error "Failed: ${local_path} (exit code: ${exit_code})"
            ((failed++))
        fi
        rm -f "$sync_output"
    done

    release_lock
    if [[ $failed -gt 0 ]]; then
        log_error "Sync finished with ${failed}/${total} failures."
        return 1
    else
        log_info "Sync finished successfully (${total} mappings)."
    fi
}
