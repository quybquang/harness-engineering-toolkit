#!/bin/sh
# harness init — Full pipeline for new projects
# discover → classify → generate → write → validate

run_cmd_init() {
    log_info "━━━ Initializing harness ━━━"
    echo ""

    # Check if harness already exists
    if [ -f "$STATE_FILE" ]; then
        _existing_tier=$(json_get "$STATE_FILE" '.tier')
        log_warn "Harness already initialized (tier: $_existing_tier)"
        log_step "Use 'harness update' to refresh, or 'harness init --force' to reinitialize."
        if [ "$FLAG_FORCE" != true ]; then
            exit $EXIT_STATE_CONFLICT
        fi
        log_step "Force mode: reinitializing..."
    fi

    # Step 1: Discover
    log_info "[1/5] Discovering project..."
    run_discover

    # Step 2: Classify
    log_info "[2/5] Classifying project..."
    run_classify

    # Step 3: Generate
    log_info "[3/5] Generating harness content..."
    run_generate

    # Step 4: Write
    if [ "$FLAG_DRY_RUN" = true ]; then
        log_info "[4/5] Writing files (dry run)..."
    else
        log_info "[4/5] Writing files..."
    fi
    run_write

    # Step 5: Validate
    log_info "[5/5] Validating..."
    run_validate

    # Update state
    if [ "$FLAG_DRY_RUN" != true ]; then
        write_state
    fi

    # Summary
    echo ""
    log_info "━━━ Init complete ━━━"
    _tier=$(json_get "$CONFIG_FILE" '.tier')
    _pattern_count=$(json_get "$CONFIG_FILE" '.patterns | length')
    log_step "Tier: $_tier"
    log_step "Patterns: $_pattern_count"
    log_step "CLAUDE.md: $([ -f "$CLAUDE_MD" ] && echo 'updated' || echo 'created')"

    if [ "$FLAG_DRY_RUN" = true ]; then
        echo ""
        log_step "This was a dry run. No files were modified."
        log_step "Run 'harness init' without --dry-run to apply changes."
    fi
}

# ── Write state.json ─────────────────────────────────────────────────────────

write_state() {
    _timestamp=$(iso_timestamp)
    _tier=$(json_get "$CONFIG_FILE" '.tier')
    _patterns=$(json_get "$CONFIG_FILE" '.patterns')
    _context_hash=$(json_get "$CONTEXT_FILE" '.hash')

    ensure_dir "$HARNESS_DIR"

    cat > "$STATE_FILE" <<STEOF
{
    "version": "2.0",
    "toolkit_version": "${TOOLKIT_VERSION}",
    "initialized_at": "${_timestamp}",
    "last_updated": "${_timestamp}",
    "tier": "${_tier}",
    "patterns": ${_patterns},
    "context_hash": "${_context_hash}",
    "managed_files": {
        "claude_md": true,
        "hooks": $([ -f "$HOOKS_DIR/pre-command.sh" ] && echo 'true' || echo 'false'),
        "scoped_configs": $([ "$_tier" != "minimal" ] && echo 'true' || echo 'false'),
        "zone_b": $(tier_at_least "$_tier" "standard" && echo 'true' || echo 'false')
    },
    "managed_hooks": [
        {"event": "PreToolUse", "description": "[harness] Command risk classification"}$([ -f "$HOOKS_DIR/post-edit.sh" ] && printf ',\n        {"event": "PostToolUse", "description": "[harness] Auto-format after edit"}')
    ]
}
STEOF

    _tmp=$(mktemp)
    jq '.' "$STATE_FILE" > "$_tmp" && mv "$_tmp" "$STATE_FILE"

    log_verbose "State written to $STATE_FILE"
}
