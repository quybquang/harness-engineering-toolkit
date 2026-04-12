# Spec: Eject & Slash Commands — v2

---

## Part 1: Eject

### Overview

**Command**: `harness eject`
**Purpose**: Remove toolkit management. Convert from toolkit-managed → manually-maintained harness.
**Executor**: Pure shell script

### v2 Changes

| v1 | v2 |
|---|---|
| Inline content between markers | Map between markers → inline rules into CLAUDE.md body |
| Remove `generated/` | Remove `rules/` (Zone A). Keep `state/` (Zone B) |
| Remove `state.json` | Remove `config.json` |
| No Zone B handling | Zone B (state/, plans/) kept in place |

### Behavior

```bash
run_eject() {
  if ! is_initialized; then
    log_error "Harness not initialized in this project."
    exit 3
  fi

  # Confirm
  if [ "$HARNESS_FLAG_FORCE" != "1" ]; then
    printf "${YELLOW}This will:${NC}\n"
    echo "  1. Inline harness map content into CLAUDE.md (remove markers)"
    echo "  2. Append rules/* content to CLAUDE.md (so nothing is lost)"
    echo "  3. Remove toolkit-managed files (.claude/harness/rules/, hooks/, config.json)"
    echo "  4. Remove [harness] hooks from .claude/settings.json"
    echo "  5. Keep agent-managed state files (.claude/harness/state/)"
    echo ""
    printf "Continue? [y/N] "
    read -r answer
    [ "$answer" != "y" ] && [ "$answer" != "Y" ] && exit 0
  fi

  # Step 1: Inline CLAUDE.md
  eject_claude_md

  # Step 2: Remove hooks from settings.json
  eject_hooks

  # Step 3: Remove toolkit files (keep state/)
  eject_files

  log_success "Ejected. Harness is now manually maintained."
  log_step "Zone A (rules) inlined into CLAUDE.md"
  log_step "Zone B (state/) preserved at .claude/harness/state/"
  log_step "You can safely delete .claude/harness/ entirely if you don't need state files"
}
```

### CLAUDE.md Ejection

```bash
eject_claude_md() {
  local target="$PROJECT_ROOT/CLAUDE.md"
  local rules_dir="$PROJECT_ROOT/.claude/harness/rules"

  if [ ! -f "$target" ]; then
    log_warn "CLAUDE.md not found, nothing to inline"
    return
  fi

  # Extract map content (between v2 markers)
  local map_content=""
  if has_v2_markers "$target"; then
    map_content="$(awk '/HARNESS:START v2/{found=1; next} /HARNESS:END v2/{found=0; next} found{print}' "$target")"
  elif has_v1_markers "$target"; then
    map_content="$(awk '/HARNESS:START/{found=1; next} /HARNESS:END/{found=0; next} found{print}' "$target")"
  fi

  # Build ejected content
  local ejected_content=""

  # Start with map content (minus the "Read .claude/harness/rules/..." pointers)
  if [ -n "$map_content" ]; then
    ejected_content="$(echo "$map_content" | grep -v '\.claude/harness/rules/')"
  fi

  # Append rules file contents
  for rules_file in conventions.md risk-rules.md workflow.md architecture.md; do
    if [ -f "$rules_dir/$rules_file" ]; then
      ejected_content="$ejected_content

$(cat "$rules_dir/$rules_file")"
    fi
  done

  # Remove marker block from CLAUDE.md
  if has_v2_markers "$target"; then
    local before="$(awk '/HARNESS:START v2/{exit} {print}' "$target")"
    local after="$(awk '/HARNESS:END v2/{found=1; next} found{print}' "$target")"
  elif has_v1_markers "$target"; then
    local before="$(awk '/HARNESS:START/{exit} {print}' "$target")"
    local after="$(awk '/HARNESS:END/{found=1; next} found{print}' "$target")"
  fi

  # Reassemble: ejected content + user's existing content
  echo "$ejected_content
$before
$after" | sed '/^$/N;/^\n$/d' > "$target"

  log_step "Inlined harness content into CLAUDE.md"
}
```

### Hooks Removal

```bash
eject_hooks() {
  local settings="$PROJECT_ROOT/.claude/settings.json"

  if [ ! -f "$settings" ]; then
    return
  fi

  # Remove only [harness] hooks
  local tmp="$(mktemp)"
  jq '
    if .hooks then
      .hooks |= (
        to_entries |
        map({
          key: .key,
          value: [.value[] | select(.description | test("^\\[harness\\]") | not)]
        }) |
        map(select(.value | length > 0)) |
        from_entries
      )
    else . end
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"

  log_step "Removed [harness] hooks from settings.json"
}
```

### File Cleanup

```bash
eject_files() {
  local harness_dir="$PROJECT_ROOT/.claude/harness"

  # Remove Zone A (toolkit-managed)
  rm -rf "$harness_dir/rules"
  rm -rf "$harness_dir/hooks"
  rm -f "$harness_dir/config.json"
  rm -f "$harness_dir/project-context.json"
  rm -f "$harness_dir/.map-content.tmp"
  rm -rf "$harness_dir/backup"
  rm -f "$PROJECT_ROOT/.harnessignore"

  # Keep Zone B (agent-managed)
  # .claude/harness/state/ stays intact

  log_step "Removed toolkit files (kept state/)"
}
```

---

## Part 2: Slash Commands

### Installation

Slash commands are symlinked from `~/.claude/commands/` to the toolkit repo.

```bash
# install.sh
install_commands() {
  local commands_dir="$HOME/.claude/commands"
  mkdir -p "$commands_dir"

  for cmd in "$TOOLKIT_DIR/commands/"*.md; do
    local name="$(basename "$cmd")"
    local target="$commands_dir/$name"

    if [ -L "$target" ]; then
      rm "$target"
    elif [ -f "$target" ]; then
      log_warn "Non-symlink $name exists in $commands_dir. Skipping."
      continue
    fi

    ln -s "$cmd" "$target"
    log_step "Linked /$name"
  done

  log_success "Commands installed. Available in any Claude Code session."
}
```

### Command Definitions

#### `/harness.md` — Full Pipeline

```markdown
Run the harness engineering toolkit for the current project.

## Usage

1. If `.claude/harness/config.json` exists → run `harness update`
2. If not → run `harness init`

## Steps

### Init Mode (new project)
1. Run `$TOOLKIT_DIR/bin/harness init`
2. Review generated CLAUDE.md map
3. Review rules in `.claude/harness/rules/`

### Update Mode (existing harness)
1. Run `$TOOLKIT_DIR/bin/harness update`
2. Review changes

After either mode, run `$TOOLKIT_DIR/bin/harness check` to validate.
```

#### `/harness-check.md` — Validate

```markdown
Check the harness configuration for the current project.

Run: `$TOOLKIT_DIR/bin/harness check`

If issues are found, try: `$TOOLKIT_DIR/bin/harness check --fix`

Report the results to the user.
```

#### `/harness-eject.md` — Eject

```markdown
Eject the harness toolkit from the current project.

This inlines all harness content into CLAUDE.md and removes toolkit management.

Run: `$TOOLKIT_DIR/bin/harness eject`

After ejection:
- CLAUDE.md contains all rules directly
- .claude/harness/state/ is preserved (plans, progress, learnings)
- Hooks are removed from settings.json
- The project is no longer managed by the toolkit
```

---

## Part 3: Uninstall

```bash
# uninstall.sh
uninstall_commands() {
  local commands_dir="$HOME/.claude/commands"

  for cmd in "$TOOLKIT_DIR/commands/"*.md; do
    local name="$(basename "$cmd")"
    local target="$commands_dir/$name"

    if [ -L "$target" ]; then
      rm "$target"
      log_step "Removed /$name"
    fi
  done

  log_success "Commands uninstalled."
}
```

---

## Edge Cases

| Case | Handling |
|---|---|
| Eject with custom content after markers | Preserved — only content between markers is touched |
| Eject with no markers in CLAUDE.md | Append rules content to end of CLAUDE.md |
| Eject with Zone B files | Kept in place. User informed they can delete manually |
| Eject interrupted mid-way | CLAUDE.md may be partially modified. Backup exists for recovery |
| Slash command conflict (user has /harness) | Install warns "Non-symlink exists. Skipping." |
| Uninstall with harness still active in projects | Only removes commands. Harness in projects stays. User must eject per-project |
| Install on system without ~/.claude/ | Create the directory |
