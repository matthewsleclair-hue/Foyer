#!/usr/bin/env bash
# Builds your TMDB key into Foyer TV, for "Where to watch" in Search everything.
# It asks for the key without showing it, keeps a copy in ~/.leclair-signing/tmdb-key (for
# builds on this Mac), gives it to GitHub as the TMDB_KEY secret, and rebuilds the TV and PC
# versions. The key never goes into the code or the repo.
# Get a key: themoviedb.org → sign in → Settings → API → create (personal use).
# Usage: bash tools/set-tmdb-key.sh
set -e
REPO="${FOYER_REPO:-matthewsleclair-hue/Foyer}"
SIGN="$HOME/.leclair-signing"
command -v gh >/dev/null || { echo "Install the GitHub CLI first:  brew install gh && gh auth login"; exit 1; }
printf "Paste your TMDB API key (or read access token), then press Return: "
read -rs KEY; echo
KEY="$(printf %s "$KEY" | tr -d '[:space:]')"
[ ${#KEY} -ge 20 ] || { echo "That looks too short for a TMDB key."; exit 1; }
# check it works before saving it anywhere
if [[ "$KEY" == eyJ* ]]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" https://api.themoviedb.org/3/configuration)
else
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://api.themoviedb.org/3/configuration?api_key=$KEY")
fi
[ "$CODE" = 200 ] || { echo "TMDB didn't accept that key (answer $CODE). Copy it again from themoviedb.org."; exit 1; }
mkdir -p "$SIGN" && umask 077 && printf %s "$KEY" > "$SIGN/tmdb-key"
printf %s "$KEY" | gh secret set TMDB_KEY --repo "$REPO"
echo "Saved. GitHub builds it into Foyer TV from now on."
gh api -X POST "repos/$REPO/actions/workflows/foyer-android.yml/dispatches" -f ref=main >/dev/null && echo "Rebuilding the TV app…"
gh api -X POST "repos/$REPO/actions/workflows/foyer-pc.yml/dispatches" -f ref=main >/dev/null && echo "Rebuilding Foyer for PC…"
echo "Watch it here: https://github.com/$REPO/actions"
