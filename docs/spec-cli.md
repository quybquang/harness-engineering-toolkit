# Spec: CLI Entry Point & Shared Infrastructure — v2

---

## `bin/harness` — CLI Router

### Pseudocode

```bash
#!/bin/sh
set -e

TOOLKIT_VERSION="$(cat "$(dirname "$(readlink -f "$0")")/../VERSION")"
TOOLKIT_DIR="$(dirname "$(readlink -f "$0")")/.."
PROJECT_ROOT="$(pwd)"

. "$TOOLKIT_DIR/lib/utils.sh"

# --- Pre-flight ---
ensure_jq

COMMAND="$1"
[ -z "$COMMAND" ] && usage && exit 0
shift

case "$COMMAND" in
  init)    . "$TOOLKIT_DIR/lib/cmd-init.sh"    "$@" ;;
  update)  . "$TOOLKIT_DIR/lib/cmd-update.sh"  "$@" ;;
  check)   . "$TOOLKIT_DIR/lib/cmd-check.sh"   "$@" ;;
  eject)   . "$TOOLKIT_DIR/lib/cmd-eject.sh"   "$@" ;;
  version) echo "harness-toolkit v$TOOLKIT_VERSION" ;;
  help)    usage ;;
  *)       log_error "Unknown command: $COMMAND"; usage; exit 1 ;;
esac
```

### Flag Parsing Convention

All commands use a consistent flag parser in `utils.sh`:

```bash
parse_flags() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)        HARNESS_FLAG_DRY_RUN=1 ;;
      --force)          HARNESS_FLAG_FORCE=1 ;;
      --verbose)        HARNESS_FLAG_VERBOSE=1 ;;
      --fix)            HARNESS_FLAG_FIX=1 ;;
      --json)           HARNESS_FLAG_JSON=1 ;;
      --skip-questions) HARNESS_FLAG_SKIP_QUESTIONS=1 ;;
      --tier=*)         HARNESS_FLAG_TIER="${1#--tier=}" ;;
      *)                log_error "Unknown flag: $1"; exit 1 ;;
    esac
    shift
  done
}
```

---

## `lib/utils.sh` — Shared Utilities

### Logging

```bash
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { printf "${BLUE}[harness]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[harness]${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}[harness]${NC} %s\n" "$1" >&2; }
log_error()   { printf "${RED}[harness]${NC} %s\n" "$1" >&2; }
log_step()    { printf "${DIM}  → %s${NC}\n" "$1"; }
log_verbose() { [ "$HARNESS_FLAG_VERBOSE" = "1" ] && printf "${DIM}  [verbose] %s${NC}\n" "$1"; }
```

### JSON Helpers

```bash
json_get() {
  jq -r "$2" "$1" 2>/dev/null || echo ""
}

json_set() {
  local tmp="$(mktemp)"
  jq "$2 = $3" "$1" > "$tmp" && mv "$tmp" "$1"
}

json_merge() {
  jq -s '.[0] * .[1]' "$1" "$2"
}
```

### File Operations

```bash
hash_file() {
  jq 'del(.hash)' "$1" 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}

is_initialized() {
  [ -f "$PROJECT_ROOT/.claude/harness/config.json" ]
}

get_config_version() {
  json_get "$PROJECT_ROOT/.claude/harness/config.json" ".toolkit_version"
}

# Check for v2 markers in CLAUDE.md
has_v2_markers() {
  local file="$1"
  [ -f "$file" ] && grep -q "HARNESS:START v2" "$file" && grep -q "HARNESS:END v2" "$file"
}

# Check for v1 markers (for migration)
has_v1_markers() {
  local file="$1"
  [ -f "$file" ] && grep -q "HARNESS:START" "$file" && ! grep -q "HARNESS:START v2" "$file"
}

# Tier level helper
tier_to_level() {
  case "$1" in
    minimal)    echo 1 ;;
    standard)   echo 2 ;;
    full)       echo 3 ;;
    enterprise) echo 4 ;;
  esac
}
```

### Template Resolution

```bash
# Resolve a prompt template by replacing {{placeholders}} with project context values
resolve_template() {
  local template_file="$1"
  local context_file="$2"
  local content="$(cat "$template_file")"

  # Replace {{project_context_json}} with full context
  content="$(echo "$content" | sed "s|{{project_context_json}}|$(cat "$context_file")|")"

  # Replace individual field references
  for field in stack.frameworks stack.package_manager stack.test_framework infrastructure.database infrastructure.deployment infrastructure.ci_cd ai_indicators.has_agents; do
    local value="$(jq -r ".$field" "$context_file" 2>/dev/null)"
    local placeholder="$(echo "$field" | sed 's/\./_/g')"
    content="$(echo "$content" | sed "s|{{$field}}|$value|g")"
  done

  echo "$content"
}
```

### LLM Call Adapter

```bash
# LLM call wrapper — abstracts the actual call mechanism
# In Claude Code context: writes prompt to file, reads from slash command
# Standalone: could be adapted to API call
call_llm() {
  local prompt="$1"
  local prompt_file="$(mktemp)"
  local response_file="$(mktemp)"

  echo "$prompt" > "$prompt_file"

  # Mechanism depends on execution context
  if [ -n "$HARNESS_LLM_ADAPTER" ]; then
    # Custom adapter (e.g., API call)
    $HARNESS_LLM_ADAPTER "$prompt_file" > "$response_file"
  else
    # Default: Claude Code context (stdin/stdout)
    cat "$prompt_file"
    # Response comes from Claude Code's LLM response
    read -r response
    echo "$response" > "$response_file"
  fi

  cat "$response_file"
  rm -f "$prompt_file" "$response_file"
}
```

### Backup

```bash
backup_current() {
  local harness_dir="$PROJECT_ROOT/.claude/harness"
  local backup_dir="$harness_dir/backup/$(date +%s)"

  mkdir -p "$backup_dir"

  # Backup Zone A
  [ -d "$harness_dir/rules" ] && cp -r "$harness_dir/rules" "$backup_dir/"
  [ -d "$harness_dir/hooks" ] && cp -r "$harness_dir/hooks" "$backup_dir/"

  # Backup config
  [ -f "$harness_dir/config.json" ] && cp "$harness_dir/config.json" "$backup_dir/"

  # Backup Zone B (safety — never overwritten by toolkit)
  [ -d "$harness_dir/state" ] && cp -r "$harness_dir/state" "$backup_dir/"

  # Backup CLAUDE.md
  [ -f "$PROJECT_ROOT/CLAUDE.md" ] && cp "$PROJECT_ROOT/CLAUDE.md" "$backup_dir/"

  # Prune old backups (keep last 5)
  local count=0
  for dir in $(ls -1dt "$harness_dir/backup/"*/ 2>/dev/null); do
    count=$((count + 1))
    [ "$count" -gt 5 ] && rm -rf "$dir"
  done

  log_step "Backed up to $backup_dir"
}
```

### Dependency Check

```bash
ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed."
    log_error "Install: brew install jq (macOS) | apt install jq (Linux)"
    exit 1
  fi
}
```

---

## Error Handling Strategy

### Exit Codes (all commands)

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Validation warning (operation completed, but issues found) |
| 2 | Input error (bad flags, missing project, no recognizable project) |
| 3 | State conflict (already initialized for init, not initialized for update) |
| 4 | Write error (filesystem permission, disk full, malformed markers) |
| 5 | LLM error (generation failed, timeout, no response) |

### Recovery Patterns

| Error | Recovery |
|---|---|
| Discover fails (empty project) | Exit 2: "No recognizable project files found" |
| Classify conflict | Fall back to LLM. If LLM fails → default to `minimal` + warn |
| Generate fails (LLM timeout) | Retry once. If fails → exit 5: "Generation failed" |
| Write fails mid-way | Restore from backup. Exit 4: "Write failed. Previous state restored" |
| Validate finds issues | Exit 1. Print issues. Suggest `harness check --fix` |
| Markers malformed | Abort write. Exit 4: "CLAUDE.md markers are malformed. Fix manually or run `harness eject` then `harness init`" |
| v1 markers detected | Auto-migrate to v2 during write step |

---

## UX: What User Sees

### `harness init` — Success

```
[harness] Discovering project...
  → Detected: TypeScript, Next.js 15, pnpm
  → Detected: Vercel deployment, GitHub Actions CI
  → Detected: 2 services (web, api)
  → AI indicators: @ai-sdk/anthropic found
[harness] Classifying...
  → Tier: full (agentic + multi-service)
  → Patterns: 12 patterns active
[harness] Generating harness content...
  → rules/conventions.md ✓
  → rules/risk-rules.md ✓
  → rules/workflow.md ✓
  → rules/architecture.md ✓
  → Evaluator: conventions.md passed
  → Evaluator: risk-rules.md passed
  → Evaluator: architecture.md passed
[harness] Writing files...
  → CLAUDE.md (created with v2 map, ~20 lines)
  → .claude/harness/hooks/pre-command.sh ✓
  → .claude/settings.json (hooks registered)
  → state/progress.md ✓
  → state/learnings.md ✓
  → state/plans/ templates ✓
  → .claude/harness/config.json ✓
[harness] Validating...
  → Structure: 12/12 checks passed
  → Consistency: no issues
  → Freshness: ok
  → Quality: all files passed

[harness] ✓ Initialized (tier: full, 12 patterns)
[harness]   CLAUDE.md is a map (~20 lines). Rules live in .claude/harness/rules/
```

### `harness init` — Already initialized

```
[harness] Error: Harness already initialized in this project.
[harness] Use `harness update` to update, or `harness eject` then `harness init` for fresh start.
```

### `harness check` — Issues found

```
[harness] Checking harness...
  → Structure: 10/12 checks passed
    ✗ Hook script hooks/post-edit.sh is not executable
    ✗ Scoped config src/payments/CLAUDE.md listed in config but file missing
  → Consistency: project has changed since last generate
    ! New dependency detected: prisma (not reflected in conventions)
  → Freshness:
    ! state/progress.md last updated 12 days ago (stale)
    ! Plan fix-auth-bug.md is in-progress but 18 days old
  → Quality:
    ! Risk rules don't cover database migration commands (prisma migrate)

[harness] 2 errors, 3 warnings. Run `harness check --fix` to auto-fix errors.
```

### `harness update` — v1 → v2 Migration

```
[harness] Discovering project...
  → Detected: TypeScript, React, npm
[harness] Classifying...
  → Tier: standard (CI/CD detected)
[harness] Generating harness content...
  → Migrating from v1 to v2 format
  → rules/conventions.md ✓ (overrides only — trimmed from 85 to 28 lines)
  → rules/risk-rules.md ✓
  → rules/workflow.md ✓ (session protocol)
[harness] Writing files...
  → CLAUDE.md (migrated v1 → v2 map, 85 lines → 18 lines)
  → state/progress.md ✓ (new in v2)
  → state/learnings.md ✓ (new in v2)
[harness] Validating...
  → All checks passed

[harness] ✓ Updated to v2 (tier: standard, 8 patterns)
```
