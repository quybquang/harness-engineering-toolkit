#!/bin/sh
# Harness Engineering Toolkit — Uninstaller
# Removes CLI symlink and Claude Code commands

set -e

echo "━━━ Harness Engineering Toolkit — Uninstall ━━━"
echo ""

# ── Remove CLI ───────────────────────────────────────────────────────────────

_target="$HOME/.local/bin/harness"
if [ -L "$_target" ]; then
    rm "$_target"
    echo "  CLI: removed from $_target"
else
    echo "  CLI: not found at $_target (already removed?)"
fi

# ── Remove Claude Code commands ──────────────────────────────────────────────

_claude_cmd_dir="$HOME/.claude/commands"
_removed=0

for _cmd in harness-init.md harness-update.md harness-check.md harness-eject.md; do
    if [ -L "$_claude_cmd_dir/$_cmd" ]; then
        rm "$_claude_cmd_dir/$_cmd"
        _removed=$((_removed + 1))
        echo "  Claude Code: removed $_cmd"
    fi
done

if [ "$_removed" -eq 0 ]; then
    echo "  Claude Code: no commands found (already removed?)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Uninstall complete ━━━"
echo ""
echo "  Note: This only removes the toolkit's CLI and slash commands."
echo "  Harness files in your projects (CLAUDE.md, hooks, rules) are untouched."
echo "  To remove harness from a project, run 'harness eject' first."
echo ""
