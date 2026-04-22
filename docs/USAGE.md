# Harness Engineering Toolkit — Usage Guide

## Table of Contents

1. [What Is Harness Engineering?](#1-what-is-harness-engineering)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Quick Start](#4-quick-start)
5. [Core Concepts](#5-core-concepts)
   - [Pipeline](#pipeline)
   - [Complexity Tiers](#complexity-tiers)
   - [Two Zones](#two-zones)
   - [CLAUDE.md as a Map](#claudemd-as-a-map)
6. [Commands Reference](#6-commands-reference)
   - [harness init](#harness-init)
   - [harness update](#harness-update)
   - [harness check](#harness-check)
   - [harness eject](#harness-eject)
7. [Flags Reference](#7-flags-reference)
8. [Generated Output](#8-generated-output)
9. [15 Harness Patterns](#9-15-harness-patterns)
10. [Scoring & Tier Classification](#10-scoring--tier-classification)
11. [Git & Team Usage](#11-git--team-usage)
12. [Troubleshooting](#12-troubleshooting)
13. [FAQ](#13-faq)

---

## 1. What Is Harness Engineering?

**Harness Engineering** is the practice of designing the orchestration layer around an AI agent — the environment that controls what the agent sees, what it can do, and how it works.

```
Agent = brain
Harness = nervous system
```

Without a harness, an agent runs "naked":
- Doesn't know the project uses `pnpm` instead of `npm`
- Doesn't know which commands are dangerous
- Has no memory between sessions
- Needs full context re-briefing every time

The harness solves this by **encoding knowledge into the environment**, instead of relying on context-window re-injection each session.

### Four Pillars

| Pillar | What it controls | Example |
|---|---|---|
| **Context** | What the agent sees | `CLAUDE.md`, `conventions.md`, `architecture.md` |
| **Permissions** | What the agent can do | `risk-rules.md`, pre-command hooks |
| **Workflow** | How the agent works | `workflow.md`, session protocol |
| **Automation** | Where the system intervenes deterministically | Shell hooks (pre/post tool-use) |

### Core Principle

```
LLM generates content → Shell script writes files
```

The LLM never touches the filesystem directly. Scripts are the sole writers — deterministic, safe, auditable.

---

## 2. Requirements

| Dependency | Install | Purpose |
|---|---|---|
| `jq` | `brew install jq` / `apt install jq` | JSON processing throughout |
| `git` | pre-installed on most systems | Contributor detection |
| `sh` (POSIX) | built-in | All scripts are POSIX-compatible |
| Claude Code | [claude.ai/code](https://claude.ai/code) | LLM steps (generate, quality validate) |

---

## 3. Installation

```bash
# 1. Clone the repository
git clone <repo-url> ~/tools/harness-engineering-toolkit
cd ~/tools/harness-engineering-toolkit

# 2. Run installer
./install.sh
```

The installer does two things:

1. **Symlinks the CLI** to `~/.local/bin/harness`
2. **Installs slash commands** to `~/.claude/commands/` (if Claude Code is present)

### PATH setup

If `~/.local/bin` is not in your PATH, add this to `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload:

```bash
source ~/.zshrc
```

### Verify installation

```bash
harness version
# → harness-toolkit v0.1.0
```

### Uninstall

```bash
./uninstall.sh
```

---

## 4. Quick Start

```bash
# Go to any project
cd ~/my-project

# Preview what would be generated (safe — no file writes)
harness init --dry-run

# Initialize harness
harness init

# Check health
harness check

# After project changes
harness update

# Full ownership (opt out of toolkit management)
harness eject
```

### In Claude Code

After installation, slash commands are available in any Claude Code session:

```
/harness-init      Initialize with LLM assistance
/harness-update    Update with LLM assistance
/harness-check     Validate harness health
/harness-eject     Eject from toolkit management
```

---

## 5. Core Concepts

### Pipeline

Every `harness init` runs a 5-step pipeline:

```
[1] Discover → [2] Classify → [3] Generate → [4] Write → [5] Validate
  (script)       (script)       (LLM)         (script)    (script+LLM)
```

| Step | Executor | Input | Output |
|---|---|---|---|
| **Discover** | Shell script | Filesystem scan + optional Q&A | `project-context.json` |
| **Classify** | Shell (scoring) | `project-context.json` | Tier + pattern list → `config.json` |
| **Generate** | LLM (Claude) | Context + prompt templates | `conventions.md`, `risk-rules.md`, hooks, etc. |
| **Write** | Shell script | Generated content | Files in `.claude/harness/` + `CLAUDE.md` |
| **Validate** | Shell + LLM | Current harness state | Pass / warn / fail report |

### Complexity Tiers

The classify step assigns a **tier** based on detected signals (score-based):

| Tier | Score | Triggers | Pattern Count | What gets generated |
|---|---|---|---|---|
| `minimal` | 0–2 | Any project | 4 | CLAUDE.md + conventions + risk-rules + hooks |
| `standard` | 3–5 | Docker, CI/CD, database | 8 | + workflow + Zone B state |
| `full` | 6–12 | AI agents, MCP, multi-service | 12 | + architecture + evaluator quality loop |
| `enterprise` | 13+ | Large team (5+), monorepo | 15 | + dream consolidation + fork-join templates |

**Score signals:**

| Signal | Points |
|---|---|
| Containerized (Docker) | +2 |
| CI/CD detected | +2 |
| Database detected | +1 |
| AI agents | +3 |
| MCP integration | +2 |
| AI SDK dependency | +1 |
| Monorepo (Turbo/Lerna/Nx) | +3 |
| Multi-service (>2) | +2 |
| Team 2–5 | +2 |
| Team 5+ | +4 |
| Large codebase (>500 files) | +1 |

Override tier manually:

```bash
harness init --tier=full
```

### Two Zones

The generated `.claude/harness/` directory has two zones with different ownership:

```
.claude/harness/
├── rules/          ← Zone A: TOOLKIT-owned. Overwritten on update.
├── hooks/          ← Zone A: TOOLKIT-owned. Overwritten on update.
├── config.json     ← Zone A: TOOLKIT-owned.
├── state/          ← Zone B: AGENT-owned. Created once, NEVER overwritten.
│   ├── progress.md
│   ├── learnings.md
│   └── plans/
└── backup/         ← Auto-backups (last 5 kept)
```

**Zone A** — Toolkit manages. Updated every `harness update`. No manual edits (they will be overwritten).

**Zone B** — AI agent manages. The toolkit creates these from templates on first init and never touches them again. The agent reads and writes `progress.md`, `learnings.md`, and plan files across sessions.

### CLAUDE.md as a Map

`CLAUDE.md` is a **map** (~20 lines), not a manual. It fits in L1 context and points to detail files.

```markdown
<!-- HARNESS:START v2 — Auto-generated by harness-toolkit v0.1.0. Do not edit. -->

# Harness · my-project · standard tier

TypeScript · Next.js 15 · pnpm · Vitest · Vercel

## Rules
- Read `.claude/harness/rules/conventions.md` before writing code
- Read `.claude/harness/rules/risk-rules.md` before running commands
- Follow session protocol in `.claude/harness/rules/workflow.md`

## State
- `.claude/harness/state/progress.md` — read at start, update at end
- `.claude/harness/state/plans/` — active work plans

## Critical
- Use `pnpm`, never `npm` or `yarn`
- Run `pnpm check` before committing

<!-- HARNESS:END v2 -->
```

Content **outside** the markers is user-owned and never touched.

---

## 6. Commands Reference

### harness init

Full pipeline for new projects: `discover → classify → generate → write → validate`

```bash
harness init [flags]
```

**Behavior:**
- Exits with error if already initialized (use `--force` to override)
- Asks 2–3 questions only when signals are ambiguous
- Use `--skip-questions` to suppress all prompts

**Example output:**
```
[harness] ━━━ Initializing harness ━━━
[harness] Discovering project...
  → Detected: TypeScript, Next.js 15, pnpm
  → Detected: GitHub Actions CI, Vercel deployment
  → AI indicators: @ai-sdk/anthropic found
[harness] Classifying project...
  → Tier: full (score: 7)
  → Patterns: 12 active
[harness] Generating harness content...
  → rules/conventions.md ✓
  → rules/risk-rules.md ✓
  → rules/architecture.md ✓
[harness] Writing files...
  → CLAUDE.md created (v2 map, 19 lines)
  → .claude/harness/rules/ ✓
  → .claude/harness/hooks/ ✓
[harness] Validating...
  → All checks passed

[harness] ✓ Initialized (tier: full, 12 patterns)
```

---

### harness update

Re-discovers the project, detects changes, and selectively regenerates stale content.

```bash
harness update [flags]
```

**Behavior:**
- Exits with error if not initialized
- Compares current project state with stored context hash
- Only regenerates what has changed (unless `--force`)
- **Never overwrites Zone B files** (`state/`)
- Creates a backup before any writes

**When to run:**
- After adding a new dependency or service
- After switching package manager, framework, or deployment target
- After the team grows beyond a tier boundary

---

### harness check

Validates the current harness without modifying anything. Safe to run at any time.

```bash
harness check [--fix] [--verbose]
```

**Four validation levels:**

| Level | Tier | Checks |
|---|---|---|
| Structure | All | Files exist, markers valid, hooks executable, settings.json registered |
| Consistency | All | Context hash, file modification times vs discovery time |
| Freshness | Standard+ | `progress.md` age, orphaned plans (in-progress >14 days) |
| Quality | Full+ | LLM reviews rules files for specificity, actionability, conciseness |

**Exit codes:**
- `0` — all clear (or warnings only)
- `1` — errors found

**Auto-fix** (`--fix`) repairs:
- Non-executable hook scripts (`chmod +x`)
- Missing Zone B files (recreates from templates)

---

### harness eject

Removes toolkit management. Gives full ownership to the user.

```bash
harness eject [--dry-run]
```

**What eject does:**
- Removes `<!-- HARNESS:START v2 -->` / `<!-- HARNESS:END v2 -->` markers from `CLAUDE.md` (content kept)
- Removes `[harness]` hooks from `.claude/settings.json`
- Removes toolkit metadata: `config.json`, `project-context.json`, `backup/`

**What eject keeps:**
- All content in `CLAUDE.md`
- `.claude/harness/rules/` — your rule files
- `.claude/harness/hooks/` — your hook scripts
- `.claude/harness/state/` — your agent state files

After ejecting, you own all files. Edit them freely. To re-initialize: `harness init --force`.

---

## 7. Flags Reference

| Flag | Commands | Description |
|---|---|---|
| `--dry-run` | all | Show what would change, write nothing |
| `--force` | init, update | Skip conflict checks, regenerate everything |
| `--verbose` | all | Detailed logging |
| `--fix` | check | Auto-fix solvable issues |
| `--json` | all | Machine-readable output |
| `--skip-questions` | init, update | Use defaults for discovery questions |
| `--tier=<tier>` | init | Force tier: `minimal` / `standard` / `full` / `enterprise` |

---

## 8. Generated Output

After `harness init`, the following structure is created in your project:

```
project-root/
├── CLAUDE.md                           ← Map (~20 lines, v2 markers)
├── .harnessignore                      ← Scan exclusion patterns
└── .claude/
    ├── settings.json                   ← Hook registrations
    └── harness/
        ├── project-context.json        ← Discovery output
        ├── config.json                 ← Tier, patterns, version hashes
        ├── rules/                      ← Zone A
        │   ├── conventions.md          ← Project-specific coding conventions
        │   ├── risk-rules.md           ← Command risk classification rules
        │   ├── workflow.md             ← Session protocol (standard+)
        │   └── architecture.md         ← Non-obvious arch decisions (full+)
        ├── hooks/                      ← Zone A
        │   ├── pre-command.sh          ← Risk classifier (auto-parsed from risk-rules.md)
        │   └── post-edit.sh            ← Auto-formatter (if formatter detected)
        ├── state/                      ← Zone B
        │   ├── progress.md             ← Session continuity
        │   ├── learnings.md            ← Discovered gotchas
        │   └── plans/
        │       ├── _template-feature.md
        │       └── _template-bugfix.md
        └── backup/                     ← Last 5 auto-backups
```

### What to commit

```gitignore
# .gitignore — add these:
.claude/harness/backup/

# Commit everything else:
# CLAUDE.md
# .claude/harness/rules/
# .claude/harness/hooks/
# .claude/harness/config.json
# .claude/harness/state/   (optional — depends on team preference)
```

---

## 9. 15 Harness Patterns

Patterns are cumulative — each tier includes all patterns from lower tiers.

### Group 1: Memory & Context

| # | Pattern | Tier | Problem solved |
|---|---|---|---|
| 1 | **Persistent Instruction File** | Minimal | Agent forgets conventions each session |
| 2 | **Scoped Context Assembly** | Standard | Multi-module rule conflicts |
| 3 | **Tiered Memory** (L1/L2/L3) | Full | Context window overflow |
| 4 | **Dream Consolidation** | Enterprise | Memory bloat over time |
| 5 | **Progressive Context Compaction** | Full | Long conversations losing context |
| 6 | **Living State** | Standard | No continuity between sessions |

### Group 2: Workflow & Orchestration

| # | Pattern | Tier | Problem solved |
|---|---|---|---|
| 7 | **Explore-Plan-Act Loop** | Standard | Agent modifies before understanding |
| 8 | **Context-Isolated Subagents** | Full | Context pollution between agents |
| 9 | **Fork-Join Parallelism** | Enterprise | Sequential execution bottleneck |
| 10 | **Session Protocol** | Standard | Sessions without structure drift |

### Group 3: Tools & Permissions

| # | Pattern | Tier | Problem solved |
|---|---|---|---|
| 11 | **Progressive Tool Expansion** | Enterprise | Too many tools confuse the model |
| 12 | **Command Risk Classification** | Minimal | Destructive commands uncontrolled |
| 13 | **Single-Purpose Tool Design** | Minimal | General shell too broad to validate |

### Group 4: Automation

| # | Pattern | Tier | Problem solved |
|---|---|---|---|
| 14 | **Deterministic Lifecycle Hooks** | Minimal | Agent forgets procedural steps |
| 15 | **Generator-Evaluator Loop** | Full | Generated content too generic or verbose |

---

## 10. Scoring & Tier Classification

The classify step uses a **point-based scoring system** — no LLM required for the base case.

```
score 0-2   → minimal
score 3-5   → standard
score 6-12  → full
score 13+   → enterprise
```

If conflicting signals are detected (e.g., agents directory with no AI SDK), the toolkit logs warnings and proceeds with rule-based classification. Running inside Claude Code enables LLM-assisted conflict resolution.

**Override when the score is wrong:**

```bash
# My project has agents but scored only standard:
harness init --tier=full
```

---

## 11. Git & Team Usage

### Recommended `.gitignore`

```gitignore
.claude/harness/backup/
```

### What each team member needs

- The toolkit installed locally (`./install.sh`)
- `jq` installed
- Claude Code (for LLM steps)

### First-time setup on a project with existing harness

```bash
# Project already has .claude/harness/ checked in
harness check      # validate what's there
harness update     # regenerate if stale
```

### Sharing harness across team

Commit `rules/`, `hooks/`, `config.json`, and `CLAUDE.md`. Optionally commit `state/` (useful for shared context; skip if team prefers individual agent state).

---

## 12. Troubleshooting

### `harness: command not found`

```bash
# Check symlink
ls -la ~/.local/bin/harness

# Check PATH
echo $PATH | tr ':' '\n' | grep local

# Fix: add to ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
source ~/.zshrc
```

### `jq is required but not installed`

```bash
# macOS
brew install jq

# Ubuntu/Debian
apt install jq

# Alpine
apk add jq
```

### `Harness already initialized`

```bash
# Option 1: Update existing harness
harness update

# Option 2: Full reinit (discards Zone A, keeps Zone B)
harness init --force
```

### `Harness not initialized`

```bash
harness init
```

### Hook not executable

```bash
harness check --fix
```

### CLAUDE.md markers malformed

```bash
# Eject to remove markers, then reinit
harness eject
harness init --force
```

### Generation failed (LLM error)

Make sure you're running from within a Claude Code session (not bare shell) for the generate step. Alternatively, run `harness init --tier=minimal` — minimal tier uses no LLM.

---

## 13. FAQ

**Q: Does the toolkit work without Claude Code?**  
A: The discover, classify, write, and structure-validate steps work without Claude Code. Only the generate step (content creation) and quality validate step require LLM access.

**Q: Can I edit the rule files manually?**  
A: Zone A files (`rules/`, `hooks/`) will be overwritten on `harness update`. Edit them after running `harness eject`, or use `harness update --force` to trigger regeneration with your current project context.

**Q: What happens to my existing CLAUDE.md?**  
A: The toolkit only modifies content between the `<!-- HARNESS:START v2 -->` and `<!-- HARNESS:END v2 -->` markers. Everything outside is untouched.

**Q: What is `.harnessignore`?**  
A: Similar to `.gitignore` — patterns listed here are excluded from filesystem scanning during discovery. Useful for large generated directories. Default exclusions: `node_modules`, `.git`, `dist`, `build`, `.next`, `__pycache__`, `vendor`, `target`.

**Q: Can I use this with non-Claude AI agents?**  
A: The toolkit generates standard Markdown files. Any agent that reads `CLAUDE.md` (or equivalent) can use the output. Hook scripts are shell scripts — they work with any tool that supports pre-command hooks.

**Q: How do I add a custom pattern?**  
A: After ejecting, you own all files. Add your own sections to `conventions.md`, extend `risk-rules.md`, or create additional files. Reference them in `CLAUDE.md`.

---
