#!/bin/sh
# harness check — Validate current harness without changes

run_cmd_check() {
    log_info "━━━ Checking harness ━━━"
    echo ""

    # Basic existence check
    if [ ! -d "$HARNESS_DIR" ]; then
        log_error "No harness found in this project."
        log_step "Run 'harness init' to set up harness."
        exit $EXIT_STATE_CONFLICT
    fi

    # Run validation
    run_validate

    # If --fix flag, fixes were already applied in validate

    # Show harness info
    echo ""
    log_step "─── Harness Info ───"

    if [ -f "$STATE_FILE" ]; then
        _tier=$(json_get "$STATE_FILE" '.tier')
        _version=$(json_get "$STATE_FILE" '.toolkit_version')
        _init_at=$(json_get "$STATE_FILE" '.initialized_at')
        _updated_at=$(json_get "$STATE_FILE" '.last_updated')
        _pattern_count=$(json_get "$STATE_FILE" '.patterns | length')

        log_step "Tier: $_tier"
        log_step "Patterns: $_pattern_count"
        log_step "Toolkit version: $_version"
        log_step "Initialized: $_init_at"
        log_step "Last updated: $_updated_at"
    else
        log_warn "state.json not found — harness may be partially initialized"
    fi

    # File inventory
    echo ""
    log_step "─── Files ───"

    _rule_count=0
    for _f in "$RULES_DIR"/*.md; do
        if [ -f "$_f" ]; then
            _rule_count=$((_rule_count + 1))
            _name=$(basename "$_f")
            _lines=$(wc -l < "$_f" | tr -d ' ')
            _placeholder=""
            grep -q "needs LLM generation" "$_f" 2>/dev/null && _placeholder=" (placeholder)"
            log_step "  rules/$_name — ${_lines} lines${_placeholder}"
        fi
    done

    _hook_count=0
    for _f in "$HOOKS_DIR"/*.sh; do
        if [ -f "$_f" ]; then
            _hook_count=$((_hook_count + 1))
            _name=$(basename "$_f")
            _exec=""
            [ -x "$_f" ] && _exec=" (executable)" || _exec=" (NOT executable!)"
            log_step "  hooks/$_name${_exec}"
        fi
    done

    log_step "Total: $_rule_count rule file(s), $_hook_count hook(s)"

    # Scoped configs
    _scoped_count=0
    while IFS= read -r _scoped; do
        if [ -f "$_scoped" ] && [ "$_scoped" != "$CLAUDE_MD" ]; then
            if has_v2_markers "$_scoped" || has_v1_markers "$_scoped"; then
                _scoped_count=$((_scoped_count + 1))
                _rel=$(printf '%s' "$_scoped" | sed "s|${PROJECT_ROOT}/||")
                log_step "  scoped: $_rel"
            fi
        fi
    done <<EOF
$(find "$PROJECT_ROOT" -name "CLAUDE.md" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
EOF

    if [ "$_scoped_count" -gt 0 ]; then
        log_step "Scoped configs: $_scoped_count"
    fi
}
