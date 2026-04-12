# Harness Engineering Toolkit

## Project Overview

CLI toolkit to bootstrap and manage AI agent harness for any project. Shell-based core with Claude Code integration.

## Tech Stack

- POSIX shell scripts (no bash-specific features)
- jq for JSON processing
- Claude Code slash commands for LLM integration
- Markdown templates with `{{placeholder}}` substitution

## Architecture

```
bin/harness          ← CLI entry point, argument parser, command router
lib/utils.sh         ← Shared utilities (logging, JSON helpers, markers, backup)
lib/discover.sh      ← Filesystem scanner, produces project-context.json
lib/classify.sh      ← Rule-based tier classification
lib/generate.sh      ← Content generation orchestrator + LLM prompt preparation
lib/write.sh         ← File writer with marker management
lib/validate.sh      ← Structure + quality validation
lib/cmd-*.sh         ← Command handlers (init, update, check, eject)
prompts/             ← LLM prompt templates
templates/           ← Static file templates
integrations/        ← IDE-specific integrations (Claude Code commands)
```

## Conventions

- All shell scripts must be POSIX-compatible (`#!/bin/sh`)
- Use `jq` for JSON manipulation, never sed/awk on JSON
- All file writes go through `lib/write.sh` — never write project files directly from other scripts
- Marker format: `<!-- HARNESS:START v2 ... -->` / `<!-- HARNESS:END v2 -->`
- Logging uses `log_info`, `log_step`, `log_warn`, `log_error`, `log_success` from utils.sh
- Variable names use snake_case with underscore prefix for local vars: `_my_var`
- Exit codes defined in utils.sh — use named constants, not raw numbers

## Testing

Test by running against real projects:
```bash
cd ~/some-project && harness init --dry-run
```

## Critical Rules

1. Never write directly to user's CLAUDE.md without marker management
2. Never overwrite Zone B files (progress.md, learnings.md) — they contain user state
3. All LLM-dependent steps must have standalone fallbacks (placeholder content)
4. backup_current() must be called before any write operation
