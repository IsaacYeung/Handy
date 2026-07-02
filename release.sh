#!/bin/bash
# Publishes a release: builds the DMG, signs it for Sparkle, generates the
# appcast, and uploads everything to GitHub Releases.
#
# Usage:
#   1. Bump the VERSION file
#   2. Commit everything (the release should match what's in git)
#   3. bash release.sh          (SIGNING_IDENTITY="Developer ID …" for real releases)
set -e

VERSION=$(tr -d '[:space:]' < VERSION)
REPO="IsaacYeung/Handy"

if [ "${SIGNING_IDENTITY:--}" = "-" ]; then
    echo ""
    echo "  WARNING: building ad-hoc. Updates delivered from this release will"
    echo "  RESET users' permissions. Set SIGNING_IDENTITY to your Developer ID"
    echo "  for real releases."
    echo ""
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: uncommitted changes — commit first so the release matches git."
    exit 1
fi

if gh release view "v$VERSION" --repo "$REPO" &>/dev/null; then
    echo "ERROR: release v$VERSION already exists. Bump the VERSION file."
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
bash build.sh

# ── Stage + appcast ───────────────────────────────────────────────────────────
# generate_appcast signs each archive with the EdDSA key from the Keychain and
# writes releases/appcast.xml. Old DMGs left in releases/ stay listed, which
# lets Sparkle offer delta/skipped-version logic.
mkdir -p releases
cp Handy.dmg "releases/Handy-$VERSION.dmg"
./vendor/Sparkle/bin/generate_appcast releases \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/"

# ── Publish ───────────────────────────────────────────────────────────────────
gh release create "v$VERSION" \
    "releases/Handy-$VERSION.dmg" \
    "releases/appcast.xml" \
    --repo "$REPO" \
    --title "Handy $VERSION" \
    --generate-notes

echo ""
echo "Released v$VERSION."
echo "Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
