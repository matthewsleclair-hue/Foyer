#!/usr/bin/env bash
# Puts the latest Foyer Drop (the phone page and its server) on your server and restarts it.
# Usage: bash tools/deploy-drop.sh        (uses the same server as publish.sh)
# Your accounts, TVs, notes, photos and Foyer updates live in foyer-drop/data and are never touched.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/tools/drop-ssh.sh"
DROP_HOME="${FOYER_DROP_HOME:-foyer-drop}"
echo "Copying Foyer Drop to $DROP_SSH:$DROP_HOME …"
ssh -o ConnectTimeout=5 "$DROP_SSH" "mkdir -p $DROP_HOME"
rsync -az \
  --exclude data/ --exclude .env --exclude __pycache__/ \
  "$HERE/server/" "$DROP_SSH:$DROP_HOME/"
echo "Rebuilding and restarting it …"
ssh -t "$DROP_SSH" "cd $DROP_HOME && (docker compose up -d --build || sudo docker compose up -d --build)"
echo "Done. Reload the Foyer Drop page on your phone (on iPhone: close the app from the app switcher and open it again)."
