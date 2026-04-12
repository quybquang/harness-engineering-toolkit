#!/bin/sh
# harness classify — Tier classification engine
# Reads project-context.json → outputs config.json with tier + pattern list

# ── Scoring ──────────────────────────────────────────────────────────────────

score_tier() {
    log_step "Scoring complexity tier..."

    _score=0
    _signals=""

    # Read from context
    _containerized=$(json_get "$CONTEXT_FILE" '.infrastructure.containerized')
    _ci_cd=$(json_get "$CONTEXT_FILE" '.infrastructure.ci_cd')
    _deployment=$(json_get "$CONTEXT_FILE" '.infrastructure.deployment')
    _database=$(json_get "$CONTEXT_FILE" '.infrastructure.database')
    _shape_type=$(json_get "$CONTEXT_FILE" '.shape.type')
    _has_agents=$(json_get "$CONTEXT_FILE" '.ai_indicators.has_agents')
    _has_mcp=$(json_get "$CONTEXT_FILE" '.ai_indicators.has_mcp')
    _ai_sdk_count=$(json_get "$CONTEXT_FILE" '.ai_indicators.ai_sdk | length')
    _team_size=$(json_get "$CONTEXT_FILE" '.collaboration.team_size')
    _contributor_count=$(json_get "$CONTEXT_FILE" '.collaboration.contributor_count')
    _file_count=$(json_get "$CONTEXT_FILE" '.shape.estimated_file_count')
    _services_count=$(json_get "$CONTEXT_FILE" '.shape.services | length')
    _framework_count=$(json_get "$CONTEXT_FILE" '.stack.frameworks | length')

    # Containerization (+2)
    if [ "$_containerized" = "true" ]; then
        _score=$((_score + 2))
        _signals="${_signals}\"containerized\","
    fi

    # CI/CD (+2)
    if [ "$_ci_cd" != "null" ]; then
        _score=$((_score + 2))
        _signals="${_signals}\"ci_cd\","
    fi

    # Database (+1)
    if [ "$_database" != "null" ]; then
        _score=$((_score + 1))
        _signals="${_signals}\"database\","
    fi

    # AI agents (+3)
    if [ "$_has_agents" = "true" ]; then
        _score=$((_score + 3))
        _signals="${_signals}\"agents\","
    fi

    # MCP integration (+2)
    if [ "$_has_mcp" = "true" ]; then
        _score=$((_score + 2))
        _signals="${_signals}\"mcp\","
    fi

    # AI SDK (+1)
    if [ "$_ai_sdk_count" -gt 0 ] 2>/dev/null; then
        _score=$((_score + 1))
        _signals="${_signals}\"ai_sdk\","
    fi

    # Monorepo (+3)
    if [ "$_shape_type" = "monorepo" ]; then
        _score=$((_score + 3))
        _signals="${_signals}\"monorepo\","
    fi

    # Multi-service (+2)
    if [ "$_services_count" -gt 2 ] 2>/dev/null; then
        _score=$((_score + 2))
        _signals="${_signals}\"multi_service\","
    fi

    # Team size
    case "$_team_size" in
        "2-5")  _score=$((_score + 2)); _signals="${_signals}\"team_small\"," ;;
        "5+")   _score=$((_score + 4)); _signals="${_signals}\"team_large\"," ;;
    esac

    # Large codebase (+1)
    if [ "$_file_count" -gt 500 ] 2>/dev/null; then
        _score=$((_score + 1))
        _signals="${_signals}\"large_codebase\","
    fi

    _signals=$(printf '%s' "$_signals" | sed 's/,$//')

    # Score → tier mapping
    if [ "$_score" -le 2 ]; then
        TIER="minimal"
    elif [ "$_score" -le 6 ]; then
        TIER="standard"
    elif [ "$_score" -le 12 ]; then
        TIER="full"
    else
        TIER="enterprise"
    fi

    TIER_SCORE="$_score"
    TIER_SIGNALS="[${_signals}]"

    log_verbose "Score: $_score → Tier: $TIER"
    log_verbose "Signals: ${_signals}"
}

# ── Pattern Mapping ──────────────────────────────────────────────────────────

map_patterns() {
    log_step "Mapping patterns for tier: $TIER"

    # Cumulative — each tier includes all patterns from lower tiers
    case "$TIER" in
        minimal)
            PATTERNS='["persistent-instruction","lifecycle-hooks","command-risk-classification"]'
            ;;
        standard)
            PATTERNS='["persistent-instruction","lifecycle-hooks","command-risk-classification","scoped-context-assembly","explore-plan-act","single-purpose-tools"]'
            ;;
        full)
            PATTERNS='["persistent-instruction","lifecycle-hooks","command-risk-classification","scoped-context-assembly","explore-plan-act","single-purpose-tools","context-isolated-subagents","tiered-memory","progressive-tool-expansion"]'
            ;;
        enterprise)
            PATTERNS='["persistent-instruction","lifecycle-hooks","command-risk-classification","scoped-context-assembly","explore-plan-act","single-purpose-tools","context-isolated-subagents","tiered-memory","progressive-tool-expansion","fork-join-parallelism","dream-consolidation","progressive-context-compaction"]'
            ;;
    esac

    _pattern_count=$(printf '%s' "$PATTERNS" | jq 'length')
    log_step "Active patterns: $_pattern_count"
}

# ── Conflict Detection ───────────────────────────────────────────────────────

detect_conflicts() {
    log_step "Checking for signal conflicts..."

    CONFLICTS="[]"
    _has_conflicts=false

    _has_agents=$(json_get "$CONTEXT_FILE" '.ai_indicators.has_agents')
    _ai_sdk_count=$(json_get "$CONTEXT_FILE" '.ai_indicators.ai_sdk | length')
    _team_size=$(json_get "$CONTEXT_FILE" '.collaboration.team_size')
    _shape_type=$(json_get "$CONTEXT_FILE" '.shape.type')
    _test_fw=$(json_get "$CONTEXT_FILE" '.stack.test_framework')

    # Agents detected but no AI SDK
    if [ "$_has_agents" = "true" ] && [ "$_ai_sdk_count" -eq 0 ] 2>/dev/null; then
        CONFLICTS=$(printf '%s' "$CONFLICTS" | jq '. + ["agents_without_sdk: agents directory exists but no AI SDK dependency found"]')
        _has_conflicts=true
    fi

    # Monorepo but solo developer
    if [ "$_shape_type" = "monorepo" ] && [ "$_team_size" = "1" ]; then
        CONFLICTS=$(printf '%s' "$CONFLICTS" | jq '. + ["monorepo_solo: monorepo structure but single contributor — may be over-engineered or intentional"]')
        _has_conflicts=true
    fi

    # No test framework detected but non-minimal tier
    if [ "$_test_fw" = "null" ] && [ "$TIER" != "minimal" ]; then
        CONFLICTS=$(printf '%s' "$CONFLICTS" | jq '. + ["no_tests_at_scale: no test framework detected but project complexity suggests testing is needed"]')
        _has_conflicts=true
    fi

    if [ "$_has_conflicts" = true ]; then
        _count=$(printf '%s' "$CONFLICTS" | jq 'length')
        log_warn "Found $_count signal conflict(s) — may need LLM review"
    else
        log_verbose "No conflicts detected"
    fi
}

# ── LLM Fallback ─────────────────────────────────────────────────────────────

classify_with_llm() {
    # Only called when conflicts exist and need resolution
    # In Claude Code context: output the prompt for the LLM to evaluate
    # In standalone: skip with warning
    log_warn "LLM classification requested but not in Claude Code context"
    log_warn "Using rule-based classification. Run in Claude Code for LLM-assisted classification."
}

# ── Write Config ─────────────────────────────────────────────────────────────

write_config() {
    log_step "Writing config..."

    _timestamp=$(iso_timestamp)
    _context_hash=$(json_get "$CONTEXT_FILE" '.hash')

    ensure_dir "$HARNESS_DIR"

    cat > "$CONFIG_FILE" <<CFGEOF
{
    "version": "2.0",
    "toolkit_version": "${TOOLKIT_VERSION}",
    "generated_at": "${_timestamp}",
    "tier": "${TIER}",
    "tier_score": ${TIER_SCORE},
    "tier_signals": ${TIER_SIGNALS},
    "patterns": ${PATTERNS},
    "conflicts": ${CONFLICTS},
    "context_hash": "${_context_hash}"
}
CFGEOF

    # Pretty-print
    _tmp=$(mktemp)
    jq '.' "$CONFIG_FILE" > "$_tmp" && mv "$_tmp" "$CONFIG_FILE"

    log_verbose "Config written to $CONFIG_FILE"
}

# ── Main ─────────────────────────────────────────────────────────────────────

run_classify() {
    log_info "Classifying project..."

    if [ ! -f "$CONTEXT_FILE" ]; then
        log_error "No project-context.json found. Run 'harness discover' first."
        exit $EXIT_STATE_CONFLICT
    fi

    # Override tier if flag provided
    if [ -n "$FLAG_TIER" ]; then
        _level=$(tier_to_level "$FLAG_TIER")
        if [ "$_level" -eq 0 ]; then
            log_error "Invalid tier: $FLAG_TIER (expected: minimal|standard|full|enterprise)"
            exit $EXIT_INPUT_ERROR
        fi
        TIER="$FLAG_TIER"
        TIER_SCORE=0
        TIER_SIGNALS='["user_override"]'
        log_step "Tier overridden to: $TIER"
    else
        score_tier
    fi

    map_patterns
    detect_conflicts

    # If conflicts and not forced, consider LLM review
    _conflict_count=$(printf '%s' "$CONFLICTS" | jq 'length')
    if [ "$_conflict_count" -gt 0 ] && [ "$FLAG_FORCE" != true ]; then
        log_warn "Conflicts detected. Proceeding with rule-based tier: $TIER"
        log_step "Use --force to skip conflict warnings, or run in Claude Code for LLM review"
    fi

    write_config

    log_step "Tier: ${TIER} (score: ${TIER_SCORE})"
}
