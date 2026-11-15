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
shot home        "The home screen (Keep watching showing, a photo scene behind)"
shot all-apps    "All apps (press Down on your apps)"
shot settings    "Settings (the gear), on Home screen so its options show on the right"
shot people      "Settings > Home screen > People"
shot tv-settings "Settings > TV settings > (press Right) the list on the right"
shot weather     "Settings > Appearance > Weather on the background > Rain (the preview)"
shot smart-idle  "Settings > Screensaver and power > Smart idle (switched On, so its options show)"
shot sports      "Settings > Home screen > Sports"
shot alert       "A score alert on screen: Sports page > Show a sample, then press Enter quickly"
shot sleep       "The moon button menu (Goodnight / Sleep timer / Screen off / Fireplace)"
shot setup       "The welcome setup's \"Make it yours\" step (Settings > Backup and updates > Run setup again)"
shot holiday     "Christmas on the home screen, with the lights (Appearance > Seasonal themes > Try one now > Christmas)"
shot search      "Search results (the magnifying glass, then search a show like Stranger Things)"
shot open-apps   "Open apps (press Back twice on the home screen, with a few apps open)"
shot jiggle      "Jiggle mode (hold OK on an app on the home screen)"
shot glass       "Glass app icons on the home screen (Appearance > App icons > Glass)"
echo
echo "Done. Check them, then: git add docs/screenshots && git commit -m 'Screenshots' && git push"
echo "(Tip: if the scores or a person's name shouldn't be in the pictures, switch them off first.)"
