#!/bin/sh
# Harness Engineering Toolkit — Installer
# Installs CLI to PATH and Claude Code commands to ~/.claude/commands/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="$SCRIPT_DIR"

echo "━━━ Harness Engineering Toolkit — Install ━━━"
echo ""

# ── Check dependencies ───────────────────────────────────────────────────────

check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: '$1' is required but not installed."
        echo "Install it and re-run this script."
        exit 1
    fi
}

check_dependency "jq"
check_dependency "git"
echo "  Dependencies: OK"

# ── Install CLI ──────────────────────────────────────────────────────────────

# Make bin/harness executable
chmod +x "$TOOLKIT_DIR/bin/harness"

# Add to PATH via symlink
_target_dir="$HOME/.local/bin"
mkdir -p "$_target_dir"

if [ -L "$_target_dir/harness" ]; then
    rm "$_target_dir/harness"
fi
ln -s "$TOOLKIT_DIR/bin/harness" "$_target_dir/harness"
echo "  CLI: symlinked to $_target_dir/harness"

# Check if ~/.local/bin is in PATH
case ":$PATH:" in
    *":$_target_dir:"*) ;;
    *)
        echo ""
        echo "  WARNING: $_target_dir is not in your PATH."
        echo "  Add this to your shell profile (~/.zshrc or ~/.bashrc):"
        echo ""
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        ;;
esac

# ── Install Claude Code commands ─────────────────────────────────────────────

_claude_cmd_dir="$HOME/.claude/commands"

if [ -d "$HOME/.claude" ]; then
    mkdir -p "$_claude_cmd_dir"

    for _cmd in "$TOOLKIT_DIR/integrations/claude-code/commands/"*.md; do
        if [ -f "$_cmd" ]; then
            _name=$(basename "$_cmd")
            if [ -L "$_claude_cmd_dir/$_name" ]; then
                rm "$_claude_cmd_dir/$_name"
            fi
            ln -s "$_cmd" "$_claude_cmd_dir/$_name"
            echo "  Claude Code: /$_name"
        fi
    done

    echo "  Claude Code commands installed"
else
    echo "  Claude Code: ~/.claude not found — skipping command installation"
    echo "  (Install Claude Code first, then re-run this script)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "━━━ Install complete ━━━"
echo ""
echo "  Usage:"
echo "    harness init        # Initialize harness for a project"
echo "    harness update      # Update existing harness"
echo "    harness check       # Validate harness health"
echo "    harness eject       # Remove toolkit management"
echo ""
echo "  In Claude Code:"
echo "    /harness-init       # Initialize with LLM assistance"
echo "    /harness-update     # Update with LLM assistance"
echo "    /harness-check      # Validate harness"
echo "    /harness-eject      # Eject from toolkit"
echo ""
