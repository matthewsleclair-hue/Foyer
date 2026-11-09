#!/usr/bin/env bash
# Builds a signed APK and publishes it as a GitHub Release. Every Foyer with
# Settings > Updates pointed at this repo then offers the update.
# One-time: brew install gh && gh auth login
# Usage: tools/publish.sh [project-path] ["release notes"]
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${FOYER_REPO:-matthewsleclair-hue/Foyer}"
PROJ="${1:-$HOME/Downloads/leclair_home}"
NOTES="${2:-}"
command -v gh >/dev/null || { echo "Install the GitHub CLI first:  brew install gh && gh auth login"; exit 1; }
bash "$HERE/tools/release.sh" "$PROJ"
NAME="$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)"
BUILD="$(python3 -c "import json;print(json.load(open('$HERE/update.json'))['build'])")"
TAG="v$NAME+$BUILD"
[ -n "$NOTES" ] || NOTES="Foyer $NAME"
gh release create "$TAG" "$HERE/Foyer.apk" --repo "$REPO" --title "Foyer $NAME ($BUILD)" --notes "$NOTES"
echo
echo "Published $TAG to https://github.com/$REPO/releases"
echo "On the stick: Settings > Updates > Check now."
