#!/usr/bin/env bash
# Bumps VERSION by how big the update is.
#   bash tools/bump.sh small    1.0.1 -> 1.0.2   (fixes, tweaks)
#   bash tools/bump.sh medium   1.0.1 -> 1.1.0   (new feature or screen)
#   bash tools/bump.sh large    1.0.1 -> 2.0.0   (a lot changed)
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IFS=. read -r MA MI PA < "$HERE/VERSION"
case "$1" in
  small)  PA=$((PA+1));;
  medium) MI=$((MI+1)); PA=0;;
  large)  MA=$((MA+1)); MI=0; PA=0;;
  *) echo "Usage: bash tools/bump.sh small|medium|large"; exit 1;;
esac
echo "$MA.$MI.$PA" > "$HERE/VERSION"
echo "Version is now $MA.$MI.$PA"
