#!/bin/sh
# harness generate — Content generation engine
# Reads config.json → generates rules, hooks, map content, Zone B templates
# LLM-dependent steps output prompts for Claude Code context to process

# ── LLM Call Helper ──────────────────────────────────────────────────────────

# In Claude Code context: the slash command reads the prompt and processes it
# In standalone: output the prompt to a file for manual processing
prepare_llm_prompt() {
    _template="$1"
    _output="$2"
    _context="$CONTEXT_FILE"

    if [ ! -f "$_template" ]; then
        log_error "Template not found: $_template"
        return 1
    fi

    # Read template and substitute project context
    _prompt=$(cat "$_template")

    # Replace {{project_context_json}} with actual context
    _ctx=$(cat "$_context" | jq -c '.')
    _tmpfile=$(mktemp)
    _tmpl_tmp=$(mktemp)
    cat "$_template" > "$_tmpl_tmp"

    # Use jq-based substitution for safety (no sed escaping issues)
    _context_escaped=$(cat "$_context" | jq -c '.' | jq -Rs '.')
    printf '%s' "$_prompt" | sed "s|{{project_context_json}}|See attached context below.|g" > "$_tmpfile"
    printf '\n\n---\n## Project Context JSON\n```json\n' >> "$_tmpfile"
    cat "$_context" >> "$_tmpfile"
    printf '\n```\n' >> "$_tmpfile"

    ensure_dir "$(dirname "$_output")"
    mv "$_tmpfile" "$_output"
    rm -f "$_tmpl_tmp"
}

# ── Generators ───────────────────────────────────────────────────────────────

generate_conventions() {
    log_step "Generating conventions..."
    _prompt_file="${HARNESS_DIR}/.prompts/conventions-prompt.md"
    _output_file="${RULES_DIR}/conventions.md"

    prepare_llm_prompt \
        "$TOOLKIT_DIR/prompts/generate/conventions.md.tmpl" \
        "$_prompt_file"

    if [ "$IN_CLAUDE_CODE" = true ]; then
        # Claude Code will process the prompt via slash command
        log_verbose "Prompt ready: $_prompt_file"
    else
        # Standalone: create placeholder
        ensure_dir "$RULES_DIR"
        cat > "$_output_file" <<'PLACEHOLDER'
## Conventions

> This file needs LLM generation. Run `harness update` in Claude Code,
> or manually process the prompt in .claude/harness/.prompts/conventions-prompt.md
> and save the output here.

PLACEHOLDER
        log_warn "Conventions placeholder created — needs LLM generation"
    fi
}

generate_risk_rules() {
    log_step "Generating risk rules..."
    _prompt_file="${HARNESS_DIR}/.prompts/risk-rules-prompt.md"
    _output_file="${RULES_DIR}/risk-rules.md"

    prepare_llm_prompt \
        "$TOOLKIT_DIR/prompts/generate/risk-rules.md.tmpl" \
        "$_prompt_file"

    if [ "$IN_CLAUDE_CODE" != true ]; then
        ensure_dir "$RULES_DIR"
        cat > "$_output_file" <<'PLACEHOLDER'
## Risk Classification

> This file needs LLM generation. Run `harness update` in Claude Code,
> or manually process the prompt in .claude/harness/.prompts/risk-rules-prompt.md
> and save the output here.

### Safe
- `git status` — read-only
- `git diff` — read-only
- `npm test` / `pnpm test` — bounded side effects

### Risky
- `git push` — affects remote
- `npm publish` — public release

### Blocked
- `rm -rf /` — catastrophic
- `git push --force` — destructive to remote history

PLACEHOLDER
        log_warn "Risk rules created with defaults — needs LLM generation for project-specific rules"
    fi
}

generate_workflow() {
    log_step "Generating workflow..."
    _prompt_file="${HARNESS_DIR}/.prompts/workflow-prompt.md"
    _output_file="${RULES_DIR}/workflow.md"

    prepare_llm_prompt \
        "$TOOLKIT_DIR/prompts/generate/workflow.md.tmpl" \
        "$_prompt_file"

    if [ "$IN_CLAUDE_CODE" != true ]; then
        ensure_dir "$RULES_DIR"
        cat > "$_output_file" <<'PLACEHOLDER'
## Session Workflow

> This file needs LLM generation. Run `harness update` in Claude Code.

### 1. Orient
- Read CLAUDE.md and relevant rule files
- Check git status and recent changes

### 2. Plan
- Break task into steps
- Identify affected files and potential risks

### 3. Execute
- Follow conventions from rules/conventions.md
- Check risk classification before running commands

### 4. Verify
- Run tests
- Run linter

### 5. Document
- Update progress.md
- Log any discoveries in learnings.md

PLACEHOLDER
        log_warn "Workflow placeholder created — needs LLM generation"
    fi
}

generate_architecture() {
    log_step "Generating architecture notes..."
    _prompt_file="${HARNESS_DIR}/.prompts/architecture-prompt.md"
    _output_file="${RULES_DIR}/architecture.md"

    prepare_llm_prompt \
        "$TOOLKIT_DIR/prompts/generate/architecture.md.tmpl" \
        "$_prompt_file"

    if [ "$IN_CLAUDE_CODE" != true ]; then
        ensure_dir "$RULES_DIR"
        cat > "$_output_file" <<'PLACEHOLDER'
## Architecture Notes

> This file needs LLM generation. Run `harness update` in Claude Code.

PLACEHOLDER
        log_warn "Architecture placeholder created — needs LLM generation"
    fi
}

generate_critical_rules() {
    log_step "Extracting critical rules..."
    _prompt_file="${HARNESS_DIR}/.prompts/critical-rules-prompt.md"

    # This prompt needs the generated content as input
    _template="$TOOLKIT_DIR/prompts/generate/critical-rules.md.tmpl"
    _tmp_template=$(mktemp)
    cat "$_template" > "$_tmp_template"

    # Substitute generated content if available
    _conv_content=""
    [ -f "${RULES_DIR}/conventions.md" ] && _conv_content=$(cat "${RULES_DIR}/conventions.md")
    _risk_content=""
    [ -f "${RULES_DIR}/risk-rules.md" ] && _risk_content=$(cat "${RULES_DIR}/risk-rules.md")
    _wf_content=""
    [ -f "${RULES_DIR}/workflow.md" ] && _wf_content=$(cat "${RULES_DIR}/workflow.md")

    prepare_llm_prompt "$_template" "$_prompt_file"

    # Append actual generated content to prompt
    printf '\n\n---\n## Generated Conventions\n%s\n' "$_conv_content" >> "$_prompt_file"
    printf '\n---\n## Generated Risk Rules\n%s\n' "$_risk_content" >> "$_prompt_file"
    printf '\n---\n## Generated Workflow\n%s\n' "$_wf_content" >> "$_prompt_file"

    rm -f "$_tmp_template"

    # Default critical rules for standalone mode
    CRITICAL_RULES="1. Read the relevant rule files before modifying code.
2. Check risk classification before running any shell command.
3. Run tests after every code change."
}

# ── Hook Generation ──────────────────────────────────────────────────────────

generate_hooks() {
    log_step "Generating hook scripts..."

    ensure_dir "$HOOKS_DIR"

    # Pre-command hook — risk classifier
    cat > "$HOOKS_DIR/pre-command.sh" <<'HOOKEOF'
#!/bin/sh
# harness pre-command hook — Command risk classification
# Auto-generated. Regenerate with `harness update`.

COMMAND="$1"

# Extract the base command (first word)
BASE_CMD=$(printf '%s' "$COMMAND" | awk '{print $1}')

# ── Blocked commands (exit 1 to prevent execution) ──
case "$COMMAND" in
    *"rm -rf /"*|*"rm -rf /*"*)
        echo "[harness] BLOCKED: Catastrophic delete operation" >&2
        exit 1 ;;
    *"--force"*"push"*|*"push"*"--force"*|*"push -f"*)
        echo "[harness] BLOCKED: Force push. Use --force-with-lease instead." >&2
        exit 1 ;;
    *"drop database"*|*"DROP DATABASE"*)
        echo "[harness] BLOCKED: Database drop operation" >&2
        exit 1 ;;
    *"migrate reset"*|*"migrate:reset"*)
        echo "[harness] BLOCKED: Migration reset. This destroys all data." >&2
        exit 1 ;;
esac

# ── Risky commands (exit 2 to flag for confirmation) ──
case "$COMMAND" in
    *"git push"*)
        echo "[harness] RISKY: Pushing to remote" >&2
        exit 2 ;;
    *"npm publish"*|*"pnpm publish"*)
        echo "[harness] RISKY: Publishing package" >&2
        exit 2 ;;
    *"deploy"*|*"--prod"*)
        echo "[harness] RISKY: Production deployment" >&2
        exit 2 ;;
    *"git branch -D"*|*"git branch -d"*)
        echo "[harness] RISKY: Deleting branch" >&2
        exit 2 ;;
esac

# ── Safe: allow everything else ──
exit 0
HOOKEOF

    chmod +x "$HOOKS_DIR/pre-command.sh"

    # Post-edit hook — auto-format (only if formatter detected)
    _formatter=$(json_get "$CONTEXT_FILE" '.stack.formatter')
    if [ "$_formatter" != "null" ]; then
        cat > "$HOOKS_DIR/post-edit.sh" <<FMTEOF
#!/bin/sh
# harness post-edit hook — Auto-format on file change
# Auto-generated. Regenerate with \`harness update\`.

FILE="\$1"

# Only format known extensions
case "\$FILE" in
    *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.md)
        ;;
    *.py)
        ;;
    *.go)
        ;;
    *)
        exit 0 ;;
esac

# Format based on detected formatter
case "${_formatter}" in
    "prettier")
        npx prettier --write "\$FILE" 2>/dev/null ;;
    "biome")
        npx biome format --write "\$FILE" 2>/dev/null ;;
    "ruff")
        ruff format "\$FILE" 2>/dev/null ;;
    "black")
        black "\$FILE" 2>/dev/null ;;
    "gofmt")
        gofmt -w "\$FILE" 2>/dev/null ;;
    "rustfmt")
        rustfmt "\$FILE" 2>/dev/null ;;
esac

exit 0
FMTEOF
        chmod +x "$HOOKS_DIR/post-edit.sh"
    fi

    log_verbose "Hooks generated in $HOOKS_DIR"
}

# ── Map Assembly ─────────────────────────────────────────────────────────────

assemble_map() {
    log_step "Assembling CLAUDE.md map..."

    _project_name=$(json_get "$CONTEXT_FILE" '.project.name')
    _tier="$TIER"
    _languages=$(json_get "$CONTEXT_FILE" '.stack.languages | join(", ")')
    _frameworks=$(json_get "$CONTEXT_FILE" '.stack.frameworks | join(", ")')
    _pkg_manager=$(json_get "$CONTEXT_FILE" '.stack.package_manager')
    _deployment=$(json_get "$CONTEXT_FILE" '.infrastructure.deployment')

    _stack_line="${_languages}"
    [ -n "$_frameworks" ] && [ "$_frameworks" != "null" ] && _stack_line="${_stack_line} + ${_frameworks}"
    [ "$_pkg_manager" != "null" ] && _stack_line="${_stack_line} | ${_pkg_manager}"
    [ "$_deployment" != "null" ] && _stack_line="${_stack_line} → ${_deployment}"

    MAP_CONTENT="# ${_project_name}

**Stack**: ${_stack_line}
**Harness tier**: ${_tier}

## Rules
- [Conventions](.claude/harness/rules/conventions.md)
- [Risk Classification](.claude/harness/rules/risk-rules.md)"

    # Add tier-specific entries
    if tier_at_least "$_tier" "standard"; then
        MAP_CONTENT="${MAP_CONTENT}
- [Workflow](.claude/harness/rules/workflow.md)"
    fi
    if tier_at_least "$_tier" "full"; then
        MAP_CONTENT="${MAP_CONTENT}
- [Architecture](.claude/harness/rules/architecture.md)"
    fi

    # Zone B
    if tier_at_least "$_tier" "standard"; then
        MAP_CONTENT="${MAP_CONTENT}

## State (read before starting, update after finishing)
- [Session Progress](.claude/harness/state/progress.md)
- [Learnings](.claude/harness/state/learnings.md)"
    fi

    # Critical rules
    MAP_CONTENT="${MAP_CONTENT}

## Critical Rules
${CRITICAL_RULES}"

    # Save to temp file for write step
    _map_file="${HARNESS_DIR}/.map-content.md"
    ensure_dir "$HARNESS_DIR"
    printf '%s\n' "$MAP_CONTENT" > "$_map_file"

    log_verbose "Map content assembled ($(wc -l < "$_map_file" | tr -d ' ') lines)"
}

# ── Zone B Templates ─────────────────────────────────────────────────────────

generate_zone_b() {
    log_step "Setting up Zone B (state files)..."

    ensure_dir "$STATE_DIR"

    # Only create if not existing (never overwrite Zone B)
    if [ ! -f "$STATE_DIR/progress.md" ]; then
        cp "$TOOLKIT_DIR/templates/zone-b/progress.md" "$STATE_DIR/progress.md"
        log_verbose "Created progress.md"
    else
        log_verbose "progress.md exists, skipping"
    fi

    if [ ! -f "$STATE_DIR/learnings.md" ]; then
        cp "$TOOLKIT_DIR/templates/zone-b/learnings.md" "$STATE_DIR/learnings.md"
        log_verbose "Created learnings.md"
    else
        log_verbose "learnings.md exists, skipping"
    fi

    # Copy plan templates
    if [ ! -f "$STATE_DIR/_template-feature.md" ]; then
        cp "$TOOLKIT_DIR/templates/zone-b/_template-feature.md" "$STATE_DIR/_template-feature.md"
    fi
    if [ ! -f "$STATE_DIR/_template-bugfix.md" ]; then
        cp "$TOOLKIT_DIR/templates/zone-b/_template-bugfix.md" "$STATE_DIR/_template-bugfix.md"
    fi
}

# ── Selective Generate ───────────────────────────────────────────────────────

selective_generate() {
    log_step "Checking what needs regeneration..."

    _old_hash=""
    if [ -f "$CONFIG_FILE" ]; then
        _old_hash=$(json_get "$CONFIG_FILE" '.context_hash')
    fi
    _new_hash=$(json_get "$CONTEXT_FILE" '.hash')

    if [ "$_old_hash" = "$_new_hash" ] && [ "$FLAG_FORCE" != true ]; then
        log_info "Project context unchanged. Skipping generation."
        log_step "Use --force to regenerate anyway."
        return 1
    fi

    return 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

run_generate() {
    log_info "Generating harness content..."

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "No config.json found. Run 'harness classify' first."
        exit $EXIT_STATE_CONFLICT
    fi

    TIER=$(json_get "$CONFIG_FILE" '.tier')

    # Check if running inside Claude Code
    IN_CLAUDE_CODE=false
    if [ -n "$CLAUDE_CODE_SESSION" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
        IN_CLAUDE_CODE=true
    fi

    ensure_dir "$RULES_DIR"
    ensure_dir "${HARNESS_DIR}/.prompts"

    # Generate based on tier (cumulative)
    # Minimal: conventions + risk rules
    generate_conventions
    generate_risk_rules
    generate_hooks

    # Standard+: workflow + Zone B
    if tier_at_least "$TIER" "standard"; then
        generate_workflow
        generate_zone_b
    fi

    # Full+: architecture
    if tier_at_least "$TIER" "full"; then
        generate_architecture
    fi

    # Critical rules (always — uses generated content)
    generate_critical_rules

    # Assemble the map
    assemble_map

    _rule_count=$(ls -1 "$RULES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
    _hook_count=$(ls -1 "$HOOKS_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')
    log_step "Generated: ${_rule_count} rule file(s), ${_hook_count} hook(s)"

    if [ "$IN_CLAUDE_CODE" != true ]; then
        log_warn "Running outside Claude Code — LLM-generated files contain placeholders."
        log_step "Process prompts in .claude/harness/.prompts/ to complete generation."
    fi
}
