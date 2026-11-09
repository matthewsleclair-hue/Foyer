#!/bin/bash
# Foyer tune-up, run from a computer on the same Wi-Fi as the stick.
#   bash tools/tuneup.sh 192.168.68.64          disable ads/tracking + unused Amazon apps
#   bash tools/tuneup.sh 192.168.68.64 undo     turn everything back on
# The stick needs ADB debugging on (Settings > My Fire TV > Developer options).
IP="$1"; MODE="$2"
if [ -z "$IP" ]; then echo "Usage: bash tools/tuneup.sh <stick IP> [undo]"; exit 1; fi
if ! command -v adb >/dev/null; then echo "adb not found. Install it first (Mac: brew install android-platform-tools)."; exit 1; fi
adb connect "$IP:5555" | tail -1
if ! adb -s "$IP:5555" shell true 2>/dev/null; then
  echo "Could not talk to the stick. Accept 'Allow USB debugging' on the TV (choose Always allow) and run again."; exit 1
fi
ADS="com.amazon.recess com.amazon.tv.acr com.amazon.hybridadidservice com.amazon.ftvads.deeplinking com.amazon.sneakpeek com.amazon.shoptv.client com.amazon.shoptv.firetv.client com.amazon.tv.releasenotes com.amazon.storm.lightning.tutorial com.amazon.tmm.tutorial"
EXTRAS="com.amazon.minitv.android.app com.amazon.imdb.tv.android.app com.amazon.bueller.photos com.amazon.bueller.music com.amazon.gamehub com.amazon.tv.livetv com.amazon.tv.support com.amazon.tv.csapp"
ok=0; skip=0
for p in $ADS $EXTRAS; do
  if [ "$MODE" = "undo" ]; then out=$(adb -s "$IP:5555" shell pm enable "$p" 2>&1)
  else out=$(adb -s "$IP:5555" shell pm disable-user --user 0 "$p" 2>&1); fi
  case "$out" in
    *Exception*|*"Unknown package"*|*"not found"*) skip=$((skip+1)); echo "  skipped $p";;
    *) ok=$((ok+1)); echo "  done    $p";;
  esac
done
echo "Finished: $ok changed, $skip not on this stick."
