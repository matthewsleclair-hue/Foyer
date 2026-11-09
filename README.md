# Foyer

An Apple TV style home screen for Amazon Fire TV sticks: glass UI, fast, no ads.
It is a launcher that sits on top of Fire OS (it does not replace the OS).

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

Private repo: create a fine-grained token (GitHub > Settings > Developer settings > Personal access tokens),
limited to this repo with **Contents: Read-only**, and add it in Settings > Updates > Add access token. It is
stored on the TV only and is never included in backups or debug reports. A public repo needs no token.

Not using GitHub? Settings > Updates also accepts a link to a small JSON file
(`{"version":"1.0.1","build":26110901,"url":"<direct apk link>","notes":""}`).
`tools/release.sh` writes one as `update.json`.
Bump `VERSION` to change the version name; the build number goes up automatically (hourly), so you can publish at most once per hour.

## Icon
Regenerate with `python3 tools/make_icons.py` (needs `pip install playwright`). Previews are in `docs/`.

## Notes
- Home button: double-press Home to reach the stock Fire TV home. "Use as my Home screen" in Tune-up disables
  Amazon's launcher (Restore Amazon home undoes it).
- Tune-up needs ADB debugging on. Some Fire OS versions block on-device ADB; it then prints the commands to run from a computer.
- Wallpaper photos: put them in Pictures/Download, or the app's own folder shown in Settings > Wallpaper.
- Untested on devices other than a Fire TV Stick 3rd Gen (2020).
