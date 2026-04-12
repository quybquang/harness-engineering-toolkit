# Spec: Classify Step — v2

---

## Overview

**File**: `lib/classify.sh`
**Input**: `.claude/harness/project-context.json`
**Output**: Tier name + pattern list → written to `.claude/harness/config.json`
**Executor**: Shell script (primary) + LLM (fallback for ambiguity)
**Changes from v1**: `state.json` renamed to `config.json`. Pattern list updated to 15 patterns. Tier mapping includes 3 new patterns: `session-protocol`, `living-state`, `generator-evaluator`.

---

## Tier Decision Tree

```bash
classify_tier() {
  local context="$1"
  local tier="minimal"
  local reason=""

  # --- Check for forced tier ---
  if [ -n "$HARNESS_FLAG_TIER" ]; then
    tier="$HARNESS_FLAG_TIER"
    reason="forced via --tier flag"
    output_classification "$tier" "$reason"
    return
  fi

  # --- Rule-based classification ---
  local containerized="$(json_get "$context" ".infrastructure.containerized")"
  local ci_cd="$(json_get "$context" ".infrastructure.ci_cd")"
  local has_agents="$(json_get "$context" ".ai_indicators.has_agents")"
  local service_count="$(json_get "$context" ".shape.services | length")"
  local autonomous="$(json_get "$context" ".user_answers.autonomous_agents // false")"
  local team_size="$(json_get "$context" ".collaboration.team_size")"
  local project_type="$(json_get "$context" ".shape.type")"

  # Minimal → Standard
  if [ "$containerized" = "true" ] || [ "$ci_cd" != "none" ]; then
    tier="standard"
    reason="containerized=$containerized, ci_cd=$ci_cd"
  fi

  # Standard → Full
  if [ "$has_agents" = "true" ] || [ "$service_count" -gt 1 ] 2>/dev/null || [ "$autonomous" = "true" ]; then
    tier="full"
    reason="has_agents=$has_agents, services=$service_count, autonomous=$autonomous"
  fi

  # Full → Enterprise
  if [ "$team_size" = "2-5" ] || [ "$team_size" = "5+" ] || [ "$project_type" = "monorepo" ]; then
    tier="enterprise"
    reason="team_size=$team_size, type=$project_type"
  fi

  # --- Conflict detection ---
  local conflicts=""
  
  # Conflict: monorepo but solo developer
  if [ "$project_type" = "monorepo" ] && [ "$team_size" = "1" ]; then
    conflicts="monorepo with single developer"
  fi

  # Conflict: agents directory exists but no AI SDK found
  if [ -d "$PROJECT_ROOT/agents" ] && [ "$(json_get "$context" ".ai_indicators.ai_sdk | length")" = "0" ]; then
    conflicts="$conflicts${conflicts:+; }agents/ directory exists but no AI SDK imports found"
  fi

  # Conflict: no tests but complex project
  if [ -z "$(json_get "$context" ".stack.test_framework")" ] && [ "$tier" != "minimal" ]; then
    conflicts="$conflicts${conflicts:+; }no test framework detected for $tier-tier project"
  fi

  # --- LLM fallback if conflicts ---
  if [ -n "$conflicts" ]; then
    log_warn "Ambiguous signals detected: $conflicts"
    tier="$(classify_with_llm "$context" "$tier" "$conflicts")"
    reason="LLM resolved conflicts: $conflicts"
  fi

  output_classification "$tier" "$reason"
}
```

---

## Pattern Mapping — v2 (15 patterns)

```bash
get_patterns_for_tier() {
  local tier="$1"

  case "$tier" in
    minimal)
      echo "persistent-instruction lifecycle-hooks risk-classification"
      ;;
    standard)
      echo "persistent-instruction lifecycle-hooks risk-classification scoped-context explore-plan-act session-protocol living-state single-purpose-tools"
      ;;
    full)
      echo "persistent-instruction lifecycle-hooks risk-classification scoped-context explore-plan-act session-protocol living-state single-purpose-tools tiered-memory context-compaction context-isolated-subagents generator-evaluator"
      ;;
    enterprise)
      echo "persistent-instruction lifecycle-hooks risk-classification scoped-context explore-plan-act session-protocol living-state single-purpose-tools tiered-memory context-compaction context-isolated-subagents generator-evaluator progressive-tool-expansion dream-consolidation fork-join-parallelism"
      ;;
  esac
}
```

### v2 Pattern → Tier Reference

| Tier | Patterns (cumulative) |
|---|---|
| Minimal (3) | persistent-instruction (map format), lifecycle-hooks, risk-classification |
| Standard (8) | + scoped-context, explore-plan-act (with session protocol), session-protocol, living-state, single-purpose-tools |
| Full (12) | + tiered-memory, context-compaction, context-isolated-subagents, generator-evaluator |
| Enterprise (15) | + progressive-tool-expansion, dream-consolidation, fork-join-parallelism |

---

## LLM Fallback — Ambiguous Classification

### When triggered

Only when `classify_tier()` detects conflicting signals. Not for every run.

### Prompt template: `prompts/classify-ambiguous.md.tmpl`

```markdown
You are classifying a software project into a complexity tier for AI agent harness setup.

## Tiers (from simplest to most complex)
- **minimal**: Simple project. Needs: CLAUDE.md map + basic hooks + risk rules.
- **standard**: Has CI/CD or containers. Adds: scoped configs, session protocol, living state (progress/plans), Explore-Plan-Act workflow.
- **full**: Has AI agents or multiple services. Adds: tiered memory, generator-evaluator loop, subagent templates.
- **enterprise**: Team project or large monorepo. Adds: dream consolidation, fork-join parallelism, progressive tool expansion.

## Project Context
```json
{{project_context_json}}
```

## Conflicting Signals
{{conflicts}}

## Current rule-based classification: {{current_tier}}

## Your Task
Decide the correct tier. Consider:
1. The HIGHER tier is only justified if the project genuinely needs those patterns.
2. A monorepo with 1 developer usually doesn't need enterprise-level harness.
3. An agents/ directory without AI SDK imports might just be a naming convention.

Respond with ONLY a JSON object:
```json
{
  "tier": "<minimal|standard|full|enterprise>",
  "reasoning": "<one sentence explaining why>"
}
```
```

### LLM call handling

```bash
classify_with_llm() {
  local context_file="$1"
  local current_tier="$2"
  local conflicts="$3"

  local prompt_file="$TOOLKIT_DIR/prompts/classify-ambiguous.md.tmpl"
  local context_json="$(cat "$context_file")"

  local prompt="$(cat "$prompt_file")"
  prompt="$(echo "$prompt" | sed "s|{{project_context_json}}|$context_json|")"
  prompt="$(echo "$prompt" | sed "s|{{conflicts}}|$conflicts|")"
  prompt="$(echo "$prompt" | sed "s|{{current_tier}}|$current_tier|")"

  local response="$(call_llm "$prompt")"

  local tier="$(echo "$response" | jq -r '.tier')"
  local reasoning="$(echo "$response" | jq -r '.reasoning')"

  case "$tier" in
    minimal|standard|full|enterprise)
      log_info "LLM classified as: $tier ($reasoning)"
      echo "$tier"
      ;;
    *)
      log_warn "LLM returned invalid tier '$tier', falling back to $current_tier"
      echo "$current_tier"
      ;;
  esac
}
```

---

## Output — Config Initialization

Renamed from `state.json` to `config.json` in v2 to reflect its role as toolkit metadata (not agent state).

```bash
output_classification() {
  local tier="$1"
  local reason="$2"
  local patterns="$(get_patterns_for_tier "$tier")"
  local config_file="$PROJECT_ROOT/.claude/harness/config.json"

  log_info "Tier: $tier ($reason)"
  log_step "Patterns: $(echo $patterns | tr ' ' ', ')"

  jq -n \
    --arg toolkit_version "$TOOLKIT_VERSION" \
    --arg tier "$tier" \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg hash "$(json_get "$PROJECT_ROOT/.claude/harness/project-context.json" ".hash")" \
    --arg reason "$reason" \
    '{
      toolkit_version: $toolkit_version,
      min_compatible_version: $toolkit_version,
      generated_at: $generated_at,
      tier: $tier,
      classification_reason: $reason,
      patterns: ($ARGS.positional),
      project_context_hash: $hash,
      scoped_configs: [],
      managed_hooks: [],
      backup_history: []
    }' --args $patterns > "$config_file"
}
```

---

## Tier Transition (for `harness update`)

```bash
handle_tier_transition() {
  local old_tier="$1"
  local new_tier="$2"

  if [ "$old_tier" = "$new_tier" ]; then
    log_step "Tier unchanged: $new_tier"
    return
  fi

  local old_level="$(tier_to_level "$old_tier")"
  local new_level="$(tier_to_level "$new_tier")"

  if [ "$new_level" -gt "$old_level" ]; then
    log_warn "Tier UPGRADED: $old_tier → $new_tier (new patterns will be added)"
  else
    log_warn "Tier DOWNGRADED: $old_tier → $new_tier (some patterns may become orphaned)"
    log_step "Orphaned patterns will remain but won't be regenerated"
    log_step "Run 'harness eject' then 'harness init' for a clean re-initialization"
  fi
}

tier_to_level() {
  case "$1" in
    minimal)    echo 1 ;;
    standard)   echo 2 ;;
    full)       echo 3 ;;
    enterprise) echo 4 ;;
  esac
}
```

---

## Edge Cases

| Case | Handling |
|---|---|
| All signals point to minimal | No conflict, no LLM. Output minimal immediately |
| --tier flag provided | Skip all classification, use forced tier |
| LLM timeout | Warn + fall back to rule-based tier |
| LLM returns garbage | Validate JSON + tier value. Fall back to rule-based |
| Tier downgrade on update | Warn user. Don't remove old patterns. Suggest eject + re-init for clean state |
| New patterns added mid-tier | Pattern list comes from toolkit's mapping. If toolkit updates mapping, update will pick up new patterns |
