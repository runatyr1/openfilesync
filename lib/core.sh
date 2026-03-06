#!/usr/bin/env bash
# core.sh - shared functions: logging, config, locking, mappings

set -euo pipefail

CONFIG_DIR="${HOME}/.config/openfilesync"
DATA_DIR="${HOME}/.local/share/openfilesync"
CONFIG_FILE="${CONFIG_DIR}/openfilesync.conf"
MAPPINGS_FILE="${CONFIG_DIR}/mappings"
FILTERS_FILE="${DATA_DIR}/filters.combined"
LOG_FILE="${DATA_DIR}/openfilesync.log"
LOCK_FILE="${DATA_DIR}/lock"

# Defaults
DEFAULT_REMOTE=""
DEFAULT_SYNC_INTERVAL=1800
DEFAULT_CONFLICT_RESOLVE="newer"
DEFAULT_MAX_DELETE=10

ensure_dirs() {
    mkdir -p "$CONFIG_DIR" "$DATA_DIR"
}

# --- Logging ---

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[${timestamp}] [${level}] ${msg}"
    echo "$line" >> "$LOG_FILE"
    if [[ "$level" == "ERROR" ]]; then
        echo "$line" >&2
    else
        echo "$line"
    fi
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

trim_log() {
    [[ -f "$LOG_FILE" ]] || return 0
    local cutoff
    cutoff="$(date -d '15 days ago' '+%Y-%m-%d')"
    local tmp="${LOG_FILE}.tmp"
    awk -v cutoff="$cutoff" '
        match($0, /^\[([0-9]{4}-[0-9]{2}-[0-9]{2})/, m) {
            if (m[1] >= cutoff) print
            next
        }
        { print }
    ' "$LOG_FILE" > "$tmp" && mv "$tmp" "$LOG_FILE"
}

# --- Config ---

load_config() {
    REMOTE="${DEFAULT_REMOTE}"
    SYNC_INTERVAL="${DEFAULT_SYNC_INTERVAL}"
    CONFLICT_RESOLVE="${DEFAULT_CONFLICT_RESOLVE}"
    MAX_DELETE="${DEFAULT_MAX_DELETE}"

    if [[ -f "$CONFIG_FILE" ]]; then
        # Source only known variables (safe subset)
        while IFS='=' read -r key value; do
            key="$(echo "$key" | xargs)"
            value="$(echo "$value" | xargs)"
            [[ -z "$key" || "$key" == \#* ]] && continue
            case "$key" in
                REMOTE)           REMOTE="$value" ;;
                SYNC_INTERVAL)    SYNC_INTERVAL="$value" ;;
                CONFLICT_RESOLVE) CONFLICT_RESOLVE="$value" ;;
                MAX_DELETE)       MAX_DELETE="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi

    if [[ -z "$REMOTE" ]]; then
        log_error "No remote configured. Run 'openfilesync init' first."
        return 1
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# OpenFileSync configuration
REMOTE=${REMOTE}
SYNC_INTERVAL=${SYNC_INTERVAL}
CONFLICT_RESOLVE=${CONFLICT_RESOLVE}
MAX_DELETE=${MAX_DELETE}
EOF
}

# --- Mappings ---

load_mappings() {
    MAPPING_REMOTES=()
    MAPPING_LOCALS=()

    if [[ ! -f "$MAPPINGS_FILE" ]]; then
        log_error "No mappings found. Run 'ofs init' first."
        return 1
    fi

    while IFS='=' read -r remote_path local_path; do
        remote_path="$(echo "$remote_path" | xargs)"
        local_path="$(echo "$local_path" | xargs)"
        [[ -z "$remote_path" || "$remote_path" == \#* ]] && continue
        # Strip trailing slashes
        remote_path="${remote_path%/}"
        local_path="${local_path%/}"
        MAPPING_REMOTES+=("$remote_path")
        MAPPING_LOCALS+=("$local_path")
    done < "$MAPPINGS_FILE"

    if [[ ${#MAPPING_REMOTES[@]} -eq 0 ]]; then
        log_error "No mappings defined in ${MAPPINGS_FILE}"
        return 1
    fi
}

save_mappings() {
    {
        echo "# OpenFileSync path mappings"
        echo "# Format: remote_path = local_path"
        for i in "${!MAPPING_REMOTES[@]}"; do
            echo "${MAPPING_REMOTES[$i]} = ${MAPPING_LOCALS[$i]}"
        done
    } > "$MAPPINGS_FILE"
}

# --- Locking ---

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
        if [[ $lock_age -gt 120 ]]; then
            log_warn "Stale lock file (${lock_age}s old), removing."
            rm -f "$LOCK_FILE"
        else
            log_error "Another sync is running (lock age: ${lock_age}s). Exiting."
            return 1
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}
