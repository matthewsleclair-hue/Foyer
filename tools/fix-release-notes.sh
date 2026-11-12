#!/usr/bin/env bash
# One-time: rewrites the description of every Foyer release on GitHub from CHANGELOG.md,
# so each one says what it added, changed, removed and fixed (counting every version
# since the release before it). Safe to run again. Usage: bash tools/fix-release-notes.sh
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${FOYER_REPO:-matthewsleclair-hue/Foyer}"
command -v gh >/dev/null || { echo "Install the GitHub CLI first:  brew install gh && gh auth login"; exit 1; }
gh api "repos/$REPO/releases" --paginate --jq '.[] | "\(.id) \(.tag_name)"' > /tmp/foyer-releases.txt
# oldest first, by version then build
python3 - "$HERE" /tmp/foyer-releases.txt <<'PY' > /tmp/foyer-release-plan.txt
import re, sys
rows = []
for line in open(sys.argv[2]):
    rid, tag = line.split()
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?", tag)
    if m:
        rows.append(((int(m[1]), int(m[2]), int(m[3])), int(m[4] or 0), rid, tag))
rows.sort()
prev = None
for v, b, rid, tag in rows:
    name = ".".join(map(str, v))
    print(rid, tag, name, prev or "-")
    prev = name
PY
n=0
while read -r ID TAG NAME PREV; do
  if [ "$PREV" = "-" ] || [ "$PREV" = "$NAME" ]; then
    BODY="$(python3 "$HERE/tools/release_notes.py" "$NAME")"
  else
    BODY="$(python3 "$HERE/tools/release_notes.py" "$NAME" "$PREV")"
  fi
  gh api -X PATCH "repos/$REPO/releases/$ID" -f body="$BODY" --silent
  echo "  $TAG"
  n=$((n+1))
done < /tmp/foyer-release-plan.txt
echo "Updated $n releases: https://github.com/$REPO/releases"
