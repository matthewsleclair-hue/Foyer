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

1. On the TV: Settings → Home screen → **Photo and note drop** → **Link this TV**. Enter the server address once.
2. The TV shows a 5-character code.
3. On the web page: sign in → **TVs** → type the code. The TV links itself within a few seconds.

Unlink a TV any time from the same page.

## Open on TV

The **Apps** tab on the web page lists the apps on your TV. Tap one and the TV opens it, or paste a link (a YouTube video, for example).
Foyer has to be on screen on the TV; a request that is not picked up within 20 seconds is dropped.

## Family and friends

The owner sees an **invite code** on the TVs page. Others pick "Create an account" and enter it.
Each account has its own TVs, notes, drawings and photos.

## Notes

- Everything is stored in `./data` (a SQLite file and the pictures). Back that folder up.
- Photos are shrunk to 1920 px on upload so the stick stays fast.
- Notes disappear after 24 hours by default (`NOTE_HOURS`), or choose how long on the page.
- Away from home: put it behind HTTPS (for example a Cloudflare Tunnel). Do not open the port raw to the internet.
- Upgrading from the first version (the one with `FOYER_TOKEN`): the token is no longer used. Photos already sent move to the first account you create. Old notes are not kept.
