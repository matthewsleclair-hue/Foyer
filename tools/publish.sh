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
if [ -z "$NOTES" ]; then
  # what's new since the last release, from CHANGELOG.md (added, changed, removed, fixed)
  PREV="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null | sed 's/^v//; s/+.*//' || true)"
  if [ -n "$PREV" ] && [ "$PREV" != "$NAME" ]; then
    NOTES="$(python3 "$HERE/tools/release_notes.py" "$NAME" "$PREV")"
  else
    NOTES="$(python3 "$HERE/tools/release_notes.py" "$NAME")"
  fi
fi
gh release create "$TAG" "$HERE/Foyer.apk" --repo "$REPO" --title "Foyer $NAME ($BUILD)" --notes "$NOTES"
echo
echo "Published $TAG to https://github.com/$REPO/releases"

# Also put it on your Foyer Drop server, for boxes set to update from Foyer Drop
# (most update straight from GitHub now). Skipped when no server is set (tools/drop-ssh.sh).
DROP_SSH_ASK=0; . "$HERE/tools/drop-ssh.sh"
DROP_DIR="${FOYER_DROP_DIR:-foyer-drop/data/releases}"
python3 - "$HERE/update.json" "$NOTES" > "$HERE/update-drop.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1])); j["notes"] = sys.argv[2]; j.pop("url", None)
print(json.dumps(j))
PY
if [ -n "$DROP_SSH" ] && ssh -o ConnectTimeout=5 "$DROP_SSH" "mkdir -p $DROP_DIR" 2>/dev/null; then
  scp -q "$HERE/Foyer.apk" "$DROP_SSH:$DROP_DIR/Foyer.apk.new"
  scp -q "$HERE/update-drop.json" "$DROP_SSH:$DROP_DIR/update.json.new"
  # swap both in at once, so a TV never sees the new version number with the old file
  ssh "$DROP_SSH" "cd $DROP_DIR && mv Foyer.apk.new Foyer.apk && mv update.json.new update.json"
  echo "Also on Foyer Drop ($DROP_SSH:$DROP_DIR): linked TVs can update now."
else
  echo "(Foyer Drop didn't get this version: no server set, or it didn't answer. Boxes update from GitHub anyway.)"
fi

# Foyer for PC (built by GitHub): put the newest one on Foyer Drop too, so PCs update themselves.
bash "$HERE/tools/publish-pc.sh" || echo "(Foyer for PC wasn't put on Foyer Drop this time.)"
