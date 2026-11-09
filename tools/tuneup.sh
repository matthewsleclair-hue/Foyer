#!/bin/bash
# Tune-up from your computer (same as the in-app Tune-up, but over your own ADB connection).
#   bash tools/tuneup.sh            disable ads/tracking + unused Amazon apps
#   bash tools/tuneup.sh undo       turn everything back on
# Needs: adb connected to the stick (adb connect <stick-ip>:5555)
ADS="com.amazon.recess com.amazon.tv.acr com.amazon.hybridadidservice com.amazon.ftvads.deeplinking com.amazon.sneakpeek com.amazon.shoptv.client com.amazon.shoptv.firetv.client com.amazon.tv.releasenotes com.amazon.storm.lightning.tutorial com.amazon.tmm.tutorial"
EXTRAS="com.amazon.minitv.android.app com.amazon.imdb.tv.android.app com.amazon.bueller.photos com.amazon.bueller.music com.amazon.gamehub com.amazon.tv.livetv com.amazon.tv.support com.amazon.tv.csapp"
if [ "$1" = "undo" ]; then ACT=enable; else ACT=disable-user; fi
for p in $ADS $EXTRAS; do
  [ "$ACT" = enable ] && adb shell pm enable "$p" >/dev/null 2>&1 || adb shell pm disable-user --user 0 "$p" 2>&1 | tail -1
  echo "$ACT $p"
done
