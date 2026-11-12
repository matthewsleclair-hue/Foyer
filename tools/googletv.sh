#!/bin/bash
# Makes Foyer the home screen on a Google TV / Android TV box (Google TV Streamer, Chromecast with Google TV...).
# Run from a computer on the same Wi-Fi as the TV.
#   bash tools/googletv.sh 192.168.1.60          switch the stock home screen off, Foyer takes over
#   bash tools/googletv.sh 192.168.1.60 undo     bring the stock home screen back
#   bash tools/googletv.sh 192.168.1.60 5555 ... use another port (newer TVs show one under Wireless debugging)
#
# On the TV first: Settings > System > About, press "Android TV OS build" 7 times, then
# Settings > System > Developer options > turn on USB debugging (or Wireless debugging).
# With Wireless debugging you may have to pair once:  adb pair <ip>:<pairing port>
IP="$1"; shift
PORT=5555; MODE=""
for a in "$@"; do
  case "$a" in
    undo) MODE=undo ;;
    ''|*[!0-9]*) ;;
    *) PORT="$a" ;;
  esac
done
if [ -z "$IP" ]; then echo "Usage: bash tools/googletv.sh <TV IP> [port] [undo]"; exit 1; fi
if ! command -v adb >/dev/null; then echo "adb not found. Install it first (Mac: brew install android-platform-tools)."; exit 1; fi
T="$IP:$PORT"
adb connect "$T" | tail -1
if ! adb -s "$T" shell true 2>/dev/null; then
  echo "Could not talk to the TV. Accept the 'Allow debugging' box on the TV (choose Always allow) and run again."
  echo "If the TV shows a different port under Wireless debugging, add it:  bash tools/googletv.sh $IP <port>"
  exit 1
fi
PKG=com.leclair.leclair_home
# Google's setup app has to go with the home screen: left on, its recovery screen can
# grab Home and crash-loop the Streamer. It also holds the saved Wi-Fi, so you may
# have to pick your Wi-Fi again once afterwards.
STOCK="com.google.android.apps.tv.launcherx com.google.android.tungsten.setupwraith"

if [ "$MODE" = "undo" ]; then
  for p in $STOCK; do
    adb -s "$T" shell pm enable "$p" >/dev/null 2>&1 && echo "  back on  $p" || echo "  skipped  $p"
  done
  echo "The stock home screen is back. Press Home on the remote."
  exit 0
fi

if ! adb -s "$T" shell pm path "$PKG" 2>/dev/null | grep -q package:; then
  echo "Foyer is not installed on this TV yet. Install it first:  adb -s $T install Foyer.apk"
  echo "(Nothing was changed, so the TV still has its normal home screen.)"
  exit 1
fi
# Lets Foyer manage its own Home button service, in case it is ever needed as a fallback.
adb -s "$T" shell pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS 2>/dev/null
# Android 13+ blocks accessibility helpers for apps updated from an APK file; lift that.
adb -s "$T" shell appops set "$PKG" ACCESS_RESTRICTED_SETTINGS allow 2>/dev/null
for p in $STOCK; do
  out=$(adb -s "$T" shell pm disable-user --user 0 "$p" 2>&1)
  case "$out" in
    *Exception*|*"Unknown package"*|*"not found"*|*rror*) echo "  could not switch off $p: $out" ;;
    *) echo "  off      $p" ;;
  esac
done
adb -s "$T" shell cmd package set-home-activity "$PKG/.MainActivity" >/dev/null 2>&1
# Show Foyer now; from here on the Home button lands on it.
adb -s "$T" shell am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null 2>&1
home=$(adb -s "$T" shell cmd package resolve-activity --brief -c android.intent.category.HOME 2>/dev/null | tail -1)
echo "Home button now opens: $home"
case "$home" in
  *"$PKG"*) echo "Done. Foyer is the home screen." ;;
  *) echo "Foyer is not the home screen yet. If the TV asks which home app to use, pick Foyer and 'Always'."
     echo "To go back at any time:  bash tools/googletv.sh $IP $PORT undo" ;;
esac
