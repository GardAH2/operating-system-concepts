#!/usr/bin/env bash
# =============================================================================
# create_users.sh
# Task 1 – Automate user creation and environment configuration
# ID616001 Operating Systems Concepts – Assignment 1, Semester 1 2026
#
# Usage:
#   sudo ./create_users.sh [CSV_PATH_OR_URL]
#
# If no argument is supplied the script will interactively prompt for one.
# =============================================================================

# ---------------------------------------------------------------------------
# 0. GLOBALS & LOG SETUP
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/create_users_$(date '+%Y%m%d_%H%M%S').log"
DOWNLOADED_CSV=""   # track any downloaded file so we can clean up

# Colour helpers (stdout only – log file stays plain)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------------------------------------------------------------------------
# 1. LOGGING HELPERS
# ---------------------------------------------------------------------------

# log_msg LEVEL message  – writes to log file with timestamp
log_msg() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >> "$LOG_FILE"
}

# info / warn / error – console + log
info()  { echo -e "${GREEN}[INFO]${NC}  $*";  log_msg "INFO"  "$*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; log_msg "WARN"  "$*"; }
error() { echo -e "${RED}[ERROR]${NC} $*";    log_msg "ERROR" "$*"; }

# detail – log-only (verbose detail not needed on console)
detail() { log_msg "DETAIL" "$*"; }

# ---------------------------------------------------------------------------
# 2. PRE-FLIGHT CHECKS
# ---------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)."
        exit 1
    fi
}

check_dependencies() {
    # Tools this script relies on
    local deps=(curl wget useradd groupadd chage usermod chown chmod ln)
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
# 3. INPUT HANDLING
# ---------------------------------------------------------------------------

# is_url STR – returns 0 if STR looks like a http/https URL
is_url() { [[ "$1" =~ ^https?:// ]]; }

# download_csv URL – downloads to SCRIPT_DIR, sets DOWNLOADED_CSV
download_csv() {
    local url="$1"
    local filename
    filename="${SCRIPT_DIR}/$(basename "$url")"

    info "Downloading CSV from: $url"
    if curl -fsSL "$url" -o "$filename" 2>>"$LOG_FILE"; then
        detail "Download succeeded → $filename"
        DOWNLOADED_CSV="$filename"
        echo "$filename"
    else
        error "Failed to download file from $url"
        exit 1
    fi
}

# validate_csv FILE – basic existence + header check
validate_csv() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        exit 1
    fi
    if [[ ! -s "$file" ]]; then
        error "File is empty: $file"
        exit 1
    fi
    # Check the file has at least the expected header columns
    local header
    header=$(head -1 "$file")
    if ! echo "$header" | grep -qi "e-mail"; then
        error "File does not appear to be a valid users CSV (missing 'e-mail' header): $file"
        exit 1
    fi
    detail "CSV validation passed for $file"
}

# resolve_input INPUT – returns a local validated CSV path
resolve_input() {
    local input="$1"
    local csv_path

    if is_url "$input"; then
        csv_path=$(download_csv "$input")
    else
        csv_path="$input"
    fi

    validate_csv "$csv_path"
    echo "$csv_path"
}

# get_input – obtain source either from arg or interactive prompt
get_input() {
    local source=""

    if [[ -n "$1" ]]; then
        source="$1"
    else
        echo ""
        echo -e "${CYAN}No input file specified.${NC}"
        echo "Please enter a local file path or a URL to a CSV file:"
        read -rp "> " source
        source="${source// /}"   # strip accidental spaces
    fi

    if [[ -z "$source" ]]; then
        error "No input provided. Exiting."
        exit 1
    fi

    resolve_input "$source"
}

# ---------------------------------------------------------------------------
# 4. USERNAME / PASSWORD GENERATION
# ---------------------------------------------------------------------------

# generate_username EMAIL → e.g. linus.torvalds@linux.org → tLinus
generate_username() {
    local email="$1"
    local local_part="${email%%@*}"          # linus.torvalds
    local first="${local_part%%.*}"          # linus
    local last="${local_part##*.}"           # torvalds

    # First letter of surname (lowercase) + full first name capitalised
    local first_cap
    first_cap="$(tr '[:lower:]' '[:upper:]' <<< "${first:0:1}")${first:1}"
    local last_initial
    last_initial="$(tr '[:upper:]' '[:lower:]' <<< "${last:0:1}")"

    echo "${last_initial}${first_cap}"
}

# generate_password BIRTHDATE → YYYYMM  (birthdate format: YYYY/MM/DD)
generate_password() {
    local birthdate="$1"
    # Use parameter expansion – no subprocess needed
    local year="${birthdate:0:4}"
    local month="${birthdate:5:2}"
    echo "${year}${month}"
}

# ---------------------------------------------------------------------------
# 5. GROUP HELPERS
# ---------------------------------------------------------------------------

# ensure_group GROUP – create group if it does not exist
ensure_group() {
    local group="$1"
    if getent group "$group" &>/dev/null; then
        detail "Group '$group' already exists – skipping creation."
    else
        if groupadd "$group" 2>>"$LOG_FILE"; then
            detail "Created group '$group'."
        else
            warn "Failed to create group '$group'."
            return 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# 6. SHARED FOLDER HELPERS
# ---------------------------------------------------------------------------

# ensure_shared_folder PATH GROUP – create folder + group + set permissions
ensure_shared_folder() {
    local folder="$1"
    local group="$2"

    # Create the folder if needed
    if [[ ! -d "$folder" ]]; then
        if mkdir -p "$folder" 2>>"$LOG_FILE"; then
            detail "Created shared folder '$folder'."
        else
            warn "Failed to create shared folder '$folder'."
            return 1
        fi
    else
        detail "Shared folder '$folder' already exists."
    fi

    # Ensure the associated group exists
    ensure_group "$group" || return 1

    # Set ownership and permissions
    # Owner = root (or script runner), group = shared-folder group
    # Permissions: rwxrws--- (setgid bit so new files inherit group)
    chown root:"$group" "$folder" 2>>"$LOG_FILE"
    chmod 2770 "$folder" 2>>"$LOG_FILE"
    detail "Set permissions 2770 on '$folder' with group '$group'."
}

# derive_folder_group FOLDER_PATH – e.g. /staffData → staffData_grp
derive_folder_group() {
    local folder="$1"
    local base
    base="$(basename "$folder")"
    echo "${base}_grp"
}

# ---------------------------------------------------------------------------
# 7. ALIAS HELPER
# ---------------------------------------------------------------------------

# create_sudo_alias HOME_DIR USERNAME
# Creates the 'myls' alias in ~/.bash_aliases for sudo users
create_sudo_alias() {
    local home_dir="$1"
    local username="$2"
    local alias_file="${home_dir}/.bash_aliases"
    local alias_line="alias myls='ls -la \${HOME}'"

    # Append only if alias not already present
    if grep -qF "alias myls=" "$alias_file" 2>/dev/null; then
        detail "Alias 'myls' already exists in $alias_file – skipping."
        return 0
    fi

    if echo "$alias_line" >> "$alias_file" 2>>"$LOG_FILE"; then
        chown "$username":"$username" "$alias_file" 2>>"$LOG_FILE"
        # Ensure .bashrc sources .bash_aliases (standard Ubuntu behaviour, but be safe)
        local bashrc="${home_dir}/.bashrc"
        if ! grep -q '\.bash_aliases' "$bashrc" 2>/dev/null; then
            {
                echo ""
                echo "# Source aliases"
                echo "if [ -f ~/.bash_aliases ]; then . ~/.bash_aliases; fi"
            } >> "$bashrc"
            chown "$username":"$username" "$bashrc" 2>>"$LOG_FILE"
        fi
        detail "Created alias 'myls' in $alias_file"
    else
        warn "Failed to write alias for user '$username'."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# 8. CORE USER-CREATION FUNCTION
# ---------------------------------------------------------------------------

create_user() {
    # Arguments come from parsed CSV columns
    local email="$1"
    local birthdate="$2"
    local secondary_groups="$3"   # comma-separated, may be empty
    local shared_folder="$4"      # absolute path, may be empty

    local username password home_dir

    username=$(generate_username "$email")
    password=$(generate_password "$birthdate")
    home_dir="/home/${username}"

    echo ""
    echo -e "${CYAN}──────────────────────────────────────${NC}"
    info "Processing user: $email  →  $username"

    # ── 8a. Skip if user already exists ──────────────────────────────────
    if id "$username" &>/dev/null; then
        warn "Username '$username' already exists – skipping."
        log_msg "SKIP" "User '$username' ($email) already exists."
        return 0
    fi

    # ── 8b. Ensure secondary groups exist before creating user ────────────
    local groups_to_add=()
    local is_sudo=false

    if [[ -n "$secondary_groups" ]]; then
        IFS=',' read -ra grp_array <<< "$secondary_groups"
        for grp in "${grp_array[@]}"; do
            grp="${grp// /}"   # trim spaces
            [[ -z "$grp" ]] && continue
            ensure_group "$grp" && groups_to_add+=("$grp")
            [[ "$grp" == "sudo" ]] && is_sudo=true
        done
    fi

    # If there is a shared folder, derive + ensure its group
    local folder_group=""
    if [[ -n "$shared_folder" ]]; then
        folder_group=$(derive_folder_group "$shared_folder")
        ensure_shared_folder "$shared_folder" "$folder_group"
        groups_to_add+=("$folder_group")
    fi

    # ── 8c. Create the user ───────────────────────────────────────────────
    local useradd_args=(-m -d "$home_dir" -s /bin/bash)

    # Build supplementary groups string for useradd
    if [[ ${#groups_to_add[@]} -gt 0 ]]; then
        local groups_str
        groups_str=$(IFS=','; echo "${groups_to_add[*]}")
        useradd_args+=(-G "$groups_str")
    fi

    if useradd "${useradd_args[@]}" "$username" 2>>"$LOG_FILE"; then
        detail "useradd succeeded for '$username'."
    else
        error "useradd failed for '$username' ($email). Check log for details."
        log_msg "FAIL" "useradd failed for '$username'."
        return 1
    fi

    # ── 8d. Set password ──────────────────────────────────────────────────
    if echo "${username}:${password}" | chpasswd 2>>"$LOG_FILE"; then
        detail "Password set for '$username'."
    else
        error "Failed to set password for '$username'."
    fi

    # Force password change on first login
    if chage -d 0 "$username" 2>>"$LOG_FILE"; then
        detail "Password expiry set (first-login change required) for '$username'."
    else
        warn "Failed to enforce password change at first login for '$username'."
    fi

    # ── 8e. Symbolic link to shared folder ───────────────────────────────
    if [[ -n "$shared_folder" ]]; then
        local link_path="${home_dir}/shared"
        if ln -s "$shared_folder" "$link_path" 2>>"$LOG_FILE"; then
            chown -h "$username":"$username" "$link_path" 2>>"$LOG_FILE"
            detail "Created symlink $link_path → $shared_folder"
        else
            warn "Failed to create symlink for '$username'."
        fi
    fi

    # ── 8f. Sudo alias ────────────────────────────────────────────────────
    if $is_sudo; then
        create_sudo_alias "$home_dir" "$username"
    fi

    # ── 8g. Summary output ───────────────────────────────────────────────
    info "  Username     : $username"
    info "  Home dir     : $home_dir"
    info "  Password     : $password  (must change on first login)"
    info "  Groups       : ${groups_to_add[*]:-none}"
    [[ -n "$shared_folder" ]] && info "  Shared folder: $shared_folder  (link: ${home_dir}/shared)"
    $is_sudo && info "  Alias 'myls' created in ${home_dir}/.bash_aliases"

    log_msg "SUCCESS" "User '$username' created. Groups: ${groups_to_add[*]:-none}. Folder: ${shared_folder:-none}."
}

# ---------------------------------------------------------------------------
# 9. CSV PARSING
# ---------------------------------------------------------------------------

parse_and_process() {
    local csv_file="$1"

    info "Input file : $csv_file"
    detail "Full path  : $(realpath "$csv_file")"

    # Count data rows (exclude header)
    local total
    total=$(tail -n +2 "$csv_file" | grep -c '[^[:space:]]')
    info "Users to process: $total"

    # Confirmation prompt before making changes
    echo ""
    echo -e "${YELLOW}About to create/configure $total user(s). Continue? [y/N]${NC}"
    read -rp "> " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Aborted by user."
        exit 0
    fi

    local line_num=0
    while IFS=',' read -r email birthdate col3 col4 col5; do
        (( line_num++ ))

        # Skip header row
        [[ "$email" == "e-mail" ]] && continue

        # Trim whitespace/carriage-returns from each field
        email="${email//[$'\r\n ']/}"
        birthdate="${birthdate//[$'\r\n ']/}"
        col3="${col3//[$'\r\n ']/}"
        col4="${col4//[$'\r\n ']/}"
        col5="${col5//[$'\r\n ']/}"

        # Skip blank lines
        [[ -z "$email" ]] && continue

        # ── Interpret variable columns ─────────────────────────────────
        # The CSV format has up to 5 columns:
        #   e-mail, birth date, [groups...], sharedFolder
        # Groups come before sharedFolder; sharedFolder starts with /
        # Possible combinations (see sample):
        #   email, date, sudo, staff, /folder   → groups=sudo,staff  folder=/folder
        #   email, date, sudo,      , /folder   → groups=sudo        folder=/folder
        #   email, date, staff,     , /folder   → groups=staff       folder=/folder
        #   email, date, sudo,      ,           → groups=sudo        folder=
        #   email, date,    ,       , /folder   → groups=            folder=/folder

        local groups="" folder=""

        # col3 is always the first group (or empty)
        # col4 is either a second group or the folder (if starts with /)
        # col5 is the folder (if col4 was a group)

        if [[ "$col3" == /* ]]; then
            # col3 is the folder, no groups
            folder="$col3"
        else
            [[ -n "$col3" ]] && groups="$col3"
            if [[ "$col4" == /* ]]; then
                folder="$col4"
            else
                [[ -n "$col4" ]] && groups="${groups},${col4}"
                [[ "$col5" == /* ]] && folder="$col5"
            fi
        fi

        # Remove leading comma if groups starts with one
        groups="${groups#,}"

        detail "Row $line_num: email=$email birth=$birthdate groups='$groups' folder='$folder'"

        create_user "$email" "$birthdate" "$groups" "$folder"

    done < "$csv_file"

    echo ""
    info "All users processed. See log for details: $LOG_FILE"
}

# ---------------------------------------------------------------------------
# 10. CLEANUP ON EXIT
# ---------------------------------------------------------------------------
cleanup() {
    # Remove downloaded CSV if we fetched it ourselves
    if [[ -n "$DOWNLOADED_CSV" && -f "$DOWNLOADED_CSV" ]]; then
        rm -f "$DOWNLOADED_CSV"
        detail "Removed temporary downloaded CSV: $DOWNLOADED_CSV"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 11. MAIN
# ---------------------------------------------------------------------------
main() {
    # Initialise log
    echo "============================================================" >> "$LOG_FILE"
    log_msg "INFO" "Script started. PID=$$. User=$(whoami). Args: $*"
    echo "============================================================" >> "$LOG_FILE"

    check_root
    check_dependencies

    local csv_path
    csv_path=$(get_input "$1")

    parse_and_process "$csv_path"
}

main "$@"
