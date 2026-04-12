#!/bin/sh
# harness update — Re-discover, diff, selective regenerate, merge, validate

run_cmd_update() {
    log_info "━━━ Updating harness ━━━"
    echo ""

    # Check if harness exists
    if [ ! -f "$STATE_FILE" ]; then
        log_warn "No existing harness found. Running init instead."
        run_cmd_init
        return
    fi

    _old_tier=$(json_get "$STATE_FILE" '.tier')
    _old_hash=$(json_get "$STATE_FILE" '.context_hash')

    # Step 1: Re-discover
    log_info "[1/5] Re-discovering project..."
    run_discover

    _new_hash=$(json_get "$CONTEXT_FILE" '.hash')

    # Check if anything changed
    if [ "$_old_hash" = "$_new_hash" ] && [ "$FLAG_FORCE" != true ]; then
        log_info "Project unchanged since last update."
        log_step "Hash: $_new_hash"
        log_step "Use --force to regenerate anyway."

        # Still run validate
        log_info "Running validation..."
        run_validate
        return
    fi

    log_step "Project changed (hash: ${_old_hash} → ${_new_hash})"

    # Step 2: Re-classify
    log_info "[2/5] Re-classifying..."
    run_classify

    _new_tier=$(json_get "$CONFIG_FILE" '.tier')

    if [ "$_old_tier" != "$_new_tier" ]; then
        log_step "Tier changed: $_old_tier → $_new_tier"
    else
        log_step "Tier unchanged: $_new_tier"
    fi

    # Step 3: Regenerate
    log_info "[3/5] Regenerating content..."
    run_generate

    # Step 4: Write (with backup)
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
        # Update state.json timestamps
        _timestamp=$(iso_timestamp)
        _tmp=$(mktemp)
        jq --arg ts "$_timestamp" --arg hash "$_new_hash" --arg tier "$_new_tier" --arg ver "$TOOLKIT_VERSION" \
            '.last_updated = $ts | .context_hash = $hash | .tier = $tier | .toolkit_version = $ver' \
            "$STATE_FILE" > "$_tmp" && mv "$_tmp" "$STATE_FILE"
        log_verbose "State updated"
    fi

    # Summary
    echo ""
    log_info "━━━ Update complete ━━━"
    log_step "Tier: $_new_tier"
    if [ "$_old_tier" != "$_new_tier" ]; then
        log_step "Tier changed from $_old_tier"
    fi

    if [ "$FLAG_DRY_RUN" = true ]; then
        echo ""
        log_step "This was a dry run. No files were modified."
    fi
}
