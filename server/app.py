"""Foyer Drop: send notes, drawings and photos from a phone to the Foyer launcher on your TV.

One small container. People sign in with an account; a TV is linked with a short code
(like Plex). Everything lives in /data (a SQLite file plus the pictures).
"""
import base64
import hashlib
import io
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid
from contextlib import closing
from pathlib import Path

from fastapi import Depends, FastAPI, File, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps

DATA = Path(os.environ.get("DATA_DIR", "/data"))
PHOTOS = DATA / "photos"
DRAWINGS = DATA / "drawings"
DB = DATA / "foyer.db"
MAX_PHOTO_PX = int(os.environ.get("MAX_PHOTO_PX", "1920"))  # keeps the stick's memory happy
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "25"))
DEFAULT_NOTE_HOURS = float(os.environ.get("NOTE_HOURS", "24"))
LINK_MINUTES = 10
CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O or 1/I to mix up

PHOTOS.mkdir(parents=True, exist_ok=True)
DRAWINGS.mkdir(parents=True, exist_ok=True)
app = FastAPI(title="Foyer Drop", docs_url=None, redoc_url=None)


# ───────────────────────── storage ─────────────────────────

def db():
    c = sqlite3.connect(DB, timeout=10)
    c.row_factory = sqlite3.Row
    return c


with closing(db()) as _c, _c:
    _c.executescript(
        """
        CREATE TABLE IF NOT EXISTS users(
          id INTEGER PRIMARY KEY, name TEXT UNIQUE COLLATE NOCASE, pw TEXT, salt TEXT,
          owner INTEGER DEFAULT 0, created REAL);
        CREATE TABLE IF NOT EXISTS tokens(
          hash TEXT PRIMARY KEY, id TEXT, user_id INTEGER, kind TEXT, label TEXT,
          created REAL, last REAL);
        CREATE TABLE IF NOT EXISTS notes(
          id TEXT PRIMARY KEY, user_id INTEGER, text TEXT, sender TEXT, created REAL, expires REAL);
        CREATE TABLE IF NOT EXISTS media(
          id TEXT PRIMARY KEY, user_id INTEGER, kind TEXT, sender TEXT, created REAL);
        CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
        """
    )


def _hash_token(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


def _hash_pw(pw: str, salt: bytes) -> str:
    return hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32).hex()


def _new_token(c, user_id: int, kind: str, label: str) -> str:
    raw = secrets.token_urlsafe(32)
    now = time.time()
    c.execute(
        "INSERT INTO tokens(hash,id,user_id,kind,label,created,last) VALUES(?,?,?,?,?,?,?)",
        (_hash_token(raw), uuid.uuid4().hex[:10], user_id, kind, label[:40], now, now),
    )
    return raw


def _invite(c, fresh=False) -> str:
    row = c.execute("SELECT v FROM meta WHERE k='invite'").fetchone()
    if row and not fresh:
        return row["v"]
    code = "-".join("".join(secrets.choice(CODE_LETTERS) for _ in range(4)) for _ in range(2))
    c.execute("INSERT OR REPLACE INTO meta(k,v) VALUES('invite',?)", (code,))
    return code


# ───────────────────────── small rate limiter ─────────────────────────

_hits: dict = {}
_hits_lock = threading.Lock()


def _ip(request: Request) -> str:
    return request.headers.get("cf-connecting-ip") or (request.client.host if request.client else "?")


def _limited(key: str, limit: int, seconds: int, add: bool = True) -> bool:
    """True when this key has already used up its tries."""
    now = time.time()
    with _hits_lock:
        if len(_hits) > 5000:
            for k in [k for k, v in _hits.items() if not v or v[-1] < now - 3600]:
                _hits.pop(k, None)
        times = [t for t in _hits.get(key, []) if t > now - seconds]
        over = len(times) >= limit
        if add and not over:
            times.append(now)
        _hits[key] = times
        return over


# ───────────────────────── who is asking ─────────────────────────

class Who:
    def __init__(self, row):
        self.user_id = row["user_id"]
        self.kind = row["kind"]
        self.token_hash = row["hash"]
        self.name = row["name"]
        self.owner = bool(row["owner"])


def who(authorization: str = Header(default="")) -> Who:
    raw = authorization[7:].strip() if authorization.lower().startswith("bearer ") else ""
    if not raw:
        raise HTTPException(401, "Sign in first")
    h = _hash_token(raw)
    with closing(db()) as c, c:
        row = c.execute(
            "SELECT t.hash,t.user_id,t.kind,t.last,u.name,u.owner FROM tokens t "
            "JOIN users u ON u.id=t.user_id WHERE t.hash=?",
            (h,),
        ).fetchone()
        if not row:
            raise HTTPException(401, "Sign in again")
        if time.time() - (row["last"] or 0) > 60:
            c.execute("UPDATE tokens SET last=? WHERE hash=?", (time.time(), h))
    return Who(row)


def web(w: Who = Depends(who)) -> Who:
    if w.kind != "web":
        raise HTTPException(403, "Do this from the web page")
    return w


# ───────────────────────── accounts ─────────────────────────

NAME_RE = re.compile(r"^[a-z0-9_.-]{3,30}$")


def _adopt_old_files(c, user_id: int):
    """Photos from before accounts existed go to the first account."""
    known = {r["id"] for r in c.execute("SELECT id FROM media")}
    for p in PHOTOS.glob("*.jpg"):
        if p.stem not in known:
            c.execute(
                "INSERT INTO media(id,user_id,kind,sender,created) VALUES(?,?,?,?,?)",
                (p.stem, user_id, "photo", "", p.stat().st_mtime),
            )


@app.get("/api/state")
def state():
    with closing(db()) as c:
        n = c.execute("SELECT COUNT(*) n FROM users").fetchone()["n"]
    return {"first": n == 0}


@app.post("/api/signup")
def signup(body: dict, request: Request):
    if _limited("signup:" + _ip(request), 10, 600):
        raise HTTPException(429, "Too many tries. Wait a few minutes.")
    name = str(body.get("name", "")).strip().lower()
    pw = str(body.get("password", ""))
    if not NAME_RE.match(name):
        raise HTTPException(400, "Pick a name of 3 to 30 letters or numbers (no spaces).")
    if len(pw) < 8:
        raise HTTPException(400, "Use a password of at least 8 characters.")
    with closing(db()) as c, c:
        first = c.execute("SELECT COUNT(*) n FROM users").fetchone()["n"] == 0
        if not first:
            given = str(body.get("invite", "")).strip().upper()
            if not given or not secrets.compare_digest(given, _invite(c)):
                raise HTTPException(403, "That invite code is not right. Ask the owner for the current one.")
        if c.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
            raise HTTPException(409, "That name is taken.")
        salt = secrets.token_bytes(16)
        cur = c.execute(
            "INSERT INTO users(name,pw,salt,owner,created) VALUES(?,?,?,?,?)",
            (name, _hash_pw(pw, salt), salt.hex(), 1 if first else 0, time.time()),
        )
        if first:
            _adopt_old_files(c, cur.lastrowid)
        token = _new_token(c, cur.lastrowid, "web", "web")
    return {"token": token, "name": name, "owner": first}


@app.post("/api/login")
def login(body: dict, request: Request):
    name = str(body.get("name", "")).strip().lower()
    key = f"login:{_ip(request)}:{name}"
    if _limited(key, 8, 600, add=False):
        raise HTTPException(429, "Too many tries. Wait a few minutes.")
    with closing(db()) as c, c:
        u = c.execute("SELECT * FROM users WHERE name=?", (name,)).fetchone()
        ok = bool(u) and secrets.compare_digest(
            _hash_pw(str(body.get("password", "")), bytes.fromhex(u["salt"])), u["pw"]
        )
        if not ok:
            _limited(key, 8, 600)
            raise HTTPException(401, "Wrong name or password.")
        token = _new_token(c, u["id"], "web", "web")
    return {"token": token, "name": u["name"], "owner": bool(u["owner"])}


@app.post("/api/logout")
def logout(w: Who = Depends(who)):
    with closing(db()) as c, c:
        c.execute("DELETE FROM tokens WHERE hash=?", (w.token_hash,))
    return {"ok": True}


@app.get("/api/ping")
def ping(w: Who = Depends(who)):
    return {"ok": True, "account": w.name}


@app.get("/api/me")
def me(w: Who = Depends(web)):
    with closing(db()) as c, c:
        tvs = c.execute(
            "SELECT id,label,created,last FROM tokens WHERE user_id=? AND kind='tv' ORDER BY created DESC",
            (w.user_id,),
        ).fetchall()
        out = {"name": w.name, "owner": w.owner, "tvs": [dict(r) for r in tvs]}
        if w.owner:
            out["invite"] = _invite(c)
    return out


@app.post("/api/invite/new")
def invite_new(w: Who = Depends(web)):
    if not w.owner:
        raise HTTPException(403, "Only the owner can do that")
    with closing(db()) as c, c:
        return {"invite": _invite(c, fresh=True)}


@app.delete("/api/tvs/{tv_id}")
def unlink_tv(tv_id: str, w: Who = Depends(web)):
    with closing(db()) as c, c:
        c.execute("DELETE FROM tokens WHERE id=? AND user_id=? AND kind='tv'", (tv_id, w.user_id))
    return {"ok": True}


# ───────────────────────── linking a TV with a short code ─────────────────────────

_links: dict = {}  # code -> {secret, created, name, token}
_links_lock = threading.Lock()


def _prune_links():
    cutoff = time.time() - LINK_MINUTES * 60
    for k in [k for k, v in _links.items() if v["created"] < cutoff]:
        _links.pop(k, None)


@app.post("/api/link/start")
def link_start(body: dict, request: Request):
    """The TV asks for a code to show on screen."""
    if _limited("linkstart:" + _ip(request), 12, 600):
        raise HTTPException(429, "Too many tries. Wait a few minutes.")
    with _links_lock:
        _prune_links()
        if len(_links) > 300:
            raise HTTPException(429, "Busy. Try again in a few minutes.")
        while True:
            code = "".join(secrets.choice(CODE_LETTERS) for _ in range(5))
            if code not in _links:
                break
        secret = secrets.token_urlsafe(24)
        _links[code] = {
            "secret": secret,
            "created": time.time(),
            "name": str(body.get("name", "")).strip()[:40] or "Fire TV",
            "token": None,
            "account": "",
        }
    return {"code": code, "secret": secret, "minutes": LINK_MINUTES}


@app.get("/api/link/poll")
def link_poll(secret: str = ""):
    """The TV checks whether someone typed its code yet."""
    with _links_lock:
        _prune_links()
        for code, v in _links.items():
            if secrets.compare_digest(v["secret"], secret):
                if v["token"]:
                    _links.pop(code, None)
                    return {"status": "linked", "token": v["token"], "account": v["account"]}
                return {"status": "waiting"}
    return {"status": "expired"}


@app.post("/api/link/claim")
def link_claim(body: dict, w: Who = Depends(web)):
    """Signed in on the web page: type the code the TV shows."""
    key = f"claim:{w.user_id}"
    if _limited(key, 10, 600, add=False):
        raise HTTPException(429, "Too many wrong codes. Wait a few minutes.")
    code = re.sub(r"[^A-Z0-9]", "", str(body.get("code", "")).upper())
    with _links_lock:
        _prune_links()
        v = _links.get(code)
        if not v or v["token"]:
            _limited(key, 10, 600)
            raise HTTPException(404, "That code is not on any TV right now. Check it and try again.")
        with closing(db()) as c, c:
            v["token"] = _new_token(c, w.user_id, "tv", v["name"])
        v["account"] = w.name
    return {"ok": True, "name": v["name"]}


# ───────────────────────── notes ─────────────────────────

@app.get("/api/notes")
def list_notes(w: Who = Depends(who)):
    now = time.time()
    with closing(db()) as c, c:
        c.execute("DELETE FROM notes WHERE expires IS NOT NULL AND expires<?", (now,))
        rows = c.execute(
            "SELECT id,text,sender,created,expires FROM notes WHERE user_id=? ORDER BY created DESC LIMIT 50",
            (w.user_id,),
        ).fetchall()
    return {"notes": [{**dict(r), "from": r["sender"]} for r in rows]}


@app.post("/api/notes")
def add_note(body: dict, w: Who = Depends(who)):
    text = str(body.get("text", "")).strip()[:300]
    if not text:
        raise HTTPException(400, "Write something first")
    try:
        hours = float(body.get("hours", DEFAULT_NOTE_HOURS))
    except Exception:
        hours = DEFAULT_NOTE_HOURS
    now = time.time()
    nid = uuid.uuid4().hex[:10]
    with closing(db()) as c, c:
        c.execute(
            "INSERT INTO notes(id,user_id,text,sender,created,expires) VALUES(?,?,?,?,?,?)",
            (nid, w.user_id, text, str(body.get("from", "")).strip()[:30], now,
             None if hours <= 0 else now + hours * 3600),
        )
    return {"id": nid}


@app.delete("/api/notes/{note_id}")
def delete_note(note_id: str, w: Who = Depends(who)):
    with closing(db()) as c, c:
        c.execute("DELETE FROM notes WHERE id=? AND user_id=?", (note_id, w.user_id))
    return {"ok": True}


# ───────────────────────── photos and drawings ─────────────────────────

def _media(c, user_id: int, kind: str, limit: int):
    return c.execute(
        "SELECT id,sender,created FROM media WHERE user_id=? AND kind=? ORDER BY created DESC LIMIT ?",
        (user_id, kind, limit),
    ).fetchall()


def _serve(w: Who, media_id: str, kind: str, folder: Path, ext: str, mime: str):
    if not media_id.isalnum():
        raise HTTPException(404)
    with closing(db()) as c:
        ok = c.execute(
            "SELECT 1 FROM media WHERE id=? AND user_id=? AND kind=?", (media_id, w.user_id, kind)
        ).fetchone()
    p = folder / f"{media_id}.{ext}"
    if not ok or not p.exists():
        raise HTTPException(404)
    return FileResponse(p, media_type=mime, headers={"Cache-Control": "private, max-age=86400"})


def _remove(w: Who, media_id: str, kind: str, folder: Path, ext: str):
    with closing(db()) as c, c:
        cur = c.execute(
            "DELETE FROM media WHERE id=? AND user_id=? AND kind=?", (media_id, w.user_id, kind)
        )
    if cur.rowcount and media_id.isalnum():
        (folder / f"{media_id}.{ext}").unlink(missing_ok=True)
    return {"ok": True}


@app.get("/api/photos")
def list_photos(w: Who = Depends(who)):
    with closing(db()) as c:
        return {"photos": [r["id"] for r in _media(c, w.user_id, "photo", 500)]}


@app.post("/api/photos")
async def add_photos(files: list[UploadFile] = File(...), w: Who = Depends(who)):
    saved = []
    for f in files:
        raw = await f.read()
        if len(raw) > MAX_UPLOAD_MB * 1024 * 1024:
            raise HTTPException(413, f"{f.filename} is bigger than {MAX_UPLOAD_MB} MB")
        pid = uuid.uuid4().hex[:12]
        try:
            with Image.open(io.BytesIO(raw)) as im:
                im = ImageOps.exif_transpose(im).convert("RGB")
                im.thumbnail((MAX_PHOTO_PX, MAX_PHOTO_PX))
                im.save(PHOTOS / f"{pid}.jpg", "JPEG", quality=85, optimize=True)
        except Exception:
            raise HTTPException(400, f"{f.filename} is not a picture I can read")
        with closing(db()) as c, c:
            c.execute(
                "INSERT INTO media(id,user_id,kind,sender,created) VALUES(?,?,?,?,?)",
                (pid, w.user_id, "photo", "", time.time()),
            )
        saved.append(pid)
    return {"saved": saved}


@app.get("/photos/{photo_id}.jpg")
def get_photo(photo_id: str, w: Who = Depends(who)):
    return _serve(w, photo_id, "photo", PHOTOS, "jpg", "image/jpeg")


@app.delete("/api/photos/{photo_id}")
def delete_photo(photo_id: str, w: Who = Depends(who)):
    return _remove(w, photo_id, "photo", PHOTOS, "jpg")


@app.get("/api/drawings")
def list_drawings(w: Who = Depends(who)):
    with closing(db()) as c:
        rows = _media(c, w.user_id, "drawing", 20)
    return {"drawings": [{"id": r["id"], "from": r["sender"], "created": r["created"]} for r in rows]}


@app.post("/api/drawings")
def add_drawing(body: dict, w: Who = Depends(who)):
    """Takes the canvas as a PNG data URL. See-through background, so it sits on the TV's glass."""
    data = str(body.get("image", ""))
    if "," in data:
        data = data.split(",", 1)[1]
    try:
        raw = base64.b64decode(data, validate=False)
    except Exception:
        raise HTTPException(400, "That drawing did not arrive properly")
    if not raw or len(raw) > 4 * 1024 * 1024:
        raise HTTPException(413, "That drawing is too big")
    did = uuid.uuid4().hex[:12]
    try:
        with Image.open(io.BytesIO(raw)) as im:
            if im.format != "PNG":
                raise ValueError("not a png")
            im = im.convert("RGBA")
            im.thumbnail((1200, 1200))
            im.save(DRAWINGS / f"{did}.png", "PNG", optimize=True)
    except Exception:
        raise HTTPException(400, "That drawing did not arrive properly")
    with closing(db()) as c, c:
        c.execute(
            "INSERT INTO media(id,user_id,kind,sender,created) VALUES(?,?,?,?,?)",
            (did, w.user_id, "drawing", str(body.get("from", "")).strip()[:30], time.time()),
        )
        old = c.execute(
            "SELECT id FROM media WHERE user_id=? AND kind='drawing' ORDER BY created DESC LIMIT -1 OFFSET 20",
            (w.user_id,),
        ).fetchall()
        for r in old:
            c.execute("DELETE FROM media WHERE id=?", (r["id"],))
            (DRAWINGS / f"{r['id']}.png").unlink(missing_ok=True)
    return {"id": did}


@app.get("/drawings/{drawing_id}.png")
def get_drawing(drawing_id: str, w: Who = Depends(who)):
    return _serve(w, drawing_id, "drawing", DRAWINGS, "png", "image/png")


@app.delete("/api/drawings/{drawing_id}")
def delete_drawing(drawing_id: str, w: Who = Depends(who)):
    return _remove(w, drawing_id, "drawing", DRAWINGS, "png")


app.mount("/", StaticFiles(directory=Path(__file__).parent / "static", html=True), name="static")
