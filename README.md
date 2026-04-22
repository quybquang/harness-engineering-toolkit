# Harness Engineering Toolkit

[![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](VERSION)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

CLI toolkit to bootstrap and manage AI agent harness for any project, any stage.

> **New to the project?** Jump to [Quick Start](#quick-start) or read the full [Usage Guide](docs/USAGE.md).

## What is Harness Engineering?

Harness Engineering = designing the orchestration layer around AI agents that controls:

- **Context**: What the agent sees
- **Permissions**: What the agent can do
- **Workflow**: How the agent works
- **Automation**: Where the system intervenes deterministically

Analogy: Agent = brain. Harness = nervous system.

## Core Principles

1. **Works for any project, any stage** — greenfield or existing codebase
2. **Not fully LLM-dependent** — scripts handle deterministic logic, LLM handles judgment
3. **Script is always the final writer** — LLM never writes directly to filesystem
4. **Self-contained output** — team members don't need the toolkit installed
5. **No lock-in** — `harness eject` gives full ownership back

## Commands

| Command | Purpose |
|---|---|
| `harness init` | Full pipeline: discover → classify → generate → write → validate |
| `harness update` | Re-discover, diff, selective regenerate, merge, validate |
| `harness check` | Validate current harness without changes |
| `harness eject` | Remove toolkit management, user owns everything |

### Flags

| Flag | Description |
|---|---|
| `--dry-run` | Show what would change, don't write |
| `--force` | Skip confirmations, regenerate everything |
| `--verbose` | Detailed logging |
| `--fix` | Auto-fix issues found during check |
| `--tier=<tier>` | Force tier (minimal/standard/full/enterprise) |
| `--skip-questions` | Use defaults for discovery questions |

## Quick Start

```bash
# 1. Install the toolkit
git clone https://github.com/OWNER/REPO.git ~/tools/harness-engineering-toolkit
cd ~/tools/harness-engineering-toolkit
./install.sh

# 2. Go to any project
cd ~/my-project

# 3. Preview what would be generated (safe — no file writes)
harness init --dry-run

# 4. Initialize harness
harness init

# 5. Check health
harness check

# 6. Update after project changes
harness update

# 7. Opt out of toolkit management anytime
harness eject
```

## v2 Architecture

### CLAUDE.md as Map (~20 lines)

CLAUDE.md is a **map** — a short pointer document that always fits in context:

```markdown
<!-- HARNESS:START v2 -->
# Harness · my-project · standard tier
TypeScript · Next.js 15 · pnpm · Vitest

## Rules
- Read `.claude/harness/rules/conventions.md` before writing code
- Read `.claude/harness/rules/risk-rules.md` before running commands

## Critical
- Use `pnpm`, never `npm` or `yarn`
- Run `pnpm check` before committing
<!-- HARNESS:END v2 -->
```

### Two Zones

| Zone | Owner | Contents | Toolkit Behavior |
|---|---|---|---|
| Zone A | Toolkit | `rules/`, `hooks/`, `config.json` | Overwrites on update |
| Zone B | AI Agent | `state/progress.md`, `state/learnings.md`, `state/plans/` | Creates once, never overwrites |

### Complexity Tiers

| Tier | Trigger | Pattern Count | What Gets Generated |
|---|---|---|---|
| Minimal | All projects | 4 | CLAUDE.md + conventions + risk rules + hooks |
| Standard | Docker, CI/CD, or multi-service | 8 | + workflow + scoped configs + Zone B state |
| Full | Agentic indicators, >5 services | 12 | + architecture + evaluated quality |
| Enterprise | Team >1, large monorepo | 15 | + dream consolidation + fork-join templates |

### 15 Harness Patterns

See [docs/15-patterns.md](docs/15-patterns.md) — 12 original + 3 new in v2.

## Pipeline

```
discover (script) → classify (script+LLM) → generate (LLM) → write (script) → validate (script+LLM)
```

| Step | Executor | Input | Output |
|---|---|---|---|
| Discover | Shell script | Filesystem + user answers | project-context.json |
| Classify | Shell + LLM fallback | project-context.json | Tier + pattern list |
| Generate | LLM | Context + prompts | Rules, hooks, map content |
| Write | Shell script | Generated content | Files in project |
| Validate | Shell + LLM | Current harness state | Pass/warn/fail report |

## Documentation

### Reference
- [15 Harness Patterns](docs/15-patterns.md) — Pattern reference + tier mapping
- [Output Format](docs/output-format.md) — File structure, zones, config.json, CLAUDE.md map format
- [Toolkit Structure](docs/toolkit-structure.md) — Repository layout

### Implementation Specs
- [CLI Entry Point](docs/spec-cli.md) — Router, flag parsing, utils, error handling, UX output
- [Discover](docs/spec-discover.md) — Detection logic per signal, pseudocode, edge cases
- [Classify](docs/spec-classify.md) — Decision tree, pattern mapping, LLM fallback, tier transitions
- [Generate](docs/spec-generate.md) — Prompt templates, evaluator loop, hook generation
- [Write](docs/spec-write.md) — v2 marker system, zone management, backup strategy
- [Validate](docs/spec-validate.md) — Structure + consistency + freshness + quality checks
- [Eject & Commands](docs/spec-eject-and-commands.md) — Eject logic, slash commands, install/uninstall

## Requirements

| Dependency | Install | Purpose |
|---|---|---|
| `jq` | `brew install jq` / `apt install jq` | JSON processing throughout |
| `git` | pre-installed on most systems | Contributor detection |
| `sh` (POSIX) | built-in | All scripts are POSIX-compatible |
| Claude Code | [claude.ai/code](https://claude.ai/code) | LLM steps (generate, quality validate) |

Install dependencies in one line (macOS):

```bash
brew install jq
```

## Contributing

We welcome contributions! Please read our [Contributing Guide](CONTRIBUTING.md) for development setup, coding standards, and pull request workflow.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

This project is licensed under the [MIT License](LICENSE).

## Security

To report a security vulnerability, please use [GitHub's private vulnerability reporting](SECURITY.md) instead of opening a public issue.
