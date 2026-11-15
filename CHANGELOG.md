# What's new in Foyer TV

Newest first. Each update on the TV (Settings → Backup and updates → Updates) and each
GitHub release shows the part of this list it brings.

## 1.31.2
**Changed**
- The big clock on the photo scenes sits higher, so the time is easier to read at a glance. The mountains, the volcano and the trees still tuck under the bottom of the digits.

## 1.31.1
**Added**
- **Automatic updates:** new versions install by themselves when the TV has sat on the home screen for 10 minutes, or in the middle of the night, never while you're using it. On to start; Settings → Backup and updates → Updates turns it off. Foyer for PC too. (Fire TV always asks first, so it still waits there.)

**Fixed**
- Keep watching no longer runs into the round buttons on the left: it lines up with the app row.
- Jiggle mode: moving an app a few times no longer loses track of it (it kept moving only once or twice).

## 1.30.0
**Added**
- **Jiggle mode:** hold OK on an app on the home screen and the apps wiggle, like on an iPhone or Apple TV. Left and Right move the one you picked, OK (or Back) when you're done, Down for its other options (close, uninstall, remove).
- **Aerial screensaver:** the photo scenes drift slowly in and across, one after another, with the time in the corner and the scene's name as it starts. Press Down to see where it is again. Settings → Screensaver and power → Screensaver → Aerial.

## 1.29.0
**Added**
- **Open apps, like on an Apple TV:** press Back twice on the home screen and the apps that are open show as big cards. OK jumps back into one, Up swipes it away and closes it, and Close all closes them all.

**Changed**
- Recent apps became Open apps: it only shows apps that are still running, and closing one really stops it.

## 1.28.0
**Added**
- **No internet?** An orange Wi-Fi button shows on the home screen when the internet drops. It says what's wrong and offers Reconnect Wi-Fi, Wi-Fi settings or Check again.
- **Recent apps:** press Back twice on the home screen to jump back to the last few apps you opened.
- **Battery warnings:** a note over whatever is playing when the remote or a game controller gets low (15%, then 5%). Battery levels show next to paired devices in TV settings → Bluetooth.
- **Undo:** removing an app from the home screen shows an Undo button for a few seconds.

## 1.27.1
**Changed**
- Search everything works without Foyer Drop: the TMDB key can be built into Foyer TV (bash tools/set-tmdb-key.sh puts it on GitHub, never in the code), or typed in Developer options.

## 1.27.0
**Added**
- **Search everything:** the new magnifying glass on the home screen (above the gear). Type a show or a movie and Foyer shows which of your apps have it in Canada (Netflix, Crave, Disney+, Prime Video, Apple TV, Paramount+, YouTube and more), what's on your Plex, and matching apps and games. Pick an app and it opens on that show's search. The streaming part needs a free TMDB key, added once on Foyer Drop's TVs page.

## 1.26.0
**Added**
- **Français:** Foyer TV in French, from the first setup screen (English / Français) or Settings → Appearance → Language. It switches at once, and French also turns on the 24-hour clock.
- **Settings follow you:** every TV and PC linked to Foyer Drop keeps a copy of its settings there (apps, people, teams, look, weather). Right after you link a new box, Foyer asks whether to set it up like one of your other boxes. Also in Settings → Backup and updates → Settings follow you. Plex and other sign-ins are never copied.

**Changed**
- Foyer is now called **Foyer TV** (on the TV's app list, the PC window and the shortcuts).

## 1.25.3
**Fixed**
- Games on the Google TV froze in RetroArch: RetroArch from the Play Store isn't allowed to read Foyer's Games folder. Foyer now copies the game into RetroArch's own folder first (once), and starts it from there.

## 1.25.2
**Added**
- **Add a game controller:** pick PS5 DualSense, PS4, Xbox, Switch Pro or 8BitDo, and Foyer shows which buttons to hold, then finds and pairs it by itself. In TV settings → Bluetooth, and in Games settings.
- Games settings → **Check that games work**: starts a game and shows what RetroArch said, to find out why one won't start.

**Changed**
- Games on the TV start RetroArch the same way other game launchers do (closed first, then handed the game and its core).

## 1.25.1
**Fixed**
- Games on the TV: a game no longer freezes when RetroArch (or Dolphin) was already open. Foyer closes it first, then opens the game.

## 1.25.0
**Added**
- **Games:** play your own Game Boy Advance, Game Boy, NES, SNES, N64, Sega and GameCube/Wii games, with their box art. A Games tile sits at the start of your apps once there are games; the game you played last shows in Keep watching. Games open in RetroArch (or Dolphin for GameCube and Wii), on the TV and on Foyer for PC.
- **Send games from your phone:** Foyer Drop has a Games tab. Pick the game files and they download to your TVs and PCs by themselves.
- Foyer for PC: an Xbox-style controller moves around Foyer (D-pad or stick, A, B, Start), and holding Back + Start leaves a game.

## 1.24.3
**Changed**
- Foyer for PC: Store apps and programs (Netflix, Disney+, Prime Video, Spotify...) open full screen instead of in a window.

## 1.24.2
**Added**
- Foyer for PC updates itself: Settings → Backup and updates → Updates downloads the new version, closes for a moment and opens again. It also checks by itself every few hours, and the gear gets a dot when there's one.

## 1.24.1
**Added**
- Foyer for PC uses the Microsoft Store apps (Netflix, Disney+, Prime Video, Apple TV, Plex, Spotify, Paramount+, Kodi) when they're installed, and closes them when you press Home. Settings → Home screen → Streaming apps switches back to web windows.

**Changed**
- Foyer for PC: the arrow keys (or the remote's arrows) now move between the shows and buttons on Netflix, Prime Video, Disney+ and Crave in their full-screen windows, and OK opens them.

## 1.24.0
**Added**
- **Foyer for PC:** the same Foyer on a Windows PC plugged into the TV. Netflix, Prime Video, Disney+, Crave and YouTube open as full-screen windows, Plex, Spotify, Kodi and Steam as themselves; Home on the remote comes back to Foyer from anywhere; the Foyer Drop phone remote drives the PC. Download it from the "Foyer for PC" release.

**Fixed**
- The welcome setup's Next and Back buttons follow only the steps this box needs.

## 1.23.1
**Changed**
- The Updates screen shows what's new in the version you're about to install, as a tidy list.
- Every GitHub release now describes what it added, changed, removed and fixed.

## 1.23.0
**Added**
- **Now playing:** when Spotify, YouTube Music or another music app is playing, the song, artist and cover show first in Keep watching, with previous, play/pause and next. A paused song stays for 10 minutes.
- **Follow the sun:** the photo scenes follow today's real sunrise and sunset where you live (meadow at sunrise, misty forest in the morning, Matterhorn at midday, volcano at golden hour, starry lake after dark).
- **Soundscapes** in the moon menu: rain, ocean waves, a crackling fire or brown noise, made by the TV itself. A small button shows while one plays.
- Hold OK on a Keep watching card to hide that show, or everything from that app.
- A Keep watching page in Settings: on or off, the song card on or off, and bring hidden shows back.

**Changed**
- "Match the time of day" is now called "Follow the sun".

## 1.22.3
**Fixed**
- The names of the people watching moved under the greeting, so they no longer cover the date on the photo scenes.

## 1.22.2
**Removed**
- The Fireplace row in Settings. The fireplace video is still in the moon menu.

## 1.22.1
**Added**
- Plex shows in Keep watching: Foyer asks your Plex server what you're part way through (Plex doesn't share it with the TV). A Plex row in Settings → Home screen links your account.

## 1.22.0
**Added**
- **Keep watching:** the shows you're part way through (Netflix, Disney+, Prime Video, Fibe TV, YouTube and more) as cards above your apps, with how far in you are. One press picks up where you left off.
- **People:** everyone in the house gets their own apps and sports teams. Pick a name on the home screen to switch, and the greeting says their name. Settings → Home screen → People.

**Changed**
- The settings gear is now the small round button at the bottom left (where the fireplace was).
- The fireplace moved into the moon menu.

## 1.21.2
**Added**
- The welcome setup lets you pick a photo scene, and new boxes start on the photo scenes.

## 1.21.1
**Added**
- A quiet "All apps" hint under your apps.

**Changed**
- Press Down on your apps to see all of them, and Up from the top row to go back.

**Removed**
- The All apps tile at the end of the app row (it comes back only if you unpin every app).

## 1.21.0
**Added**
- **Photo scenes:** a misty meadow, the Matterhorn, a volcano at dusk, a starry lake and a misty forest, with the big clock tucked behind the mountains and trees.

## 1.20.0
**Added**
- **New settings layout:** the sections on the left, their options on the right, with a calm dark background on every settings page.
- **Crash safety net:** if Foyer keeps crashing, the TV's own home screen takes over for a few minutes, so the TV never gets stuck.
- **Screen off:** the picture goes black while the sound keeps playing. Any button brings it back.
- **Smart idle** (off to start): a dim drifting clock, screen off or TV off after a while on the home screen; a show left paused turns the TV off after a "still here?" note; quiet hours.
- **Weather on the background:** rain, storms, snow or fog over the background when it's like that outside, with previews.

**Changed**
- Press Down on the app row to open All apps.

## 1.19.0
**Added**
- **Scenes:** painted landscape backgrounds with a big clock behind the scenery.

## 1.18.2
**Removed**
- The Plex Continue Watching row on the home screen (it took up too much room).

## 1.18.1
**Changed**
- The fireplace button opens a fireplace video on YouTube, full screen.

**Removed**
- The built-in fire and crackle sound.

## 1.18.0
**Added**
- A fireplace with flames, glowing logs, sparks and a crackling sound.

## 1.17.3
**Changed**
- The VPN page opens the VPN app, or its Play Store page if it isn't installed.

**Removed**
- The VPN sign-in QR codes.

## 1.17.2
**Changed**
- The typing box sits at the top, with its QR code beside it, clear of the keyboard.

## 1.17.1
**Added**
- Scan a QR code to type on your phone instead of with the remote.

## 1.17.0
**Added**
- A VPN page in TV settings: whether a VPN is on, and a list of VPN apps to open or install.

## 1.16.2
**Added**
- Foyer asks before turning Bluetooth off, since the remote needs it.

## 1.16.1
**Added**
- Hidden Developer options (press the version number 7 times in Updates).

**Changed**
- Where updates come from, the GitHub repo and the access token moved into Developer options.

## 1.16.0
**Changed**
- A new font everywhere: Plus Jakarta Sans.

## 1.15.2
**Changed**
- Friends' boxes get updates privately from your Foyer Drop server instead of a public download.

## 1.15.1
**Added**
- Reset for someone new: get a box ready to give away without redoing the TV setup.

## 1.15.0
**Added**
- A big clock and greeting on the home screen ("Good evening · 4° Cloudy").
- Light that follows the day: warmer at sunset, dimmer late at night.
- Apps open with a zoom from their tile.

## 1.14.10
**Fixed**
- No more black strip down the right side of All apps.

## 1.14.9
**Fixed**
- Changing the resolution from Foyer works on Android 14, and the menu shows 4K, 1080p and 720p.

## 1.14.8
**Fixed**
- Shows the TV's reason when it refuses a resolution change.

## 1.14.7
**Changed**
- The sample score alert is a Canadiens goal.

## 1.14.6
**Fixed**
- Continue Watching opens the show in Plex, not Plex's home page.

## 1.14.5
**Changed**
- Smaller score alert sizes.

## 1.14.4
**Changed**
- Prettier score alerts in the scoring team's colours. Medium is the default size.

## 1.14.3
**Added**
- Choose the score alert size.

## 1.14.2
**Changed**
- Teams, score alerts and the alert delay are all on one Sports page.

## 1.14.1
**Changed**
- Score alerts arrive within about 10 seconds during live games.

**Added**
- An optional delay, so a streamed game isn't spoiled.

## 1.14.0
**Added**
- **Score alerts:** a pop-up over whatever you're watching when your team scores.

## 1.13.3
**Removed**
- The dashboard feature.

## 1.13.2
**Fixed**
- Signing in on the dashboard.

## 1.13.1
**Changed**
- Updates checks by itself when you open it, and one button checks, downloads and installs.

## 1.13.0
**Added**
- A dashboard on the TV.

## 1.12.0
**Added**
- A new guided setup the first time Foyer starts: Wi-Fi, your name, how it looks and your apps.

## 1.11.1
**Fixed**
- Home on the remote goes back to Foyer's home screen from inside Foyer's settings.

## 1.11.0
**Added**
- Holiday looks that switch on by themselves: Halloween, Christmas, New Year and Easter.

## 1.10.1
**Changed**
- Updates install without the "Do you want to update this app?" box.

## 1.10.0
**Added**
- A sleep timer that works while other apps play, with a "still watching?" warning.

## 1.9.2
**Fixed**
- The remote helper switches itself back on after an update.

## 1.9.1
**Fixed**
- The remote helper can be switched on after Foyer updates itself.

## 1.9.0
**Added**
- Google TV Tune-up: switch off Google's ads, tracking and apps you don't use.
- Remote buttons: choose what the star, YouTube and Netflix buttons open.
- Soft click sounds as you move around.

## 1.8.1
**Added**
- Foyer asks before turning Wi-Fi off.

## 1.8.0
**Added**
- **TV settings inside Foyer:** Wi-Fi, Bluetooth, picture, sound, apps, storage, the TV's name and power.

## 1.7.0
**Added**
- Foyer Drop households: several people can use one TV with their own accounts.

## 1.6.2
**Changed**
- Simple and Liquid glass look clearly different.

## 1.6.1
**Added**
- One-press home screen takeover on Google TV, no computer needed.

## 1.6.0
**Added**
- Google TV and Android TV support: Foyer as the real home screen.

## 1.5.13
**Fixed**
- The phone page no longer zooms on a double tap.

## 1.5.12
**Fixed**
- The phone page's app list works while Settings is open on the TV.

## 1.5.11
**Fixed**
- Clearer reasons when the app list can't be sent to the phone page.

## 1.5.10
**Added**
- A remote on your phone, with typing, and password reset codes for Foyer Drop.

## 1.4.10
**Fixed**
- The phone page's app list updates reliably, and relinking a TV replaces its old entry.

## 1.4.9
**Changed**
- The phone page is now called Foyer Drop.

**Added**
- Choose which apps show on the phone page.

## 1.4.7
**Added**
- Open on TV from the phone page (apps and links).

## 1.3.7
**Changed**
- Notes, drawings and photos sent from your phone appear on the TV instantly.

## 1.3.5
**Added**
- Foyer Drop accounts, link codes, drawings and a new phone page.

## 1.2.5
**Added**
- Live sports scores with a team picker.
- Foyer Drop: send notes and photos to the TV from your phone.

## 1.1.5
**Added**
- The first versions of Foyer: your apps, glass design, weather, wallpapers and a screensaver.
