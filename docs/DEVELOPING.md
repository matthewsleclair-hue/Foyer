# Building and publishing Foyer

## Publishing without a computer (the normal way now)

GitHub builds everything. When `VERSION` changes on `main`:

- **Foyer for TV** (`.github/workflows/foyer-android.yml`) builds and signs `Foyer.apk` and publishes it as a release.
- **Foyer for PC** (`.github/workflows/foyer-pc.yml`) builds the Windows zip and publishes a "Foyer for PC" pre-release.
- **Foyer Drop** checks GitHub every 10 minutes (with a read-only token, set on its web page: TVs → Foyer updates from
  GitHub) and fetches both, so linked TVs and PCs update from it.

So publishing is: change the code, `bash tools/bump.sh small|medium|large`, add the CHANGELOG entry, push. From any
computer, or none (a Claude session can do it).

One-time setup:
1. On the Mac with the signing key: `bash tools/setup-ci.sh` (puts the key in the repo's secrets).
2. Update Foyer Drop: `bash tools/deploy-drop.sh`, then on its web page (owner): TVs → Foyer updates from GitHub → paste a
   fine-grained token (only the Foyer repository, Contents: Read-only) → Save token.

The older way below (building on the Mac with `tools/publish.sh`) still works.


Notes for whoever builds Foyer from this code. The friendly overview is the [README](../README.md).

Features: pinned-app dock, weather, screensaver (colors, your photos, or online photos), wallpapers,
Plex "Continue Watching" row, backup/restore, performance mode, start on boot, update check, and a
Tune-up screen that removes Amazon ads and bloat (reversible) over on-device ADB.

## First-time project setup (Mac)
    flutter create --org com.leclair --project-name leclair_home --platforms android ~/Downloads/leclair_home
The package id stays `com.leclair.leclair_home` so updates and settings keep working.

## Build and install on your stick
    ./update.sh            # copies this code into the project, builds, installs, grants permissions
    ./update.sh --reset    # same, and shows the first-run setup again

## Signed APK to share
    tools/create_signing.sh   # once. BACK UP ~/.leclair-signing and never commit it
    tools/release.sh          # outputs Foyer.apk and update.json

If you switch to a new signing key: back up settings in the app (Settings > Backup and restore),
`adb uninstall com.leclair.leclair_home`, install the signed build, then restore.

## Updates from GitHub (Settings > Updates)
Foyer reads the latest GitHub Release of the repo set in Settings > Updates (default `matthewsleclair-hue/Foyer`).

Publish a new version:

    brew install gh && gh auth login      # once
    tools/publish.sh ~/Downloads/leclair_home "What changed"

That builds the signed APK and creates a release tagged `v<VERSION>+<build>` with `Foyer.apk` attached.
On the stick: Settings > Updates > Check now > Download and install. A small orange dot also appears on the
home screen's settings icon when a newer version exists.

Quick way to get the token onto the stick (typing 90 characters with a remote is painful):

    printf '%s' 'github_pat_xxx' > /tmp/foyer-token.txt
    adb push /tmp/foyer-token.txt /sdcard/Android/data/com.leclair.leclair_home/files/foyer-token.txt
    rm /tmp/foyer-token.txt
Then Settings > Updates > Load token from file. The file is deleted from the stick after it is read.

Private repo: create a fine-grained token (GitHub > Settings > Developer settings > Personal access tokens),
limited to this repo with **Contents: Read-only**, and add it in Settings > Updates > Add access token. It is
stored on the TV only and is never included in backups or debug reports. A public repo needs no token.

Not using GitHub? Settings > Updates also accepts a link to a small JSON file
(`{"version":"1.0.1","build":26110901,"url":"<direct apk link>","notes":""}`).
`tools/release.sh` writes one as `update.json`.
Bump `VERSION` to change the version name; the build number goes up automatically (every minute), so you can publish as often as you like.

## French (and other words on screen)
Write the English in the code as usual. Every file imports `material.dart hide Text` plus
`i18n.dart`, whose `Text` looks the words up in `lib/fr.dart` when it's shown, so the French
needs no other change. For words that aren't a `Text` widget (a painted tile, a hint), call
`tr('...')`. A part that changes is written `{}` in fr.dart: `'Remove {}': 'Retirer {}'`.
`python3 tools/i18n_scan.py` lists English text that has no French yet.
The few words the Android side shows by itself (sleep note, Screen off, toasts) use `Lang.t()`
in `Lang.kt`.

## Settings follow you
Each box posts its settings (no sign-ins) to Foyer Drop (`POST /api/tv/settings`) about 20 seconds
after a change; `GET /api/tv/settings` lists the household's boxes and `GET /api/tv/settings/{id}`
gives one. The client is `lib/sync.dart`. The server needs `bash tools/deploy-drop.sh` once for this.

## Icon
Regenerate with `python3 tools/make_icons.py` (needs `pip install playwright`). Previews are in `docs/`.

## Screenshots for the README
    bash tools/screenshots.sh <TV IP>   # walks you through each screen and saves docs/screenshots/*.png

## Notes
- Home button: double-press Home to reach the stock Fire TV home. "Use as my Home screen" in Tune-up disables
  Amazon's launcher (Restore Amazon home undoes it).
- Tune-up needs ADB debugging on. Some Fire OS versions block on-device ADB; it then prints the commands to run from a computer.
- Wallpaper photos: put them in Pictures/Download, or the app's own folder shown in Settings > Wallpaper.
- Untested on devices other than a Fire TV Stick 3rd Gen (2020).

## Friends: setting up
See [GUIDE.md](../GUIDE.md) for the step-by-step install and clean-up guide.

## Version numbers
Small update: last number +1 (1.0.1 -> 1.0.2). Medium: middle number +1 and the last goes back to 0 (1.5.10 -> 1.6.0). Large: first number +1 and the rest go back to 0 (1.5.10 -> 2.0.0).
`bash tools/bump.sh small|medium|large` does it; `bash tools/publish.sh` then builds and releases.

**Release notes come from [CHANGELOG.md](../CHANGELOG.md).** Add a `## x.y.z` section with **Added**, **Changed**,
**Removed** and **Fixed** lists for each version. `publish.sh` puts everything since the last GitHub release into the
release's description (and the TV's Updates screen shows the same list). To rewrite every past release's description
from the changelog: `bash tools/fix-release-notes.sh`.

## Live scores and Foyer Drop

Settings → Home screen → **Sports scores** (also a step in first-run setup) lets you follow NHL, MLB, NBA, NFL teams and Formula 1.
Scores come from ESPN's public data, which is unofficial and can change, so the pill simply hides if it stops working.
**Foyer Drop** links the TV with a short code to the optional Docker server in [`server/`](../server/README.md).

## TV settings (Google TV / Android TV)

Settings > **TV settings** puts Wi-Fi, Bluetooth, picture, sound, apps, storage, name and power inside Foyer (`lib/system.dart`, `TvSystem.kt`). It uses on-device ADB for the parts apps can't change themselves, and falls back to the stock page when a TV won't allow something. Not shown on Fire TV, where Amazon blocks on-device ADB. See GUIDE.md.

## Publishing (current)
    cd ~/Foyer && git pull && bash tools/publish.sh
Builds the signed APK (adds the font to the project if needed), publishes the GitHub release, and copies the APK to your Foyer Drop server so linked friends' TVs can update.

## Android libraries
`tools/patch_deps.py` (run by `update.sh` and `release.sh`) adds ZXing core to `android/app/build.gradle(.kts)` once. Foyer uses it to draw QR codes on the TV (`qrPng` in MainActivity, `QrCode` widget in screens.dart).

## Upgrading Gradle / Android Gradle Plugin / Kotlin
When Flutter warns that support for the project's Gradle, AGP or Kotlin version will be dropped:

    flutter upgrade
    python3 tools/upgrade_gradle.py ~/Downloads/leclair_home
    cd ~/Downloads/leclair_home && flutter clean

It moves the project to Gradle 9.3.1, AGP 9.0.1 and Kotlin 2.3.20 following Flutter's AGP 9 / built-in Kotlin
migration guides (removes the kotlin-android plugin, kotlinOptions becomes kotlin.compilerOptions, sets
android.newDsl / android.builtInKotlin), and keeps a .bak of each file. Needs Flutter 3.44+; built-in Kotlin turns on with 3.47+.
To undo: rename the .bak files back.

