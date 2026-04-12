#!/bin/sh
# harness eject — Remove toolkit management, give full ownership to user

run_cmd_eject() {
    log_info "━━━ Ejecting harness ━━━"
    echo ""

    if [ ! -d "$HARNESS_DIR" ]; then
        log_error "No harness found to eject."
        exit $EXIT_STATE_CONFLICT
    fi

    if [ "$FLAG_DRY_RUN" = true ]; then
        log_step "[dry-run] Would perform the following:"
        echo ""
    fi

    # Step 1: Inline CLAUDE.md markers — remove markers, keep content
    if [ -f "$CLAUDE_MD" ] && (has_v2_markers "$CLAUDE_MD" || has_v1_markers "$CLAUDE_MD"); then
        if [ "$FLAG_DRY_RUN" = true ]; then
            log_step "[dry-run] Remove HARNESS markers from CLAUDE.md (keep all content)"
        else
            log_step "Removing markers from CLAUDE.md..."
            _tmp=$(mktemp)
            # Remove only the marker lines, keep everything between them
            grep -v "^<!-- HARNESS:START" "$CLAUDE_MD" | grep -v "^<!-- HARNESS:END" > "$_tmp"
            mv "$_tmp" "$CLAUDE_MD"
            log_step "CLAUDE.md markers removed — content preserved"
        fi
    fi

    # Step 2: Remove scoped markers
    while IFS= read -r _scoped; do
        if [ -f "$_scoped" ] && [ "$_scoped" != "$CLAUDE_MD" ]; then
            if has_v2_markers "$_scoped" || has_v1_markers "$_scoped"; then
                _rel=$(printf '%s' "$_scoped" | sed "s|${PROJECT_ROOT}/||")
                if [ "$FLAG_DRY_RUN" = true ]; then
                    log_step "[dry-run] Remove markers from $_rel"
                else
                    _tmp=$(mktemp)
                    grep -v "^<!-- HARNESS:START" "$_scoped" | grep -v "^<!-- HARNESS:END" > "$_tmp"
                    mv "$_tmp" "$_scoped"
                    log_step "Markers removed from $_rel"
                fi
            fi
        fi
    done <<EOF
$(find "$PROJECT_ROOT" -name "CLAUDE.md" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)
EOF

    # Step 3: Copy rule files to project root (so they're accessible)
    if [ -d "$RULES_DIR" ]; then
        if [ "$FLAG_DRY_RUN" = true ]; then
            log_step "[dry-run] Would keep rule files in place at .claude/harness/rules/"
        else
            log_step "Rule files remain at .claude/harness/rules/"
        fi
    fi

    # Step 4: Remove harness metadata (but keep rules, hooks, state files)
    if [ "$FLAG_DRY_RUN" = true ]; then
        log_step "[dry-run] Would remove:"
        [ -f "$STATE_FILE" ] && log_step "  - .claude/harness/state.json"
        [ -f "$CONFIG_FILE" ] && log_step "  - .claude/harness/config.json"
        [ -f "$CONTEXT_FILE" ] && log_step "  - .claude/harness/project-context.json"
        [ -d "${HARNESS_DIR}/.prompts" ] && log_step "  - .claude/harness/.prompts/"
        [ -d "${HARNESS_DIR}/backup" ] && log_step "  - .claude/harness/backup/"
        [ -f "${HARNESS_DIR}/.map-content.md" ] && log_step "  - .claude/harness/.map-content.md"
    else
        # Remove toolkit metadata files
        rm -f "$STATE_FILE"
        rm -f "$CONFIG_FILE"
        rm -f "$CONTEXT_FILE"
        rm -f "${HARNESS_DIR}/.map-content.md"
        rm -rf "${HARNESS_DIR}/.prompts"
        rm -rf "${HARNESS_DIR}/backup"
        log_step "Toolkit metadata removed"
    fi

    # Step 5: Remove harness hook markers from settings.json
    _settings_file="$PROJECT_ROOT/.claude/settings.json"
    if [ -f "$_settings_file" ]; then
        if [ "$FLAG_DRY_RUN" = true ]; then
            log_step "[dry-run] Would remove [harness] hook entries from settings.json"
        else
            # Remove hooks with [harness] description
            _tmp=$(mktemp)
            jq 'walk(if type == "array" then [.[] | select(.description? | test("\\[harness\\]") | not)] else . end)' \
                "$_settings_file" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_settings_file"
            log_step "Harness hooks removed from settings.json"
        fi
    fi

    # Summary
    echo ""
    if [ "$FLAG_DRY_RUN" = true ]; then
        log_info "Dry run complete. No changes made."
        log_step "Run 'harness eject' without --dry-run to apply."
    else
        log_success "Eject complete."
        echo ""
        log_step "What was kept:"
        log_step "  - CLAUDE.md content (markers removed)"
        log_step "  - .claude/harness/rules/ (your rule files)"
        log_step "  - .claude/harness/hooks/ (your hook scripts)"
        log_step "  - .claude/harness/state/ (your state files)"
        echo ""
        log_step "What was removed:"
        log_step "  - Toolkit metadata (state.json, config.json, context.json)"
        log_step "  - Marker comments in CLAUDE.md"
        log_step "  - [harness] hooks from settings.json"
        echo ""
        log_step "You now own all files. The toolkit will not manage them."
        log_step "To reinitialize, run 'harness init --force'."
    fi
}
