# Contributing to Harness Engineering Toolkit

Thank you for your interest in contributing! This document will help you get started.

## Table of Contents

1. [Development Setup](#development-setup)
2. [Coding Standards](#coding-standards)
3. [Testing](#testing)
4. [Pull Request Workflow](#pull-request-workflow)
5. [Commit Messages](#commit-messages)
6. [Documentation](#documentation)

---

## Development Setup

### Prerequisites

- `jq` — JSON processing (`brew install jq` on macOS, `apt install jq` on Debian/Ubuntu)
- `git`
- POSIX-compatible shell (`sh`, `bash`, `zsh`, or `dash`)
- `shellcheck` (optional but strongly recommended for linting)

### Clone and Install

```bash
git clone https://github.com/yourusername/harness-engineering-toolkit.git
cd harness-engineering-toolkit
./install.sh
```

This symlinks the `harness` CLI to `~/.local/bin` and installs Claude Code commands (if `~/.claude` exists).

### Uninstall

```bash
./uninstall.sh
```

---

## Coding Standards

All shell scripts in this project **must** be POSIX-compatible (`#!/bin/sh`).

### Rules

- Use `#!/bin/sh` — no `bash` or `zsh` specific features
- Every script must start with `set -e` (exit on error)
- Use `jq` for all JSON manipulation — never `sed`, `awk`, or `grep` on JSON
- All file writes go through `lib/write.sh` — never write project files directly from other scripts
- Prefer `printf` over `echo` for portable output
- Quote all variables: `"$var"`, not `$var`
- Use meaningful variable names with `_` prefix for local/temp variables

### Linting

If you have `shellcheck` installed, run:

```bash
make lint
```

Address all warnings before submitting a PR. Disable specific checks only with a clear code comment explaining why.

---

## Testing

Run the full test suite:

```bash
make test
```

Or run a specific test file:

```bash
sh tests/run-tests.sh unit/test-queue-append.sh
```

All new features must include unit tests in `tests/unit/`. Tests should be self-contained and not modify the working directory.

---

## Pull Request Workflow

1. **Fork** the repository and create a feature branch (`git checkout -b feature/my-feature`)
2. **Make changes** following the coding standards above
3. **Run tests**: `make test` — all must pass
4. **Run lint**: `make lint` — no warnings (or document why suppressed)
5. **Update docs** if your change affects behavior or adds new flags/commands
6. **Open a Pull Request** with a clear description of the problem and solution

### PR Checklist

- [ ] Tests pass (`make test`)
- [ ] `shellcheck` clean (`make lint`)
- [ ] Documentation updated (README, docs/, or inline comments)
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] No breaking changes without explicit discussion

---

## Commit Messages

Follow conventional commit style where possible:

```
type(scope): short description

Body explaining what and why (not how).
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Example:

```
feat(discover): add detection for pnpm monorepos

Extends the discovery engine to recognize pnpm workspace.yaml
and classify the project as standard tier automatically.
```

---

## Documentation

- `README.md` — high-level overview, quick start, badges
- `docs/USAGE.md` — detailed usage guide (English)
- `docs/USAGE.vi.md` — Vietnamese usage guide
- `docs/15-patterns.md` — pattern reference
- `docs/spec-*.md` — implementation specifications

Keep docs in sync with code changes. If you add a new flag, document it in `README.md` and `docs/USAGE.md`.
