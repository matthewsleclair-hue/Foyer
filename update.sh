#!/usr/bin/env bash
# Copies these files into your project, rebuilds (signed if you made a key), installs, opens.
# Usage: ./update.sh [path-to-leclair_home] [--reset]
#   --reset  also clears saved settings so the setup screen shows again
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$HOME/Downloads/leclair_home"
RESET=0
for a in "$@"; do
  case "$a" in
    --reset) RESET=1 ;;
    *) PROJ="$a" ;;
  esac
done
[ -d "$PROJ" ] || { echo "Project not found: $PROJ (pass its path as an argument)"; exit 1; }
SIGN="$HOME/.leclair-signing"
cp "$HERE"/lib/*.dart "$PROJ/lib/"
cp -R "$HERE/android/." "$PROJ/android/"
python3 "$HERE/tools/patch_fonts.py" "$PROJ"
python3 "$HERE/tools/patch_deps.py" "$PROJ"
if [ -f "$SIGN/key.properties" ]; then
  cp "$SIGN/key.properties" "$PROJ/android/key.properties"
  python3 "$HERE/tools/patch_signing.py" "$PROJ"
else
  echo "(No signing key yet. Run tools/create_signing.sh once, then use tools/release.sh to build the shareable APK.)"
fi
cd "$PROJ"
flutter build apk --release --build-name "$(cat "$HERE/VERSION" 2>/dev/null || echo 1.0.0)" --build-number "$(( 30000000 + ( $(date +%s) - 1767225600 ) / 60 ))"
if ! adb install -r build/app/outputs/flutter-apk/app-release.apk; then
  echo
  echo "Install failed. If it says UPDATE_INCOMPATIBLE the new signing key differs from the installed one."
  echo "In the app: Settings > Backup and restore > Back up now, then run:"
  echo "  adb uninstall com.leclair.leclair_home && ./update.sh"
  exit 1
fi
adb shell pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS || true
adb shell pm grant com.leclair.leclair_home android.permission.READ_EXTERNAL_STORAGE || true
adb shell pm grant com.leclair.leclair_home android.permission.WRITE_EXTERNAL_STORAGE || true
if [ "$RESET" = "1" ]; then
  adb shell pm clear com.leclair.leclair_home
  adb shell pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS || true
fi
adb shell monkey -p com.leclair.leclair_home -c android.intent.category.LEANBACK_LAUNCHER 1
