# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-22

### Added

- Initial release of the Harness Engineering Toolkit.
- CLI entry point (`bin/harness`) with argument parsing and command routing.
- Five core pipeline stages: discover, classify, generate, write, validate.
- Four commands: `init`, `update`, `check`, `eject`.
- Complexity tier system: minimal, standard, full, enterprise.
- Two-zone architecture: Zone A (toolkit-managed) and Zone B (agent-managed).
- `CLAUDE.md` as a short context map (~20 lines).
- POSIX-compatible shell implementation (`#!/bin/sh`, no bashisms).
- JSON processing via `jq` (never sed/awk on JSON).
- File writes centralized through `lib/write.sh`.
- 15 harness patterns with tier mapping.
- Claude Code slash command integration (`/harness-init`, `/harness-update`, etc.).
- Installer (`install.sh`) and uninstaller (`uninstall.sh`).
- Test suite (`tests/run-tests.sh`) with unit tests for learning layer.
- Comprehensive documentation: usage guide, pattern reference, implementation specs.
