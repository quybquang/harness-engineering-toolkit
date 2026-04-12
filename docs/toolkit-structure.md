# Toolkit Structure — v2

Source of truth for the harness-engineering-toolkit repository layout.

---

## Repository Structure

```
harness-engineering-toolkit/
├── bin/
│   └── harness                         ← CLI entry point
├── lib/
│   ├── utils.sh                        ← Shared utilities (logging, json, templates)
│   ├── discover.sh                     ← Project discovery engine
│   ├── classify.sh                     ← Tier classification logic
│   ├── generate.sh                     ← Content generation orchestration
│   ├── write.sh                        ← File write operations
│   ├── validate.sh                     ← Validation engine
│   ├── cmd-init.sh                     ← `harness init` command
│   ├── cmd-update.sh                   ← `harness update` command
│   ├── cmd-check.sh                    ← `harness check` command
│   └── cmd-eject.sh                    ← `harness eject` command
├── prompts/
│   ├── generate/
│   │   ├── conventions.md.tmpl         ← Conventions generation prompt
│   │   ├── risk-rules.md.tmpl          ← Risk rules generation prompt
│   │   ├── workflow.md.tmpl            ← Session protocol prompt
│   │   ├── architecture.md.tmpl        ← Architecture decisions prompt
│   │   └── critical-rules.md.tmpl      ← Critical rules selection prompt
│   ├── classify-ambiguous.md.tmpl      ← LLM fallback for tier classification
│   └── evaluator.md.tmpl              ← Generator-evaluator quality check prompt
├── templates/
│   ├── zone-b/
│   │   ├── progress.md                 ← Zone B template: progress tracking
│   │   ├── learnings.md                ← Zone B template: discoveries log
│   │   ├── _template-feature.md        ← Zone B template: feature plan
│   │   └── _template-bugfix.md         ← Zone B template: bugfix plan
│   └── harnessignore                   ← Default .harnessignore content
├── commands/
│   ├── harness.md                      ← Slash command: /harness (full pipeline)
│   ├── harness-check.md                ← Slash command: /harness-check
│   └── harness-eject.md                ← Slash command: /harness-eject
├── docs/
│   ├── 15-patterns.md                  ← Pattern reference (theory)
│   ├── output-format.md                ← What gets generated in target projects
│   ├── toolkit-structure.md            ← This file
│   ├── spec-discover.md                ← Discover step specification
│   ├── spec-classify.md                ← Classify step specification
│   ├── spec-generate.md                ← Generate step specification
│   ├── spec-write.md                   ← Write step specification
│   ├── spec-validate.md                ← Validate step specification
│   ├── spec-cli.md                     ← CLI & shared infrastructure spec
│   └── spec-eject-and-commands.md      ← Eject & slash commands spec
├── install.sh                          ← Install slash commands to ~/.claude/commands/
├── uninstall.sh                        ← Remove slash commands
├── VERSION                             ← Toolkit version (semver)
├── CLAUDE.md                           ← Toolkit's own harness config
└── README.md                           ← Usage documentation
```

---

## File Categories

### Executable Scripts (`bin/`, `lib/`)

Shell scripts (POSIX sh compatible). Single external dependency: `jq`.

- `bin/harness` — CLI router, parses flags, dispatches to commands
- `lib/cmd-*.sh` — High-level command orchestration (init, update, check, eject)
- `lib/*.sh` — Core logic (discover, classify, generate, write, validate)
- `lib/utils.sh` — Shared: logging, JSON helpers, template resolution, LLM adapter

### Prompt Templates (`prompts/`)

Markdown files with `{{placeholder}}` syntax. Resolved by `utils.sh:resolve_template()`.

- `{{project_context_json}}` — replaced with full project-context.json
- `{{stack.frameworks}}` — replaced with specific field values
- Templates are never modified at runtime

### Static Templates (`templates/`)

Files copied as-is into target projects. No placeholder resolution.

- `zone-b/*.md` — Agent-managed state files
- `harnessignore` — Default ignore patterns

### Slash Commands (`commands/`)

Markdown instruction files for Claude Code. Symlinked to `~/.claude/commands/` by install.sh.

### Documentation (`docs/`)

Design specs and references. Not shipped to target projects.

---

## Command → Step Mapping

```
harness init      = discover → classify → generate → write → validate
harness update    = discover → classify → (selective) generate → write → validate
harness check     = validate (structure + consistency + freshness + quality)
harness eject     = inline rules into CLAUDE.md → remove toolkit files → remove hooks
```

| Command | discover | classify | generate | write | validate |
|---|---|---|---|---|---|
| `init` | Full | Full | Full | Full | Full |
| `update` | Full (re-discover) | Full (may change tier) | Selective (only changed sections) | Full (with backup) | Full |
| `check` | No | No | No | No | Full |
| `eject` | No | No | No | Reverse (inline + cleanup) | No |

---

## Dependencies

| Dependency | Required | Purpose |
|---|---|---|
| `jq` | Yes | JSON parsing and manipulation |
| `shasum` | Yes (macOS built-in) | File hashing for change detection |
| `awk` | Yes (POSIX) | Marker-based text manipulation |
| `sed` | Yes (POSIX) | Template placeholder resolution |
| Claude Code | For slash commands | LLM calls during generate step |

---

## Versioning

`VERSION` file contains semver string (e.g., `0.1.0`).

- **Patch** (0.1.x): Bug fixes, template improvements
- **Minor** (0.x.0): New patterns, new features, new prompt templates
- **Major** (x.0.0): Breaking changes to output format, config schema, or marker format

`config.json` stores both `toolkit_version` (generated with) and `min_compatible_version` (minimum toolkit version that can update this harness).

---

## Installation

```bash
# Clone
git clone <repo-url> ~/tools/harness-engineering-toolkit

# Install slash commands
cd ~/tools/harness-engineering-toolkit
./install.sh

# Verify
ls -la ~/.claude/commands/harness*

# Use in any project
cd ~/my-project
/harness              # or: ~/tools/harness-engineering-toolkit/bin/harness init
```

### Update

```bash
cd ~/tools/harness-engineering-toolkit
git pull
./install.sh          # Re-links any new commands
```

### Uninstall

```bash
cd ~/tools/harness-engineering-toolkit
./uninstall.sh        # Removes symlinks from ~/.claude/commands/
```

Note: Uninstalling the toolkit does NOT remove harness from projects. Each project's harness is independent. Use `harness eject` per-project to inline and remove toolkit management.
