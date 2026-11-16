# Setting up Foyer TV with a computer

On a Google TV you don't need a computer: see "How do I get it?" in the [README](README.md). This guide is for a
Fire TV Stick, or if you'd rather install with adb.

You need: the TV box, a Mac or Windows computer on the same Wi-Fi, and `Foyer.apk` from the
[latest release](https://github.com/matthewsleclair-hue/Foyer/releases/latest).
This takes about 10 minutes. Nothing here is permanent: the clean-up can be undone.

## 1. Turn on ADB debugging on the stick
1. On the stick: **Settings > My Fire TV > About**. Click **Fire TV Stick** (or "About") 7 times until it says you are a developer.
2. Go back to **My Fire TV > Developer options**.
3. Turn **ADB debugging** ON and **Apps from Unknown Sources** ON.
4. Find the stick's address: **Settings > My Fire TV > About > Network**. Write down the IP address (like `192.168.1.25`).

## 2. Install adb on your computer (one time)
- **Mac:** open Terminal and run `brew install android-platform-tools`
  (no brew? install it from https://brew.sh first).
- **Windows:** download "SDK Platform-Tools for Windows" from
  https://developer.android.com/tools/releases/platform-tools, unzip it, and open a
  Command Prompt inside that folder.

## 3. Install Foyer
Replace `192.168.1.25` with your stick's address, and run these in the same folder as `Foyer.apk`:

    adb connect 192.168.1.25:5555
    adb install -r Foyer.apk
    adb shell pm grant com.leclair.leclair_home android.permission.WRITE_SECURE_SETTINGS

The first command may make the TV ask "Allow USB debugging?". Choose **Always allow**, then run it again.

## 4. Open Foyer and turn on the Home button
1. Open Foyer from your Apps list and follow the first-time setup.
2. Go to **Settings > Fire TV tools > Home button** and choose **Turn on**.
   (If it says a permission is missing, you skipped the last command in step 3.)
3. Press Home on the remote from any app. Foyer comes up after a moment.
   Double-press Home to reach Amazon's own home screen.

## 5. Optional: remove ads and extra Amazon apps
In the Foyer folder (from the project download):

    bash tools/tuneup.sh 192.168.1.25

Windows users: run the same commands from Git Bash.
To undo everything:

    bash tools/tuneup.sh 192.168.1.25 undo

## 6. Updates
Updates come from the GitHub releases page by themselves: Foyer installs a new version when the TV has sat on the home
screen for a while, or at night. (Fire TV asks first: when the Settings icon gets an orange dot, open
**Settings > Backup and updates > Updates** and choose **Download and install**.)

## Troubleshooting
- **"unauthorized" or no Allow prompt:** on the stick, turn ADB debugging off and on, then run `adb connect` again.
- **Foyer's Tune-up buttons say the stick hung up:** this is a Fire OS limit. Use step 5 from a computer instead.
- **Home button does nothing:** repeat the `pm grant` command in step 3, then turn the Home button off and on in Foyer's settings.
- **Reinstalled and Home stopped working:** turn the Home button service off and on again in Foyer's settings.

## Google TV and other Android TV boxes (not Fire TV)

On a Google TV Streamer, Chromecast with Google TV or similar box, Foyer can be the real home screen. No Home button workaround is needed.

**Without a computer:** open Foyer, go to **Settings > TV tools > Home button** and follow the three buttons on screen (About, Developer options, Make Foyer the home screen). If that does not work on your box, use the computer steps below.

**With a computer:**

1. On the TV: **Settings > System > About**, press **Android TV OS build** 7 times. Then **Settings > System > Developer options** and turn on **USB debugging** (or Wireless debugging).
2. Find the TV's IP address under **Settings > Network & Internet**.
3. On your computer, install Foyer and switch the stock home screen off:
   ```bash
   adb connect <TV IP>:5555
   adb install Foyer.apk
   bash tools/googletv.sh <TV IP>
   ```
4. Press Home on the remote. If the TV asks which home app to use, choose **Foyer** and **Always**.

To go back to the normal Google TV home screen: `bash tools/googletv.sh <TV IP> undo`.

This has been checked against a guide for the Chromecast with Google TV (Android 14), not on every box. A system update may switch the stock home screen back on; run the script again if that happens.

### TV settings inside Foyer

Once Foyer is the home screen (the step above), **Settings > TV settings** covers the TV itself, so you don't need the stock settings app:

- **Network and internet:** see nearby Wi-Fi, join one (type the password on the remote or your phone), forget networks, add a hidden one, turn Wi-Fi off. Shows when a cable is plugged in.
- **Bluetooth and remotes:** turn Bluetooth on or off, pair headphones, speakers, controllers and keyboards, forget devices.
- **Picture and display:** resolution and refresh rate (with a 15-second "Keep this picture?" so a bad choice undoes itself), when the screen turns off, Google's own screensaver on or off.
- **Sound:** volume, mute, button click sounds.
- **Apps:** open, force close, clear cache, clear data, turn off, uninstall, and turn back on apps you switched off.
- **Storage:** space used, and **Free up space** to clear every app's temporary files.
- **Name and about:** rename the TV (what phones see when casting), model, Android version, address.
- **Power:** sleep now, restart.
- **More:** Google account, privacy, date and time, language, keyboard, accessibility and system update. Google locks these to its own pages, so they open on top of Foyer; Back returns.

Most of these use the same debugging link as "Make Foyer the home screen". If one says debugging isn't on, run that step again. If a TV update blocks one of them, the screen offers the matching stock page instead.

### Tune-up on Google TV

**Settings > TV tools > Tune-up** switches off Google's leftover ads, tracking and apps you don't use: feedback and remote logging, Privacy Sandbox ad services, Play Games, the Google TV movie store, TalkBack and printing. Only things found on your TV are listed. Nothing is deleted, each item can be turned back on, and **Turn everything back on** undoes it all. Casting, the mic and Assistant, the Play Store, Google Play services and Google's screensaver are never touched.

The list follows CleanYourTV's tested lists for the Google TV Streamer and Chromecast with Google TV.

About Google's setup app: on the Streamer it has to stay off while Foyer is the home screen (left on, it can take over Home and crash the TV). It also holds the saved Wi-Fi and the casting keys, so after the takeover you may have to pick your Wi-Fi again once, and casting from a phone can say "untrusted device".

### Remote buttons

**Settings > TV tools > Remote buttons** picks what the star, YouTube and Netflix buttons open, on a press and on a hold. **Add another button** learns any other extra button (press it when asked). Up, down, OK, Back, Home and volume are never changed.

With Google's home switched off, the YouTube and Netflix buttons would do nothing, so Foyer answers them itself. This uses Foyer's remote helper (the same accessibility helper as the Fire TV Home button), which Foyer turns on during "Make Foyer the home screen". It only listens to every key while a custom button is set, since that adds a tiny delay to each press.

### Sounds

**Settings > Appearance > Sounds** cycles Off, Quiet and Normal: a soft tick when you move, a pop on OK and a drop on Back.

### Sleep timer

Press the **moon** button on the home screen: **Goodnight now**, or **Sleep timer** (15 minutes to 2 hours). The TV keeps playing whatever app you're in. A minute before the end, a note appears at the bottom of the screen; press any button to keep watching. At the end the TV box goes to sleep, and most TVs turn off with it over HDMI. A small moon pill on the home screen shows the time left.

You can also set a remote button to **Sleep timer: 30 more minutes each press** in Settings > TV tools > Remote buttons.

The timer runs in Foyer's remote helper, so keep that helper on.

### Seasonal themes

For the week around each holiday the home screen changes by itself: its own colours, a greeting, and gently falling particles.

| Holiday | When | Looks like |
|---|---|---|
| Halloween | Oct 25 to 31 | orange, falling autumn leaves and bats flying across |
| Christmas | Dec 19 to 26 | red, falling snow |
| New Year | Dec 27 to Jan 2 | gold, confetti and twinkling stars; on Dec 31 a countdown to midnight |
| Easter | Palm Sunday to Easter Monday | pastel lilac, drifting petals |

Settings > Appearance > Seasonal themes turns it on or off and lets you try each one now. Your own photo wallpaper is kept; the particles still show over it. Performance mode uses fewer particles.

### First-run setup

The first time Foyer opens, a guided setup walks through everything with just the remote:

1. **Welcome**
2. **Home screen**: a checklist that ticks itself off. Foyer opens the right TV pages, notices when Developer options and debugging are on, then one press makes Foyer the home screen, switches off Google's ads (Tune-up) and turns on the remote helper. On a Fire TV this step turns on the Home button helper instead.
3. **Wi-Fi**: only appears if the box is offline (the takeover can make it forget Wi-Fi once).
4. **About your home**: name, clock, weather city.
5. **Make it yours**: glass, wallpaper, holiday themes and sounds, with a live preview.
6. **Your apps**: the usual ones (Netflix, Prime Video, YouTube, Plex, Fibe TV) are already picked.
7. **Extras**: Plex, sports scores, Foyer Drop and remote buttons, all optional.
8. **All set**: what's ready, plus tips for the moon, star and Menu buttons.

Choices are saved as you go. **Settings > Backup and updates > Run setup again** opens it any time; your settings are kept.

### Score alerts

When one of the teams you follow scores, a small note pops up in the top corner for a few seconds, over whatever you're watching (Netflix, Plex, anything). It slides in from the right in the scoring team's colours, with a sport badge, the big score and the period, and a thin bar along the bottom that runs down before it fades away. NHL goals, MLB runs and NFL touchdowns, field goals and safeties are announced; NBA only gets start and final (a pop-up for every basket would never stop). F1 gets a note when the race goes live.

**Settings > Home screen > Sports** has everything in one place: your teams, score alerts (**Scores, start and final**, **Scores only** or **Off**, plus **Show a sample**), the alert size (**Medium** by default, or Small or Large) and the alert delay. Alerts need the remote helper. During a live game Foyer checks every 8 seconds, so a note shows within about 10 seconds of ESPN having the goal. TV streams usually run 20 to 60 seconds behind live, so an alert can beat the goal on screen: the **Alert delay** on the same page (0, 15, 30, 45 or 60 s) holds alerts back to match your stream.

### Home screen look

- **Big clock and greeting**: top left, a large clock with "Good evening · 4° Cloudy" under it (holiday greetings take over during holiday weeks). The separate clock and weather pills are gone; the top right keeps Settings, scores and the sleep timer.
- **Light follows the day**: the background is neutral by day, warms up around sunrise and sunset, and dims late at night so Foyer isn't bright blue at midnight. Settings > Appearance > Light follows the day turns it off.
- **Opening an app**: its tile grows to fill the screen in the app's colour, then the app opens. Performance mode keeps the plain fade.

## Setting up a box for a friend (Onn 4K Pro, Chromecast, any Google TV)

Friends' boxes update straight from GitHub, like yours. Foyer Drop is optional (the phone remote, notes, photos, games).

**Preparing the box:**
1. Unbox it and do Google's setup **with your friend's Google account** (see below).
2. Settings > System > About > press **Android TV OS build** 7 times; Developer options > **USB debugging** on.
3. From your Mac: `adb connect <box IP>:5555` then `adb -s <box IP>:5555 install Foyer.apk`.
4. Open Foyer. In the setup, do the **Home screen** step (choose **Always allow**), then skip to the end.
5. Optional: install his apps from the Play Store.
6. Restart the box once and check it starts in Foyer.
7. Foyer > Settings > Backup and updates > **Reset for someone new**. The welcome setup appears. Unplug.

**At his place:** Foyer's welcome setup asks for his Wi-Fi, name, look and apps. If you run Foyer Drop, in **Extras > Foyer Drop** he links the TV with the account you invited him to (Foyer Drop page > TVs > Add a person, or an invite code). Updates come from GitHub by themselves either way.

**The Google account:** the box needs his account for the Play Store and his apps. Do Google's setup while he's there or on a call; if Google TV offers to sign in with a phone and a code, send him the code. Or make a new Gmail for the box and give him the password. Don't use your own: your purchases, YouTube history and payment details would come with it.

### Font

Foyer uses **Plus Jakarta Sans** (in `fonts/`, free under the SIL Open Font License, see `fonts/OFL.txt`). `update.sh`, `tools/release.sh` and `tools/publish.sh` copy it into the Flutter project and add it to `pubspec.yaml` automatically (`tools/patch_fonts.py`, safe to run again). Score alert pop-ups use it too.

### Developer options

Settings > Updates only shows the one **Check now / Download and install** button, so nobody changes where updates come from by accident. To get the rest, press the **Version** line on the Updates page 7 times (like Android's build number). **Developer options** then appears at the bottom of Settings with: where updates come from (GitHub, the default, or Foyer Drop), the GitHub repo (for a fork of your own), an access token (only for a private fork), and the TMDB key for search. **Turn off developer options** hides it again; **Reset for someone new** turns it off too.

### VPN

**Settings > TV settings > VPN** lists the popular VPNs (NordVPN, ExpressVPN, Surfshark, Proton VPN, CyberGhost, Private Internet Access, Mullvad, Tailscale, OpenVPN Connect, WireGuard) and shows whether the TV is connected through one right now. The ones already on the TV are at the top.

On Android TV each VPN signs in and connects in its own app, so Foyer can't sign in for you. Picking one **opens the app** if it's installed, or its **Play Store page** if it isn't.

Some streaming apps block VPNs or show another country's catalogue while one is on.

### Fireplace

The flame button on the home screen opens a fireplace video in the **YouTube app**, full screen, with its own sound. Back or Home returns to Foyer.

**Settings > Home screen > Fireplace video** lets you paste a different YouTube link (handy with the scan-to-type QR code); leave it empty for Foyer's pick. YouTube has to be installed on the TV.

### Scenes (home backgrounds)

**Settings > Appearance > Wallpaper > Scenes** turns the home screen into a landscape with a big glass clock and the date in the sky. The clock sits *behind* the front of the scenery, so peaks and ridges overlap the bottom of the digits.

Five scenes are built in, painted by Foyer itself (no image files): **Night** (stars, a moon and a lake), **Golden hour** (a volcano at sunset), **Waterline** (snowy peaks over a lake), **Fog** (misty forested hills) and **Dawn**. Choose:

- **Take turns**: a new scene fades in every 20 seconds.
- **Match the time of day**: dawn in the early morning, fog mid-morning, waterline through the day, golden hour in the evening, night after dark.
- or one scene to keep.

With a scene on, the small clock in the corner goes away (the scene has the big one) and the greeting and weather stay. The Plex "Continue Watching" row is no longer on the home screen.
