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

## Updates (Settings > Updates)
`tools/release.sh` writes `update.json`:
`{"version":"1.0.0","build":26110920,"url":"<direct APK link>","notes":"..."}`
Host `Foyer.apk` and `update.json` somewhere with direct links (a public GitHub release works), then put the link to
`update.json` in Settings > Updates. `UPDATE_APK_URL=<link> tools/release.sh` fills the APK link in for you.
Bump `VERSION` to change the displayed version name. The build number always goes up automatically.

## Notes
- Home button: double-press Home to reach the stock Fire TV home. "Use as my Home screen" in Tune-up disables
  Amazon's launcher (Restore Amazon home undoes it).
- Tune-up needs ADB debugging on. Some Fire OS versions block on-device ADB; it then prints the commands to run from a computer.
- Wallpaper photos: put them in Pictures/Download, or the app's own folder shown in Settings > Wallpaper.
- Untested on devices other than a Fire TV Stick 3rd Gen (2020).
