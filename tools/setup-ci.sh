#!/usr/bin/env bash
# One-time, on the Mac that has your signing key: gives GitHub the key so it can build and
# sign Foyer by itself. After this, publishing needs no computer: a new version number on
# GitHub builds the TV app and Foyer for PC, and your Foyer Drop server fetches them.
# Usage: bash tools/setup-ci.sh
set -e
REPO="${FOYER_REPO:-matthewsleclair-hue/Foyer}"
SIGN="$HOME/.leclair-signing"
command -v gh >/dev/null || { echo "Install the GitHub CLI first:  brew install gh && gh auth login"; exit 1; }
[ -f "$SIGN/key.properties" ] || { echo "No signing key in $SIGN"; exit 1; }
prop() { grep "^$1=" "$SIGN/key.properties" | head -1 | cut -d= -f2-; }
JKS="$(prop storeFile)"; [ -f "$JKS" ] || JKS="$SIGN/leclair-release.jks"
[ -f "$JKS" ] || { echo "Can't find the keystore file"; exit 1; }
base64 < "$JKS" | tr -d '\n' | gh secret set FOYER_KEYSTORE_B64 --repo "$REPO"
printf %s "$(prop storePassword)" | gh secret set FOYER_STORE_PASSWORD --repo "$REPO"
printf %s "$(prop keyPassword)" | gh secret set FOYER_KEY_PASSWORD --repo "$REPO"
printf %s "$(prop keyAlias)" | gh secret set FOYER_KEY_ALIAS --repo "$REPO"
echo "GitHub has the signing key (kept secret; only the build can use it)."
echo "Building the current version now: https://github.com/$REPO/actions"
gh workflow run "Foyer for TV" --repo "$REPO" || true
