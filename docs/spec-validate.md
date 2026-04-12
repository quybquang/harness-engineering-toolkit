# Spec: Validate Step — v2

---

## Overview

**File**: `lib/validate.sh`
**Input**: Current harness state in `.claude/harness/` + `CLAUDE.md`
**Output**: Validation report (pass/warn/fail)
**Executor**: Shell script (structure checks) + LLM (quality review, optional)

### v2 Changes Summary

| v1 | v2 |
|---|---|
| Structure checks only | Structure + freshness + quality checks |
| Check `generated/*.md` | Check `rules/*.md` (Zone A) + `state/` (Zone B) |
| `state.json` | `config.json` |
| No freshness checks | Warn if progress.md >7 days old, convention drift |
| Generic quality review | Evaluator criteria (specificity, discoverability, actionability, conciseness) |

---

## Validation Levels

```bash
run_validate() {
  local errors=0
  local warnings=0

  # Level 1: Structure (always run)
  validate_structure
  errors=$((errors + $?))

  # Level 2: Consistency (always run)
  validate_consistency
  warnings=$((warnings + $?))

  # Level 3: Freshness (standard+ tier)
  local tier="$(json_get "$PROJECT_ROOT/.claude/harness/config.json" ".tier")"
  local tier_level="$(tier_to_level "$tier")"
  if [ "$tier_level" -ge 2 ]; then
    validate_freshness
    warnings=$((warnings + $?))
  fi

  # Level 4: Quality (full+ tier, LLM)
  if [ "$tier_level" -ge 3 ]; then
    validate_quality
    warnings=$((warnings + $?))
  fi

  # Report
  if [ "$errors" -gt 0 ]; then
    log_error "$errors error(s), $warnings warning(s)"
    return 1
  elif [ "$warnings" -gt 0 ]; then
    log_warn "Passed with $warnings warning(s)"
    return 0
  else
    log_success "All checks passed"
    return 0
  fi
}
```

---

## Level 1: Structure Validation

Checks that all expected files exist, are non-empty, and markers are correct.

```bash
validate_structure() {
  local errors=0
  local config_file="$PROJECT_ROOT/.claude/harness/config.json"
  local tier="$(json_get "$config_file" ".tier")"
  local tier_level="$(tier_to_level "$tier")"

  # --- Required for all tiers ---

  # CLAUDE.md exists and has v2 markers
  if [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
    if grep -q "HARNESS:START v2" "$PROJECT_ROOT/CLAUDE.md" && \
       grep -q "HARNESS:END v2" "$PROJECT_ROOT/CLAUDE.md"; then
      log_step "✓ CLAUDE.md has v2 markers"
    elif grep -q "HARNESS:START" "$PROJECT_ROOT/CLAUDE.md"; then
      log_warn "✗ CLAUDE.md has v1 markers — run \`harness update\` to migrate"
      errors=$((errors + 1))
    else
      log_error "✗ CLAUDE.md exists but has no harness markers"
      errors=$((errors + 1))
    fi
  else
    log_error "✗ CLAUDE.md not found"
    errors=$((errors + 1))
  fi

  # config.json exists
  check_file_exists "$config_file" "config.json" || errors=$((errors + 1))

  # project-context.json exists
  check_file_exists "$PROJECT_ROOT/.claude/harness/project-context.json" "project-context.json" || errors=$((errors + 1))

  # Zone A: rules/ files
  check_file_exists_nonempty "$PROJECT_ROOT/.claude/harness/rules/conventions.md" "rules/conventions.md" || errors=$((errors + 1))
  check_file_exists_nonempty "$PROJECT_ROOT/.claude/harness/rules/risk-rules.md" "rules/risk-rules.md" || errors=$((errors + 1))

  # Hooks
  local pre_cmd="$PROJECT_ROOT/.claude/harness/hooks/pre-command.sh"
  if [ -f "$pre_cmd" ]; then
    if [ -x "$pre_cmd" ]; then
      log_step "✓ hooks/pre-command.sh exists and is executable"
    else
      log_error "✗ hooks/pre-command.sh is not executable"
      errors=$((errors + 1))
      if [ "$HARNESS_FLAG_FIX" = "1" ]; then
        chmod +x "$pre_cmd"
        log_step "  → Fixed: made executable"
        errors=$((errors - 1))
      fi
    fi
  else
    log_error "✗ hooks/pre-command.sh not found"
    errors=$((errors + 1))
  fi

  # settings.json has harness hooks
  local settings="$PROJECT_ROOT/.claude/settings.json"
  if [ -f "$settings" ] && jq -e '.hooks' "$settings" > /dev/null 2>&1; then
    if jq -e '.hooks | to_entries[] | .value[] | select(.description | test("\\[harness\\]"))' "$settings" > /dev/null 2>&1; then
      log_step "✓ settings.json has harness hooks"
    else
      log_warn "✗ settings.json missing harness hooks"
      errors=$((errors + 1))
    fi
  else
    log_error "✗ settings.json missing or has no hooks section"
    errors=$((errors + 1))
  fi

  # --- Standard+ tier ---
  if [ "$tier_level" -ge 2 ]; then
    check_file_exists_nonempty "$PROJECT_ROOT/.claude/harness/rules/workflow.md" "rules/workflow.md" || errors=$((errors + 1))

    # Zone B: state directory structure
    check_file_exists "$PROJECT_ROOT/.claude/harness/state/progress.md" "state/progress.md" || errors=$((errors + 1))
    check_file_exists "$PROJECT_ROOT/.claude/harness/state/learnings.md" "state/learnings.md" || errors=$((errors + 1))

    if [ -d "$PROJECT_ROOT/.claude/harness/state/plans" ]; then
      log_step "✓ state/plans/ directory exists"
    else
      log_error "✗ state/plans/ directory missing"
      errors=$((errors + 1))
    fi
  fi

  # --- Full+ tier ---
  if [ "$tier_level" -ge 3 ]; then
    check_file_exists_nonempty "$PROJECT_ROOT/.claude/harness/rules/architecture.md" "rules/architecture.md" || errors=$((errors + 1))
  fi

  # --- Scoped configs ---
  local scoped_configs="$(json_get "$config_file" ".scoped_configs[]" 2>/dev/null)"
  for config in $scoped_configs; do
    if [ -f "$PROJECT_ROOT/$config" ]; then
      log_step "✓ Scoped config $config exists"
    else
      log_error "✗ Scoped config $config listed in config.json but file missing"
      errors=$((errors + 1))
    fi
  done

  return $errors
}

check_file_exists() {
  local file="$1"
  local label="$2"
  if [ -f "$file" ]; then
    log_step "✓ $label exists"
    return 0
  else
    log_error "✗ $label not found"
    return 1
  fi
}

check_file_exists_nonempty() {
  local file="$1"
  local label="$2"
  if [ -f "$file" ] && [ -s "$file" ]; then
    log_step "✓ $label exists and is non-empty"
    return 0
  elif [ -f "$file" ]; then
    log_error "✗ $label exists but is empty"
    return 1
  else
    log_error "✗ $label not found"
    return 1
  fi
}
```

---

## Level 2: Consistency Validation

Re-discovers project context and compares with stored hash.

```bash
validate_consistency() {
  local warnings=0
  local config_file="$PROJECT_ROOT/.claude/harness/config.json"
  local context_file="$PROJECT_ROOT/.claude/harness/project-context.json"

  # Re-discover (lightweight — just hash comparison)
  local stored_hash="$(json_get "$context_file" ".hash")"
  local current_hash="sha256:$(jq 'del(.hash)' "$context_file" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"

  if [ "$stored_hash" = "$current_hash" ]; then
    log_step "✓ project-context.json hash matches"
  else
    log_warn "! project-context.json has been modified externally"
    warnings=$((warnings + 1))
  fi

  # Check if actual project has changed since last discovery
  # Quick check: compare key files' modification time vs generated_at
  local generated_at="$(json_get "$config_file" ".generated_at")"
  local newer_files=0

  for f in package.json go.mod pyproject.toml docker-compose.yml; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
      # Check if file is newer than generation time
      if [ "$PROJECT_ROOT/$f" -nt "$context_file" ]; then
        log_warn "! $f is newer than last discovery"
        newer_files=$((newer_files + 1))
      fi
    fi
  done

  if [ "$newer_files" -gt 0 ]; then
    log_warn "! Project may have changed since last harness generation"
    log_step "  Run \`harness update\` to regenerate"
    warnings=$((warnings + 1))
  else
    log_step "✓ No dependency file changes detected"
  fi

  # Version compatibility
  local toolkit_version="$TOOLKIT_VERSION"
  local state_version="$(json_get "$config_file" ".toolkit_version")"
  local min_version="$(json_get "$config_file" ".min_compatible_version")"

  if [ "$toolkit_version" != "$state_version" ]; then
    if version_gte "$toolkit_version" "$min_version"; then
      log_step "✓ Toolkit version compatible (generated: $state_version, current: $toolkit_version)"
    else
      log_warn "! Toolkit version $toolkit_version is older than minimum compatible $min_version"
      warnings=$((warnings + 1))
    fi
  fi

  return $warnings
}
```

---

## Level 3: Freshness Checks (Standard+ Tier)

Checks that agent-managed state is being maintained.

```bash
validate_freshness() {
  local warnings=0

  # Check progress.md freshness
  local progress="$PROJECT_ROOT/.claude/harness/state/progress.md"
  if [ -f "$progress" ]; then
    local days_old="$(file_age_days "$progress")"
    if [ "$days_old" -gt 7 ]; then
      log_warn "! state/progress.md last updated $days_old days ago (stale)"
      log_step "  Agent should update this at the end of each session"
      warnings=$((warnings + 1))
    elif [ "$days_old" -gt 3 ]; then
      log_step "~ state/progress.md updated $days_old days ago"
    else
      log_step "✓ state/progress.md is fresh ($days_old days old)"
    fi
  fi

  # Check for orphaned plans (in-progress plans with no recent updates)
  local plans_dir="$PROJECT_ROOT/.claude/harness/state/plans"
  if [ -d "$plans_dir" ]; then
    for plan in "$plans_dir"/*.md; do
      [ -f "$plan" ] || continue
      local basename="$(basename "$plan")"
      # Skip templates
      echo "$basename" | grep -q "^_template" && continue

      local age="$(file_age_days "$plan")"
      if [ "$age" -gt 14 ] && grep -q "Status: in-progress" "$plan"; then
        log_warn "! Plan $basename is in-progress but hasn't been updated in $age days"
        warnings=$((warnings + 1))
      fi
    done
  fi

  # Check if risk-rules cover new dependencies
  local context_file="$PROJECT_ROOT/.claude/harness/project-context.json"
  local database="$(json_get "$context_file" ".infrastructure.database")"
  local risk_rules="$PROJECT_ROOT/.claude/harness/rules/risk-rules.md"

  if [ "$database" = "supabase" ] && [ -f "$risk_rules" ]; then
    if ! grep -qi "supabase" "$risk_rules"; then
      log_warn "! Risk rules don't mention Supabase (detected in project)"
      warnings=$((warnings + 1))
    fi
  fi

  if [ "$database" = "postgresql" ] && [ -f "$risk_rules" ]; then
    if ! grep -qi "prisma\|drizzle\|migrate" "$risk_rules"; then
      log_warn "! Risk rules don't cover database migration commands"
      warnings=$((warnings + 1))
    fi
  fi

  return $warnings
}

file_age_days() {
  local file="$1"
  local now="$(date +%s)"
  local mtime="$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)"
  echo $(( (now - mtime) / 86400 ))
}
```

---

## Level 4: Quality Validation (Full+ Tier, LLM)

Uses evaluator criteria to review generated content quality.

```bash
validate_quality() {
  local warnings=0
  local context_file="$PROJECT_ROOT/.claude/harness/project-context.json"

  log_step "Running quality review (LLM)..."

  for rules_file in conventions.md risk-rules.md architecture.md; do
    local file="$PROJECT_ROOT/.claude/harness/rules/$rules_file"
    [ -f "$file" ] || continue

    local content="$(cat "$file")"
    local prompt="Review this harness rules file for quality.

## Project Context
$(cat "$context_file")

## File: $rules_file
\`\`\`markdown
$content
\`\`\`

## Check each line against these criteria:
1. SPECIFICITY: Is it specific to this project? (not generic advice)
2. DISCOVERABILITY: Could an AI agent discover this from reading code? (if yes, it shouldn't be here)
3. ACTIONABILITY: Can an agent follow it mechanically? (not vague)
4. CONCISENESS: Is the file under 40 lines?

## Output
Respond with JSON:
{
  \"pass\": true|false,
  \"issues\": [\"description of each issue\"],
  \"suggestion\": \"brief overall suggestion or empty string\"
}
Only flag clear violations. Minor style issues are not worth flagging."

    local response="$(call_llm "$prompt")"
    local pass="$(echo "$response" | jq -r '.pass' 2>/dev/null)"

    if [ "$pass" = "true" ]; then
      log_step "✓ Quality: $rules_file passed"
    else
      local issues="$(echo "$response" | jq -r '.issues[]' 2>/dev/null)"
      local suggestion="$(echo "$response" | jq -r '.suggestion' 2>/dev/null)"
      log_warn "! Quality: $rules_file has issues"
      echo "$issues" | while read -r issue; do
        log_step "    - $issue"
      done
      [ -n "$suggestion" ] && [ "$suggestion" != "null" ] && log_step "    Suggestion: $suggestion"
      warnings=$((warnings + 1))
    fi
  done

  return $warnings
}
```

---

## `harness check --fix` Auto-Fix

```bash
auto_fix() {
  local fixed=0

  # Fix non-executable hooks
  for hook in "$PROJECT_ROOT/.claude/harness/hooks/"*.sh; do
    [ -f "$hook" ] || continue
    if [ ! -x "$hook" ]; then
      chmod +x "$hook"
      log_step "Fixed: $(basename "$hook") made executable"
      fixed=$((fixed + 1))
    fi
  done

  # Fix missing Zone B structure
  local tier="$(json_get "$PROJECT_ROOT/.claude/harness/config.json" ".tier")"
  if [ "$(tier_to_level "$tier")" -ge 2 ]; then
    local state_dir="$PROJECT_ROOT/.claude/harness/state"
    mkdir -p "$state_dir/plans"

    for tmpl in progress.md learnings.md; do
      if [ ! -f "$state_dir/$tmpl" ]; then
        cp "$TOOLKIT_DIR/templates/zone-b/$tmpl" "$state_dir/$tmpl"
        log_step "Fixed: created state/$tmpl"
        fixed=$((fixed + 1))
      fi
    done
  fi

  log_info "Auto-fixed $fixed issue(s). Run \`harness check\` again to verify."
}
```

---

## Edge Cases

| Case | Handling |
|---|---|
| LLM unavailable for quality check | Skip quality validation, warn user |
| progress.md never updated (initial template) | Freshness check ignores template content — checks mtime only |
| config.json missing | Exit 3: "Harness not initialized" |
| Toolkit version mismatch | Warn but don't fail — suggest `harness update` |
| Scoped config listed but directory deleted | Error in structure check |
| Zone B files deleted by user | Structure check fails, --fix recreates from template |
| Very large rules file (>100 lines) | Quality check flags conciseness, suggests trim |
| Multiple v2 marker pairs in CLAUDE.md | Structure check fails — only 1 pair allowed |
