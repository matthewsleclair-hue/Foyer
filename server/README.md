# Foyer Drop (optional server)

A tiny web app you host yourself. Send **notes** and **photos** from any phone;
Foyer shows the notes on the home screen and can use the photos as its screensaver.

## Run it (Docker)

```bash
cd server
echo "FOYER_TOKEN=$(openssl rand -hex 24)" > .env   # the password. Keep it private.
docker compose up -d --build
cat .env                                            # copy the token for later
```

Open `http://<your-server-ip>:8080` on a phone, enter the token once, then send notes and photos.

## Connect Foyer

On the TV: Settings → Home screen → **Photo and note drop**. Set the address
(for example `192.168.1.50:8080`) and the token (typing from your phone works), then Test connection.
For the screensaver: Settings → Screensaver and power → Screensaver → Background → **Photo drop**.

## Notes

- Photos are shrunk to 1920 px on upload so the stick stays fast.
- Notes disappear after 24 hours by default (`NOTE_HOURS`), or pick "keep" on the page.
- Reaching it away from home: put it behind HTTPS (a reverse proxy or a tunnel). Do not open the port raw to the internet.
- Never commit your `.env` file.
