#!/usr/bin/env bash
# Takes the README screenshots straight from the TV. Usage: bash tools/screenshots.sh <TV IP>
# For each one, get the TV to the screen it names, then press Enter here.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
IP="${1:?Usage: bash tools/screenshots.sh <TV IP>}"
T="$IP:5555"
OUT="$HERE/docs/screenshots"
mkdir -p "$OUT"
adb connect "$T" >/dev/null
adb -s "$T" shell true || { echo "Can't reach the TV at $T"; exit 1; }

shot() {
  read -r -p "→ $2   (Enter when it's on screen, s to skip) " a
  [ "$a" = "s" ] && return
  adb -s "$T" exec-out screencap -p > "$OUT/$1.png"
  echo "   saved docs/screenshots/$1.png"
}

echo "Tip: wait a second after each screen opens, so animations have finished."
shot home        "The home screen (an app selected, clock and greeting showing)"
shot all-apps    "All apps"
shot settings    "Settings (the main list)"
shot tv-settings "Settings > TV settings"
shot sports      "Settings > Home screen > Sports"
shot alert       "A score alert on screen: Sports page > Show a sample, then press Enter quickly"
shot sleep       "The moon button menu (Goodnight / Sleep timer)"
shot setup       "The welcome setup (Settings > Backup and updates > Run setup again)"
shot holiday     "A holiday theme on the home screen (Appearance > Seasonal themes > Try one)"
echo
echo "Done. Check them, then: git add docs/screenshots && git commit -m 'Screenshots' && git push"
