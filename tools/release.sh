#!/usr/bin/env bash
# Builds a signed release APK you can share. Usage: tools/release.sh [project-path]
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="${1:-$HOME/Downloads/leclair_home}"
[ -d "$PROJ" ] || { echo "Project not found: $PROJ"; exit 1; }
SIGN="$HOME/.leclair-signing"
[ -f "$SIGN/key.properties" ] || bash "$HERE/tools/create_signing.sh"
cp "$HERE"/lib/*.dart "$PROJ/lib/"
cp -R "$HERE/android/." "$PROJ/android/"
cp "$SIGN/key.properties" "$PROJ/android/key.properties"
python3 "$HERE/tools/patch_signing.py" "$PROJ"
cd "$PROJ"
BUILD="$(date +%y%m%d%H)"   # always goes up, so updates install over old ones
NAME="$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)"
flutter build apk --release --build-name "$NAME" --build-number "$BUILD"
OUT="$HERE/Foyer.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
cat > "$HERE/update.json" <<JSON
{"version":"$NAME","build":$BUILD,"url":"${UPDATE_APK_URL:-PUT-THE-DIRECT-APK-LINK-HERE}","notes":"What's new"}
JSON
echo
echo "Update file: $HERE/update.json  (host it next to the APK, then set its link in Settings > Updates)"
echo "Signed APK: $OUT"
echo "Share it with friends (Downloader app + a short link works well)."
