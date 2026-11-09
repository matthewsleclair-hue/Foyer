#!/usr/bin/env bash
# One-time: creates your release signing key. KEEP A BACKUP of ~/.leclair-signing,
# because updates (yours and your friends') only install over each other if signed with the same key.
set -e
DIR="$HOME/.leclair-signing"
if [ -f "$DIR/leclair-release.jks" ]; then
  echo "A signing key already exists in $DIR. Not touching it."
  exit 0
fi
command -v keytool >/dev/null || { echo "keytool not found. Install Java first: brew install --cask temurin"; exit 1; }
mkdir -p "$DIR" && chmod 700 "$DIR"
PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
keytool -genkeypair -v -keystore "$DIR/leclair-release.jks" -alias leclair \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=Foyer, O=Leclair, C=CA"
cat > "$DIR/key.properties" <<PROPS
storePassword=$PASS
keyPassword=$PASS
keyAlias=leclair
storeFile=$DIR/leclair-release.jks
PROPS
chmod 600 "$DIR/key.properties" "$DIR/leclair-release.jks"
echo
echo "Created $DIR"
echo "Back up that whole folder somewhere safe (cloud drive, USB stick)."
