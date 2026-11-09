# Setting up Foyer on a Fire TV Stick (no coding needed)

You need: a Fire TV Stick, a Mac or Windows computer on the same Wi-Fi, and the `Foyer.apk` file you were sent.
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

Windows users: run the same commands from Git Bash, or ask whoever gave you Foyer to run it for you.
To undo everything:

    bash tools/tuneup.sh 192.168.1.25 undo

## 6. Updates
Foyer checks for updates itself. If a new version is available, the Settings icon on the home screen gets an orange dot.
Open **Settings > Backup and updates > Updates** and choose **Download and install**.

## Troubleshooting
- **"unauthorized" or no Allow prompt:** on the stick, turn ADB debugging off and on, then run `adb connect` again.
- **Foyer's Tune-up buttons say the stick hung up:** this is a Fire OS limit. Use step 5 from a computer instead.
- **Home button does nothing:** repeat the `pm grant` command in step 3, then turn the Home button off and on in Foyer's settings.
- **Reinstalled and Home stopped working:** turn the Home button service off and on again in Foyer's settings.
