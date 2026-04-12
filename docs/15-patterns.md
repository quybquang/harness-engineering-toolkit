# 15 Harness Patterns — v2 Reference

---

## Definition

**Harness Engineering** = Designing the orchestration layer that controls how AI agents interact with context, tools, workflows, and automation.

Agent = the brain. Harness = the nervous system.

---

## v2 Updates

3 new patterns added from v1 (12 patterns):
- **Living State** (Memory group) — agent-writable progress/plans/learnings
- **Session Protocol** (Workflow group) — formalized session lifecycle
- **Generator-Evaluator Loop** (Automation group) — quality gate for generated content

---

## Group 1: Memory & Context (6 patterns)

### 1. Persistent Instruction File
- **Mechanism**: Project-level config file (CLAUDE.md) auto-loaded into every session
- **v2**: CLAUDE.md is a **map** (~20 lines) that points to rules files, not a monolith
- **Solves**: Agent forgets conventions, needs reminding every session
- **Tier**: Minimal (always)

### 2. Scoped Context Assembly
- **Mechanism**: Load instructions from nested scopes: `org → user → parent dir → current dir`
- **v2**: Each scoped CLAUDE.md uses same v2 marker format
- **Solves**: Large project with different rules per module
- **Tier**: Standard+

### 3. Tiered Memory
- **Mechanism**: Memory in 3 layers:
  - L1 (in-context): CLAUDE.md map, always present (~20 lines)
  - L2 (on-demand): Rules files in `.claude/harness/rules/`, read when needed
  - L3 (cold): Git history, conversation logs
- **v2**: L1 is explicitly the map. L2 is the rules directory
- **Solves**: Token waste, context window overflow
- **Tier**: Full+

### 4. Dream Consolidation
- **Mechanism**: Background process evaluates, deduplicates, prunes memory
- **Solves**: Memory bloat over time
- **Tier**: Enterprise

### 5. Progressive Context Compaction
- **Mechanism**: Compress information by age: recent=full, old=summarized, very old=compressed
- **Solves**: Long conversations losing context
- **Tier**: Full+

### 6. Living State (NEW in v2)
- **Mechanism**: Agent-writable files in Zone B:
  - `state/progress.md` — what's done, what's next, known issues
  - `state/learnings.md` — discoveries and gotchas found during work
  - `state/plans/*.md` — structured work plans (feature, bugfix templates)
- **Solves**: Session continuity — next session picks up where the last one left off
- **Tier**: Standard+

---

## Group 2: Workflow & Orchestration (4 patterns)

### 7. Explore-Plan-Act Loop
- **Mechanism**: 3 phases with different permissions:
  1. Explore: read-only tools
  2. Plan: read-only + discussion, no modifications
  3. Act: full tool access
- **v2**: Concrete session protocol file replaces generic instructions
- **Solves**: Agent rushes to modify code without understanding context
- **Tier**: Standard+

### 8. Context-Isolated Subagents
- **Mechanism**: Each subagent has its own context, prompt, and tool set. No session sharing.
- **Solves**: Context pollution between agents
- **Tier**: Full+

### 9. Fork-Join Parallelism
- **Mechanism**: Fork N subagents in isolated environments (git worktree), merge results
- **Solves**: Sequential execution too slow for independent tasks
- **Tier**: Enterprise

### 10. Session Protocol (NEW in v2)
- **Mechanism**: Formalized 5-step session lifecycle:
  1. **Orient** — read progress, check for broken state
  2. **Plan** — create or resume work plan
  3. **Execute** — incremental changes with testing
  4. **Verify** — full checks before committing
  5. **Wrap Up** — update progress, commit, note learnings
- **Solves**: Sessions without structure drift and lose context
- **Tier**: Standard+

---

## Group 3: Tools & Permissions (3 patterns)

### 11. Progressive Tool Expansion
- **Mechanism**: Default toolset < 20 tools → add more as task requires
- **Solves**: Too many tools confuse the model
- **Tier**: Enterprise

### 12. Command Risk Classification
- **Mechanism**: Classify every command before execution: safe, risky, blocked
- **v2**: Machine-parseable risk-rules.md feeds into auto-generated hooks
- **Solves**: Destructive commands without human oversight
- **Tier**: Minimal (always)

### 13. Single-Purpose Tool Design
- **Mechanism**: Replace general-purpose tools (bash + cat/sed/grep) with specialized tools
- **Solves**: General shell too broad, hard to validate input
- **Tier**: Minimal (always)

---

## Group 4: Automation (2 patterns)

### 14. Deterministic Lifecycle Hooks
- **Mechanism**: Hook into lifecycle events via code, not prompts:
  - Start → load env, validate config
  - ToolUse → pre/post hooks (risk classifier, formatter)
  - CwdChange → reload context
- **v2**: Hooks auto-generated from risk-rules.md, managed by toolkit
- **Solves**: Agent forgetting procedural steps
- **Tier**: Minimal (always)

### 15. Generator-Evaluator Loop (NEW in v2)
- **Mechanism**: Generated content passes through evaluator checking:
  - **Specificity** — is it specific to this project?
  - **Discoverability** — can agent find this from code?
  - **Actionability** — can agent follow mechanically?
  - **Conciseness** — under 40 lines?
- Failed content is re-generated with feedback (max 2 iterations)
- **Solves**: Generated conventions being too generic, bloated, or obvious
- **Tier**: Full+

---

## Summary Table

| # | Pattern | Group | Tier | Problem Solved |
|---|---|---|---|---|
| 1 | Persistent Instruction File | Memory | Minimal | Agent forgets conventions |
| 2 | Scoped Context Assembly | Memory | Standard | Multi-module rule conflicts |
| 3 | Tiered Memory | Memory | Full | Context window overflow |
| 4 | Dream Consolidation | Memory | Enterprise | Memory bloat over time |
| 5 | Progressive Context Compaction | Memory | Full | Long conversations cut off |
| 6 | **Living State** | Memory | Standard | **Session continuity** |
| 7 | Explore-Plan-Act Loop | Workflow | Standard | Agent rushes before understanding |
| 8 | Context-Isolated Subagents | Workflow | Full | Context pollution |
| 9 | Fork-Join Parallelism | Workflow | Enterprise | Sequential execution bottleneck |
| 10 | **Session Protocol** | Workflow | Standard | **Sessions without structure** |
| 11 | Progressive Tool Expansion | Tools | Enterprise | Model confused by too many tools |
| 12 | Command Risk Classification | Tools | Minimal | Destructive commands uncontrolled |
| 13 | Single-Purpose Tool Design | Tools | Minimal | General shell too broad |
| 14 | Deterministic Lifecycle Hooks | Automation | Minimal | Agent forgets procedural steps |
| 15 | **Generator-Evaluator Loop** | Automation | Full | **Generated content too generic** |

---

## Tier → Pattern Mapping

| Tier | Patterns (cumulative) | Count |
|---|---|---|
| Minimal | 1, 12, 13, 14 | 4 |
| Standard | + 2, 6, 7, 10 | 8 |
| Full | + 3, 5, 8, 15 | 12 |
| Enterprise | + 4, 9, 11 | 15 |
