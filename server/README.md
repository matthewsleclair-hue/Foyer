# Foyer Drop (optional server)

A tiny web app you host yourself. Send **notes**, **drawings** and **photos** from any phone.
Foyer shows notes and the newest drawing on the home screen and can use the photos as its screensaver.

## Run it (Docker)

```bash
cd server
docker compose up -d --build
```

Open `http://<your-server-ip>:8080` (or your own domain) and create the first account. That account is the owner.

## Link a TV (no long tokens)

1. On the TV: Settings → Home screen → **Foyer Drop** → **Link this TV**. Enter the server address once.
2. The TV shows a 5-character code.
3. On the web page: sign in → **TVs** → type the code. The TV links itself within a few seconds.

Unlink a TV any time from the same page.

## Open on TV

The **Apps** tab on the web page lists the apps on your TV. Tap one and the TV opens it, or paste a link (a YouTube video, for example).
Foyer has to be on screen on the TV; a request that is not picked up within 20 seconds is dropped.

## Remote

The **Remote** tab has arrows, OK, Back, Home, Menu and play buttons, plus a box that types on the TV.
It works fully inside Foyer. In other apps it needs Foyer's Home button service turned on: Back, Home and the
play buttons always work there, while arrows, OK and typing work in many apps but not in ones that draw
their own screens (Netflix, YouTube).

## Forgotten passwords

The owner opens **TVs → Accounts → Reset code** and passes the code on. The person taps "Forgot password?"
on the sign-in page. If the owner is locked out, run this on the server:

```bash
docker compose exec foyer-drop python reset.py <account name>
```

## Several people, one TV (households)

A TV belongs to one account, and that person can let others use it:

1. The TV's owner opens **TVs → People who can use my TVs → Add a person** and gets a code (good for 24 hours).
2. Someone new chooses "Create an account" and enters that code. Someone who already has an account enters it under **TVs → Join someone's household**.
3. They can now send notes, drawings and photos, open apps and use the remote on that TV, signed in as themselves. Notes show their name.

Only the owner can link or unlink TVs and add or remove people. A person in more than one household picks which TVs to send to with the buttons at the top of the page.

## Family and friends

The owner sees an **invite code** on the TVs page. Others pick "Create an account" and enter it.
Each account has its own TVs, notes, drawings and photos.

## Notes

- Everything is stored in `./data` (a SQLite file and the pictures). Back that folder up.
- Photos are shrunk to 1920 px on upload so the stick stays fast.
- Notes disappear after 24 hours by default (`NOTE_HOURS`), or choose how long on the page.
- Away from home: put it behind HTTPS (for example a Cloudflare Tunnel). Do not open the port raw to the internet.
- Upgrading from the first version (the one with `FOYER_TOKEN`): the token is no longer used. Photos already sent move to the first account you create. Old notes are not kept.
