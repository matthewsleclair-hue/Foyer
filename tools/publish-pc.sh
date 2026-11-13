#!/usr/bin/env bash
# Puts the newest Foyer for PC (built by GitHub, the "Foyer for PC" releases) on your
# Foyer Drop server, so PCs linked to it can update themselves (Settings > Updates).
# publish.sh runs this for you; you can also run it on its own: bash tools/publish-pc.sh
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${FOYER_REPO:-matthewsleclair-hue/Foyer}"
DROP_SSH="${FOYER_DROP_SSH:-cardtracker@192.168.2.24}"
DROP_DIR="${FOYER_DROP_DIR:-foyer-drop/data/releases}/pc"
TAG="$(gh api "repos/$REPO/releases?per_page=30" --jq '[.[] | select(.tag_name | startswith("pc-v"))][0].tag_name')"
[ -n "$TAG" ] && [ "$TAG" != "null" ] || { echo "No Foyer for PC release on GitHub yet."; exit 0; }
NAME="${TAG#pc-v}"; VER="${NAME%%+*}"; BUILD="${NAME##*+}"
TMP="$(mktemp -d)"
gh release download "$TAG" --repo "$REPO" --pattern '*.zip' --dir "$TMP"
ZIP="$(ls "$TMP"/*.zip | head -1)"
python3 - "$VER" "$BUILD" "$(python3 "$HERE/tools/release_notes.py" "$VER")" > "$TMP/update.json" <<'PY'
import json, sys
print(json.dumps({"version": sys.argv[1], "build": int(sys.argv[2]), "notes": sys.argv[3]}))
PY
ssh -o ConnectTimeout=5 "$DROP_SSH" "mkdir -p $DROP_DIR"
scp -q "$ZIP" "$DROP_SSH:$DROP_DIR/Foyer-PC.zip.new"
scp -q "$TMP/update.json" "$DROP_SSH:$DROP_DIR/update.json.new"
ssh "$DROP_SSH" "cd $DROP_DIR && mv Foyer-PC.zip.new Foyer-PC.zip && mv update.json.new update.json"
rm -rf "$TMP"
echo "Foyer for PC $VER (build $BUILD) is on Foyer Drop: linked PCs can update now."
