#!/usr/bin/env bash
# =============================================================================
# backup.sh
# Task 2 – Compress a directory and upload to a remote server via SCP
# ID616001 Operating Systems Concepts – Assignment 1, Semester 1 2026
#
# Usage:
#   ./backup.sh [DIRECTORY_PATH]
#
# If no argument is supplied the script will interactively prompt for one.
# =============================================================================

# ---------------------------------------------------------------------------
# 0. GLOBALS
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/backup_$(date '+%Y%m%d_%H%M%S').log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------------------------------------------------------------------------
# 1. LOGGING HELPERS
# ---------------------------------------------------------------------------
log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" >> "$LOG_FILE"; }
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; log_msg "INFO"  "$*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; log_msg "WARN"  "$*"; }
error() { echo -e "${RED}[ERROR]${NC} $*";    log_msg "ERROR" "$*"; }

# ---------------------------------------------------------------------------
# 2. DEPENDENCY CHECK
# ---------------------------------------------------------------------------
check_dependencies() {
    local deps=(tar gzip scp ssh)
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# 3. INPUT – DIRECTORY
# ---------------------------------------------------------------------------
get_directory() {
    local dir=""

    if [[ -n "$1" ]]; then
        dir="$1"
    else
        echo -e "${CYAN}No directory supplied.${NC}"
        read -rp "Enter the path to the directory you want to back up: " dir
    fi

    dir="${dir%/}"   # remove trailing slash

    if [[ -z "$dir" ]]; then
        error "No directory provided. Exiting."
        exit 1
    fi

    if [[ ! -d "$dir" ]]; then
        error "Directory does not exist: $dir"
        exit 1
    fi

    if [[ ! -r "$dir" ]]; then
        error "Directory is not readable: $dir"
        exit 1
    fi

    echo "$dir"
}

# ---------------------------------------------------------------------------
# 4. INPUT – REMOTE DETAILS (interactive prompts)
# ---------------------------------------------------------------------------
get_remote_details() {
    echo ""
    echo -e "${CYAN}Remote server details${NC}"
    echo "─────────────────────"

    read -rp "Remote server IP or hostname: " REMOTE_HOST
    REMOTE_HOST="${REMOTE_HOST// /}"
    if [[ -z "$REMOTE_HOST" ]]; then
        error "No remote host provided."
        exit 1
    fi

    read -rp "SSH port [default: 22]: " REMOTE_PORT
    REMOTE_PORT="${REMOTE_PORT// /}"
    REMOTE_PORT="${REMOTE_PORT:-22}"
    if ! [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] || (( REMOTE_PORT < 1 || REMOTE_PORT > 65535 )); then
        error "Invalid port number: $REMOTE_PORT"
        exit 1
    fi

    read -rp "Remote username: " REMOTE_USER
    REMOTE_USER="${REMOTE_USER// /}"
    if [[ -z "$REMOTE_USER" ]]; then
        error "No remote username provided."
        exit 1
    fi

    read -rp "Target directory on remote server: " REMOTE_DIR
    REMOTE_DIR="${REMOTE_DIR// /}"
    if [[ -z "$REMOTE_DIR" ]]; then
        error "No remote directory provided."
        exit 1
    fi

    # Export so they are accessible in the calling scope
    export REMOTE_HOST REMOTE_PORT REMOTE_USER REMOTE_DIR
}

# ---------------------------------------------------------------------------
# 5. REACHABILITY CHECK
# ---------------------------------------------------------------------------
check_remote_reachable() {
    info "Checking connectivity to ${REMOTE_HOST}:${REMOTE_PORT} …"
    if ! ssh -o BatchMode=yes \
             -o ConnectTimeout=10 \
             -o StrictHostKeyChecking=accept-new \
             -p "$REMOTE_PORT" \
             "${REMOTE_USER}@${REMOTE_HOST}" \
             "exit" 2>>"$LOG_FILE"; then
        error "Cannot connect to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}."
        error "Check the hostname, port, username, and SSH key / password."
        exit 1
    fi
    info "Connection successful."
}

# ---------------------------------------------------------------------------
# 6. CREATE TARBALL
# ---------------------------------------------------------------------------
create_tarball() {
    local src_dir="$1"
    local archive_name
    archive_name="${SCRIPT_DIR}/$(basename "$src_dir").tar.gz"

    info "Creating archive: $archive_name"
    log_msg "INFO" "Archiving '$src_dir' → '$archive_name'"

    if tar -czf "$archive_name" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" 2>>"$LOG_FILE"; then
        info "Archive created successfully ($(du -sh "$archive_name" | cut -f1))."
        log_msg "INFO" "Archive size: $(du -sh "$archive_name" | cut -f1)"
    else
        error "Failed to create archive for '$src_dir'."
        exit 1
    fi

    echo "$archive_name"
}

# ---------------------------------------------------------------------------
# 7. UPLOAD VIA SCP
# ---------------------------------------------------------------------------
upload_archive() {
    local archive="$1"

    info "Uploading $archive to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR} …"
    log_msg "INFO" "SCP upload starting: $archive → ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"

    if scp -P "$REMOTE_PORT" \
           -o ConnectTimeout=30 \
           -o StrictHostKeyChecking=accept-new \
           "$archive" \
           "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}" 2>>"$LOG_FILE"; then
        info "Upload successful."
        log_msg "SUCCESS" "Upload complete: $(basename "$archive") → ${REMOTE_HOST}:${REMOTE_DIR}"
    else
        error "Upload failed. Check network, credentials, and remote directory permissions."
        log_msg "FAIL" "SCP upload failed for $archive"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# 8. CLEANUP
# ---------------------------------------------------------------------------
cleanup() {
    # Optionally remove the local tarball after a successful upload
    # Commented out by default – uncomment if you want automatic cleanup
    # [[ -f "$ARCHIVE_PATH" ]] && rm -f "$ARCHIVE_PATH" && info "Removed local archive."
    :
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 9. MAIN
# ---------------------------------------------------------------------------
main() {
    log_msg "INFO" "Script started. PID=$$. User=$(whoami). Args: $*"

    check_dependencies

    local src_dir
    src_dir=$(get_directory "$1")
    info "Backup source: $src_dir"

    get_remote_details

    check_remote_reachable

    local archive
    archive=$(create_tarball "$src_dir")
    ARCHIVE_PATH="$archive"   # expose to cleanup trap

    upload_archive "$archive"

    echo ""
    info "Backup complete. Log: $LOG_FILE"
}

main "$@"
