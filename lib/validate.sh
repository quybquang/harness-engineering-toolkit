#!/bin/sh
# harness validate — Structure validation + quality check
# Validates harness completeness, structure integrity, and optionally content quality

# ── Structure Checks ─────────────────────────────────────────────────────────

_pass=0
_warn=0
_fail=0

check_pass() {
    _pass=$((_pass + 1))
    log_step "PASS: $1"
}

check_warn() {
    _warn=$((_warn + 1))
    log_warn "WARN: $1"
}

check_fail() {
    _fail=$((_fail + 1))
    log_error "FAIL: $1"
}

validate_structure() {
    log_step "Validating structure..."

    # CLAUDE.md exists
    if [ -f "$CLAUDE_MD" ]; then
        check_pass "CLAUDE.md exists"
    else
        check_fail "CLAUDE.md not found"
    fi

    # CLAUDE.md has harness markers
    if has_v2_markers "$CLAUDE_MD"; then
        check_pass "CLAUDE.md has v2 harness markers"
    elif has_v1_markers "$CLAUDE_MD"; then
        check_warn "CLAUDE.md has v1 markers — run 'harness update' to migrate"
    elif [ -f "$CLAUDE_MD" ]; then
        check_warn "CLAUDE.md exists but has no harness markers"
    fi

    # .claude/harness/ directory
    if [ -d "$HARNESS_DIR" ]; then
        check_pass ".claude/harness/ directory exists"
    else
        check_fail ".claude/harness/ directory not found"
    fi

    # project-context.json
    if [ -f "$CONTEXT_FILE" ]; then
        check_pass "project-context.json exists"
        # Validate JSON
        if jq '.' "$CONTEXT_FILE" >/dev/null 2>&1; then
            check_pass "project-context.json is valid JSON"
        else
            check_fail "project-context.json is invalid JSON"
        fi
    else
        check_fail "project-context.json not found"
    fi

    # config.json
    if [ -f "$CONFIG_FILE" ]; then
        check_pass "config.json exists"
        if jq '.' "$CONFIG_FILE" >/dev/null 2>&1; then
            check_pass "config.json is valid JSON"
        else
            check_fail "config.json is invalid JSON"
        fi
    else
        check_fail "config.json not found"
    fi

    # state.json
    if [ -f "$STATE_FILE" ]; then
        check_pass "state.json exists"
    else
        check_warn "state.json not found — harness may not have been fully initialized"
    fi
}

# ── Rules Validation ─────────────────────────────────────────────────────────

validate_rules() {
    log_step "Validating rule files..."

    _tier="minimal"
    [ -f "$CONFIG_FILE" ] && _tier=$(json_get "$CONFIG_FILE" '.tier')

    # Conventions (always required)
    if [ -f "$RULES_DIR/conventions.md" ]; then
        _lines=$(wc -l < "$RULES_DIR/conventions.md" | tr -d ' ')
        if [ "$_lines" -gt 5 ]; then
            check_pass "conventions.md exists ($_lines lines)"
        else
            check_warn "conventions.md exists but seems too short ($_lines lines)"
        fi
        # Check for placeholder
        if grep -q "needs LLM generation" "$RULES_DIR/conventions.md" 2>/dev/null; then
            check_warn "conventions.md contains placeholder — needs LLM generation"
        fi
    else
        check_fail "conventions.md not found"
    fi

    # Risk rules (always required)
    if [ -f "$RULES_DIR/risk-rules.md" ]; then
        _lines=$(wc -l < "$RULES_DIR/risk-rules.md" | tr -d ' ')
        check_pass "risk-rules.md exists ($_lines lines)"
        if grep -q "needs LLM generation" "$RULES_DIR/risk-rules.md" 2>/dev/null; then
            check_warn "risk-rules.md contains placeholder — needs LLM generation"
        fi
    else
        check_fail "risk-rules.md not found"
    fi

    # Workflow (standard+)
    if tier_at_least "$_tier" "standard"; then
        if [ -f "$RULES_DIR/workflow.md" ]; then
            check_pass "workflow.md exists"
            if grep -q "needs LLM generation" "$RULES_DIR/workflow.md" 2>/dev/null; then
                check_warn "workflow.md contains placeholder — needs LLM generation"
            fi
        else
            check_warn "workflow.md not found (recommended for tier: $_tier)"
        fi
    fi

    # Architecture (full+)
    if tier_at_least "$_tier" "full"; then
        if [ -f "$RULES_DIR/architecture.md" ]; then
            check_pass "architecture.md exists"
        else
            check_warn "architecture.md not found (recommended for tier: $_tier)"
        fi
    fi
}

# ── Hooks Validation ─────────────────────────────────────────────────────────

validate_hooks() {
    log_step "Validating hooks..."

    # Hook scripts exist
    if [ -f "$HOOKS_DIR/pre-command.sh" ]; then
        check_pass "pre-command.sh hook exists"
        # Check executable
        if [ -x "$HOOKS_DIR/pre-command.sh" ]; then
            check_pass "pre-command.sh is executable"
        else
            check_fail "pre-command.sh is not executable"
        fi
    else
        check_warn "pre-command.sh hook not found"
    fi

    # Settings.json references
    _settings_file="$PROJECT_ROOT/.claude/settings.json"
    if [ -f "$_settings_file" ]; then
        if jq -e '.hooks' "$_settings_file" >/dev/null 2>&1; then
            check_pass "settings.json has hooks configuration"

            # Check that referenced scripts exist
            _hook_paths=$(jq -r '.hooks[][] | .hook[]? // .hook // empty' "$_settings_file" 2>/dev/null)
            for _hp in $_hook_paths; do
                if [ -f "$PROJECT_ROOT/$_hp" ]; then
                    check_pass "Hook script exists: $_hp"
                else
                    check_fail "Hook script missing: $_hp"
                fi
            done
        else
            check_warn "settings.json has no hooks configuration"
        fi
    fi
}

# ── Zone B Validation ────────────────────────────────────────────────────────

validate_zone_b() {
    _tier="minimal"
    [ -f "$CONFIG_FILE" ] && _tier=$(json_get "$CONFIG_FILE" '.tier')

    if ! tier_at_least "$_tier" "standard"; then
        return 0
    fi

    log_step "Validating Zone B (state files)..."

    if [ -d "$STATE_DIR" ]; then
        check_pass "state/ directory exists"
    else
        check_warn "state/ directory not found (recommended for tier: $_tier)"
        return 0
    fi

    if [ -f "$STATE_DIR/progress.md" ]; then
        check_pass "progress.md exists"
    else
        check_warn "progress.md not found"
    fi

    if [ -f "$STATE_DIR/learnings.md" ]; then
        check_pass "learnings.md exists"
    else
        check_warn "learnings.md not found"
    fi
}

# ── Context Freshness ────────────────────────────────────────────────────────

validate_freshness() {
    log_step "Checking freshness..."

    if [ ! -f "$CONTEXT_FILE" ]; then
        return 0
    fi

    _generated_at=$(json_get "$CONTEXT_FILE" '.generated_at')
    if [ -n "$_generated_at" ] && [ "$_generated_at" != "null" ]; then
        # Check if older than 30 days (rough check)
        _gen_date=$(printf '%s' "$_generated_at" | cut -c1-10)
        _today=$(date +%Y-%m-%d)

        if [ "$_gen_date" = "$_today" ]; then
            check_pass "Context generated today"
        else
            check_warn "Context generated on $_gen_date — consider running 'harness update'"
        fi
    fi

    # Check if context hash matches current state
    if [ -f "$STATE_FILE" ]; then
        _state_hash=$(json_get "$STATE_FILE" '.context_hash')
        _current_hash=$(json_get "$CONTEXT_FILE" '.hash')
        if [ "$_state_hash" = "$_current_hash" ]; then
            check_pass "Context hash matches state"
        else
            check_warn "Context hash mismatch — project may have changed since last init"
        fi
    fi
}

# ── Auto-fix ─────────────────────────────────────────────────────────────────

auto_fix() {
    log_step "Attempting auto-fix..."

    _fixed=0

    # Fix non-executable hook scripts
    for _script in "$HOOKS_DIR"/*.sh; do
        if [ -f "$_script" ] && [ ! -x "$_script" ]; then
            chmod +x "$_script"
            log_step "Fixed: made $_script executable"
            _fixed=$((_fixed + 1))
        fi
    done

    # Fix missing .harnessignore
    if [ ! -f "$PROJECT_ROOT/.harnessignore" ]; then
        . "$TOOLKIT_DIR/lib/write.sh"
        write_harnessignore
        log_step "Fixed: created .harnessignore"
        _fixed=$((_fixed + 1))
    fi

    # Migrate v1 markers to v2
    if has_v1_markers "$CLAUDE_MD" && ! has_v2_markers "$CLAUDE_MD"; then
        sed -i.bak \
            -e "s|<!-- HARNESS:START --|${MARKER_START_V2} — Auto-generated by harness-toolkit. Do not edit. -->|" \
            -e "s|<!-- HARNESS:END -->|${MARKER_END_V2}|" \
            "$CLAUDE_MD"
        rm -f "${CLAUDE_MD}.bak"
        log_step "Fixed: migrated CLAUDE.md markers from v1 to v2"
        _fixed=$((_fixed + 1))
    fi

    if [ "$_fixed" -gt 0 ]; then
        log_success "Auto-fixed $_fixed issue(s)"
    else
        log_step "Nothing to auto-fix"
    fi
}

# ── LLM Quality Review ──────────────────────────────────────────────────────

prepare_quality_review() {
    log_step "Preparing quality review prompt..."

    _prompt_file="${HARNESS_DIR}/.prompts/evaluator-prompt.md"
    ensure_dir "${HARNESS_DIR}/.prompts"

    # Collect all rule files content
    _all_content=""
    for _rf in "$RULES_DIR"/*.md; do
        if [ -f "$_rf" ]; then
            _fname=$(basename "$_rf")
            _all_content="${_all_content}
---
### File: ${_fname}
$(cat "$_rf")
"
        fi
    done

    # Prepare evaluator prompt
    prepare_llm_prompt \
        "$TOOLKIT_DIR/prompts/evaluator.md.tmpl" \
        "$_prompt_file"

    # Append actual content
    printf '\n\n---\n## Files Being Evaluated\n%s\n' "$_all_content" >> "$_prompt_file"

    log_step "Quality review prompt ready: $_prompt_file"
    log_step "Process this prompt in Claude Code for LLM quality assessment"
}

# ── Report ───────────────────────────────────────────────────────────────────

print_report() {
    _total=$((_pass + _warn + _fail))

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  Harness Validation Report\n"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "  PASS: %d  |  WARN: %d  |  FAIL: %d\n" "$_pass" "$_warn" "$_fail"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$_fail" -gt 0 ]; then
        log_error "Validation FAILED — $_fail critical issue(s) found"
        return 1
    elif [ "$_warn" -gt 0 ]; then
        log_warn "Validation PASSED with $_warn warning(s)"
        return 0
    else
        log_success "Validation PASSED — all checks OK"
        return 0
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────

run_validate() {
    log_info "Validating harness..."

    validate_structure
    validate_rules
    validate_hooks
    validate_zone_b
    validate_freshness

    if [ "$FLAG_FIX" = true ]; then
        auto_fix
    fi

    print_report
}
