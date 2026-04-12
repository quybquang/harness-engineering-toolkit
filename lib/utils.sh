#!/bin/sh
# harness-toolkit: shared utilities
# Sourced by all other scripts. POSIX sh compatible.

# ── Constants ────────────────────────────────────────────────────────────────

# Exit codes
EXIT_SUCCESS=0
EXIT_WARN=1
EXIT_INPUT_ERROR=2
EXIT_STATE_CONFLICT=3
EXIT_WRITE_ERROR=4
EXIT_LLM_ERROR=5

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN=''
fi

# Paths (set after TOOLKIT_DIR and PROJECT_ROOT are established)
HARNESS_DIR=""
RULES_DIR=""
HOOKS_DIR=""
STATE_DIR=""
BACKUP_DIR=""
CONFIG_FILE=""
CONTEXT_FILE=""
CLAUDE_MD=""

# Flags (set by parse_flags)
FLAG_DRY_RUN=false
FLAG_FORCE=false
FLAG_VERBOSE=false
FLAG_FIX=false
FLAG_JSON=false
FLAG_SKIP_QUESTIONS=false
FLAG_TIER=""

# ── Logging ──────────────────────────────────────────────────────────────────

log_info() {
    printf "${C_BLUE}[harness]${C_RESET} %s\n" "$*"
}

log_success() {
    printf "${C_GREEN}[harness]${C_RESET} %s\n" "$*"
}

log_warn() {
    printf "${C_YELLOW}[harness]${C_RESET} %s\n" "$*" >&2
}

log_error() {
    printf "${C_RED}[harness]${C_RESET} %s\n" "$*" >&2
}

log_step() {
    printf "  ${C_DIM}→${C_RESET} %s\n" "$*"
}

log_verbose() {
    if [ "$FLAG_VERBOSE" = true ]; then
        printf "${C_DIM}[verbose]${C_RESET} %s\n" "$*"
    fi
}

# ── Dependency Check ─────────────────────────────────────────────────────────

ensure_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed."
        log_error "Install: brew install jq (macOS) or apt install jq (Linux)"
        exit $EXIT_INPUT_ERROR
    fi
}

# ── Flag Parsing ─────────────────────────────────────────────────────────────

parse_flags() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)          FLAG_DRY_RUN=true ;;
            --force)            FLAG_FORCE=true ;;
            --verbose)          FLAG_VERBOSE=true ;;
            --fix)              FLAG_FIX=true ;;
            --json)             FLAG_JSON=true ;;
            --skip-questions)   FLAG_SKIP_QUESTIONS=true ;;
            --tier=*)           FLAG_TIER="${1#--tier=}" ;;
            --*)                log_warn "Unknown flag: $1" ;;
            *)                  ;; # positional args handled by caller
        esac
        shift
    done
}

# ── Path Setup ───────────────────────────────────────────────────────────────

init_paths() {
    HARNESS_DIR="${PROJECT_ROOT}/.claude/harness"
    RULES_DIR="${HARNESS_DIR}/rules"
    HOOKS_DIR="${HARNESS_DIR}/hooks"
    STATE_DIR="${HARNESS_DIR}/state"
    BACKUP_DIR="${HARNESS_DIR}/backup"
    CONFIG_FILE="${HARNESS_DIR}/config.json"
    CONTEXT_FILE="${HARNESS_DIR}/project-context.json"
    CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
}

# ── JSON Helpers ─────────────────────────────────────────────────────────────

# Read a value from a JSON file
# Usage: json_get file.json '.path.to.value'
json_get() {
    jq -r "$2" "$1" 2>/dev/null
}

# Set a value in a JSON file (in-place)
# Usage: json_set file.json '.path' '"value"'
json_set() {
    _tmpfile="$(mktemp)"
    jq "$2 = $3" "$1" > "$_tmpfile" && mv "$_tmpfile" "$1"
}

# Merge two JSON objects (file2 values override file1)
# Usage: json_merge file1.json file2.json > output.json
json_merge() {
    jq -s '.[0] * .[1]' "$1" "$2"
}

# Create a new JSON object from key-value pairs
# Usage: json_obj key1 val1 key2 val2 ...
json_obj() {
    _obj="{"
    _first=true
    while [ $# -ge 2 ]; do
        if [ "$_first" = true ]; then
            _first=false
        else
            _obj="${_obj},"
        fi
        _obj="${_obj}\"$1\":$2"
        shift 2
    done
    _obj="${_obj}}"
    printf '%s' "$_obj"
}

# ── File Operations ──────────────────────────────────────────────────────────

# Compute sha256 hash of a file or string
# Usage: hash_file file.json
hash_file() {
    if [ -f "$1" ]; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}

# Compute hash of project-context.json excluding the hash field itself
hash_context() {
    if [ -f "$1" ]; then
        jq 'del(.hash)' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}

# Check if harness is initialized in current project
is_initialized() {
    [ -f "$CONFIG_FILE" ]
}

# Get toolkit version from config
get_config_version() {
    if [ -f "$CONFIG_FILE" ]; then
        json_get "$CONFIG_FILE" '.toolkit_version'
    fi
}

# Get current tier from config
get_config_tier() {
    if [ -f "$CONFIG_FILE" ]; then
        json_get "$CONFIG_FILE" '.tier'
    fi
}

# Check for v2 markers in a file
has_v2_markers() {
    [ -f "$1" ] && grep -q '<!-- HARNESS:START v2' "$1" 2>/dev/null
}

# Check for v1 markers (legacy)
has_v1_markers() {
    [ -f "$1" ] && grep -q '<!-- HARNESS:START -->' "$1" 2>/dev/null && ! grep -q '<!-- HARNESS:START v2' "$1" 2>/dev/null
}

# Convert tier name to numeric level for comparison
# minimal=1, standard=2, full=3, enterprise=4
tier_to_level() {
    case "$1" in
        minimal)    echo 1 ;;
        standard)   echo 2 ;;
        full)       echo 3 ;;
        enterprise) echo 4 ;;
        *)          echo 0 ;;
    esac
}

# Check if current tier is at least the given tier
tier_at_least() {
    _current_level=$(tier_to_level "$1")
    _required_level=$(tier_to_level "$2")
    [ "$_current_level" -ge "$_required_level" ]
}

# ── Marker Operations ────────────────────────────────────────────────────────

# Extract content between v2 markers from a file
# Usage: extract_marker_content file.md
extract_marker_content() {
    if has_v2_markers "$1"; then
        awk '/<!-- HARNESS:START v2/{found=1; next} /<!-- HARNESS:END v2/{found=0} found' "$1"
    fi
}

# Extract content OUTSIDE markers (user content)
# Usage: extract_user_content file.md
extract_user_content() {
    if has_v2_markers "$1"; then
        awk '/<!-- HARNESS:START v2/{skip=1} /<!-- HARNESS:END v2/{skip=0; next} !skip' "$1"
    elif [ -f "$1" ]; then
        cat "$1"
    fi
}

# Replace content between v2 markers with new content
# Usage: replace_marker_content file.md new_content_file
replace_marker_content() {
    _target="$1"
    _new_content="$2"
    _tmpfile="$(mktemp)"
    _version="${TOOLKIT_VERSION:-0.1.0}"

    if has_v2_markers "$_target"; then
        # Replace between existing markers
        awk -v new_content="$(cat "$_new_content")" -v version="$_version" '
        /<!-- HARNESS:START v2/ {
            print "<!-- HARNESS:START v2 — Auto-generated by harness-toolkit v" version ". Do not edit. -->"
            print ""
            print new_content
            print ""
            skip = 1
            next
        }
        /<!-- HARNESS:END v2/ {
            print "<!-- HARNESS:END v2 -->"
            skip = 0
            next
        }
        !skip { print }
        ' "$_target" > "$_tmpfile" && mv "$_tmpfile" "$_target"
    else
        # Prepend markers before existing content
        {
            printf '<!-- HARNESS:START v2 — Auto-generated by harness-toolkit v%s. Do not edit. -->\n\n' "$_version"
            cat "$_new_content"
            printf '\n\n<!-- HARNESS:END v2 -->\n\n'
            if [ -f "$_target" ]; then
                cat "$_target"
            fi
        } > "$_tmpfile" && mv "$_tmpfile" "$_target"
    fi
}

# ── Backup ───────────────────────────────────────────────────────────────────

# Backup current harness state before write
backup_current() {
    if ! is_initialized && [ ! -f "$CLAUDE_MD" ]; then
        log_verbose "No existing harness to backup"
        return 0
    fi

    _timestamp=$(date +%s)
    _backup_path="${BACKUP_DIR}/${_timestamp}"
    mkdir -p "$_backup_path"

    # Backup Zone A
    if [ -d "$RULES_DIR" ]; then
        cp -r "$RULES_DIR" "$_backup_path/rules" 2>/dev/null
    fi
    if [ -d "$HOOKS_DIR" ]; then
        cp -r "$HOOKS_DIR" "$_backup_path/hooks" 2>/dev/null
    fi

    # Backup config
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$_backup_path/config.json" 2>/dev/null
    fi

    # Backup CLAUDE.md
    if [ -f "$CLAUDE_MD" ]; then
        cp "$CLAUDE_MD" "$_backup_path/CLAUDE.md" 2>/dev/null
    fi

    # Backup Zone B
    if [ -d "$STATE_DIR" ]; then
        cp -r "$STATE_DIR" "$_backup_path/state" 2>/dev/null
    fi

    log_verbose "Backed up to ${_backup_path}"

    # Prune old backups (keep last 5)
    prune_backups
}

# Keep only last 5 backups
prune_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        return 0
    fi

    _count=$(ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')
    if [ "$_count" -gt 5 ]; then
        ls -1d "$BACKUP_DIR"/*/ 2>/dev/null | sort -n | head -n $((_count - 5)) | while read -r _dir; do
            rm -rf "$_dir"
            log_verbose "Pruned old backup: $_dir"
        done
    fi
}

# ── Template Resolution ──────────────────────────────────────────────────────

# Resolve {{placeholders}} in a template using project-context.json
# Usage: resolve_template template_file context_file
resolve_template() {
    _template="$1"
    _context="$2"

    if [ ! -f "$_template" ]; then
        log_error "Template not found: $_template"
        return 1
    fi

    _content=$(cat "$_template")

    # Replace {{project_context_json}} with full context
    if printf '%s' "$_content" | grep -q '{{project_context_json}}'; then
        _ctx_json=$(cat "$_context")
        _content=$(printf '%s' "$_content" | sed "s|{{project_context_json}}|$(printf '%s' "$_ctx_json" | sed 's/[&/\]/\\&/g; s/$/\\n/' | tr -d '\n')|g" 2>/dev/null || printf '%s' "$_content")
    fi

    # Replace simple {{field.subfield}} placeholders
    printf '%s' "$_content" | while IFS= read -r line; do
        _resolved="$line"
        # Find all {{...}} patterns
        printf '%s' "$_resolved" | grep -o '{{[^}]*}}' | while read -r _placeholder; do
            _key=$(printf '%s' "$_placeholder" | sed 's/^{{//; s/}}$//')
            _jq_path=$(printf '%s' "$_key" | sed 's/\./\./g')
            _value=$(json_get "$_context" ".$_jq_path" 2>/dev/null)
            if [ -n "$_value" ] && [ "$_value" != "null" ]; then
                _resolved=$(printf '%s' "$_resolved" | sed "s|{{${_key}}}|${_value}|g")
            fi
        done
        printf '%s\n' "$_resolved"
    done
}

# ── User Interaction ─────────────────────────────────────────────────────────

# Ask user a yes/no question
# Usage: confirm "message" → returns 0 (yes) or 1 (no)
confirm() {
    if [ "$FLAG_FORCE" = true ]; then
        return 0
    fi
    printf "${C_CYAN}[harness]${C_RESET} %s [y/N] " "$1"
    read -r _answer
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Ask user a question with custom prompt
# Usage: ask "question" "default" → prints answer to stdout
ask() {
    if [ "$FLAG_SKIP_QUESTIONS" = true ] && [ -n "$2" ]; then
        printf '%s' "$2"
        return 0
    fi
    if [ -n "$2" ]; then
        printf "${C_CYAN}[harness]${C_RESET} %s [%s]: " "$1" "$2" >&2
    else
        printf "${C_CYAN}[harness]${C_RESET} %s: " "$1" >&2
    fi
    read -r _answer
    if [ -z "$_answer" ] && [ -n "$2" ]; then
        printf '%s' "$2"
    else
        printf '%s' "$_answer"
    fi
}

# ── Directory Helpers ────────────────────────────────────────────────────────

# Ensure directory exists
ensure_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
}

# Check if a file contains a pattern (case-insensitive)
file_contains() {
    [ -f "$1" ] && grep -qi "$2" "$1" 2>/dev/null
}

# Count files matching a glob pattern (respecting .harnessignore)
count_files() {
    _dir="${2:-$PROJECT_ROOT}"
    _ignore_file="${PROJECT_ROOT}/.harnessignore"

    if [ -f "$_ignore_file" ]; then
        find "$_dir" -name "$1" 2>/dev/null | grep -v -F -f "$_ignore_file" 2>/dev/null | wc -l | tr -d ' '
    else
        find "$_dir" -name "$1" 2>/dev/null | wc -l | tr -d ' '
    fi
}

# ── Dry Run Helper ───────────────────────────────────────────────────────────

# Wrap file writes in dry-run check
# Usage: safe_write target_path content_or_file
safe_write() {
    _target="$1"
    _source="$2"

    if [ "$FLAG_DRY_RUN" = true ]; then
        log_step "[dry-run] Would write: $_target"
        return 0
    fi

    ensure_dir "$(dirname "$_target")"

    if [ -f "$_source" ]; then
        cp "$_source" "$_target"
    else
        printf '%s\n' "$_source" > "$_target"
    fi
}

# ── ISO Timestamp ────────────────────────────────────────────────────────────

iso_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}
