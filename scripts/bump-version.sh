#!/bin/sh
# scripts/bump-version.sh — Semver version bumper
# Usage: sh scripts/bump-version.sh [patch|minor|major]
#
# Updates VERSION, prepends CHANGELOG.md, and creates a git tag.
# Does NOT push — you push manually when ready.
#
# Exit codes: 0 = success, 2 = input error

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

BUMP_TYPE="${1:-patch}"

# ── Read current version ────────────────────────────────────────────────────

CURRENT=$(cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0")

# ── Parse semver ────────────────────────────────────────────────────────────

MAJOR=$(printf '%s' "$CURRENT" | cut -d. -f1)
MINOR=$(printf '%s' "$CURRENT" | cut -d. -f2)
PATCH=$(printf '%s' "$CURRENT" | cut -d. -f3)

# ── Bump ────────────────────────────────────────────────────────────────────

case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch|*)
        PATCH=$((PATCH + 1))
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TODAY=$(date +%Y-%m-%d)

# ── Update VERSION ───────────────────────────────────────────────────────────

printf '%s\n' "$NEW_VERSION" > "$VERSION_FILE"
echo "  VERSION: $CURRENT → $NEW_VERSION"

# ── Prepend CHANGELOG ────────────────────────────────────────────────────────

NEW_HEADER="## [Unreleased]

## [$NEW_VERSION] - $TODAY

### Added

### Changed

### Fixed

### Removed
"

# Insert after the first line (the header "# Changelog")
{
    head -n 1 "$CHANGELOG_FILE"
    printf '\n%s\n' "$NEW_HEADER"
    tail -n +2 "$CHANGELOG_FILE"
} > "${CHANGELOG_FILE}.tmp"

mv "${CHANGELOG_FILE}.tmp" "$CHANGELOG_FILE"
echo "  CHANGELOG: prepended $NEW_VERSION section"

# ── Git tag ─────────────────────────────────────────────────────────────────

TAG="v${NEW_VERSION}"
git tag -a "$TAG" -m "Release $TAG"
echo "  Git tag: $TAG created (local only)"

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "Bump complete. Review changes, then push with:"
echo "  git push origin $TAG"
echo ""
