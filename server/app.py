"""Foyer Drop: send notes, drawings and photos from a phone to the Foyer launcher on your TV.

One small container. People sign in with an account; a TV is linked with a short code
(like Plex). Everything lives in /data (a SQLite file plus the pictures).
"""
import asyncio
import base64
import hashlib
import io
import json
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
        CREATE TABLE IF NOT EXISTS tv_apps(tv_id TEXT PRIMARY KEY, apps TEXT, updated REAL);
        CREATE TABLE IF NOT EXISTS resets(user_id INTEGER PRIMARY KEY, hash TEXT, expires REAL);
        CREATE TABLE IF NOT EXISTS members(owner_id INTEGER, member_id INTEGER, created REAL,
          PRIMARY KEY(owner_id, member_id));
        CREATE TABLE IF NOT EXISTS joins(hash TEXT PRIMARY KEY, owner_id INTEGER, expires REAL);
        CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
        """
    )


with closing(db()) as _c, _c:
    try:
        _c.execute("ALTER TABLE tokens ADD COLUMN device TEXT")  # added later; fine if it exists
    except sqlite3.OperationalError:
        pass


def _hash_token(t: str) -> str:
    return hashlib.sha256(t.encode()).hexdigest()


def _hash_pw(pw: str, salt: bytes) -> str:
    return hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32).hex()


def _new_token(c, user_id: int, kind: str, label: str, device: str = "") -> str:
    raw = secrets.token_urlsafe(32)
    now = time.time()
    if kind == "tv" and device:
        # the same TV linked again replaces its old entry instead of piling up copies
        for r in c.execute(
            "SELECT id FROM tokens WHERE user_id=? AND kind='tv' AND device=?", (user_id, device)
        ).fetchall():
            c.execute("DELETE FROM tv_apps WHERE tv_id=?", (r["id"],))
        c.execute("DELETE FROM tokens WHERE user_id=? AND kind='tv' AND device=?", (user_id, device))
    c.execute(
        "INSERT INTO tokens(hash,id,user_id,kind,label,created,last,device) VALUES(?,?,?,?,?,?,?,?)",
        (_hash_token(raw), uuid.uuid4().hex[:10], user_id, kind, label[:40], now, now, device[:64]),
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
    """Who is asking, and whose household they are acting in.

    user_id is the household whose TVs, notes and photos this request touches. For most people
    that is their own account. A member of someone else's household can act there instead
    (the web page sends X-Foyer-Home); self_id is always the person actually signed in.
    """

    def __init__(self, row):
        self.self_id = row["user_id"]
        self.user_id = row["user_id"]
        self.kind = row["kind"]
        self.token_hash = row["hash"]
        self.token_id = row["id"]
        self.name = row["name"]
        self.owner = bool(row["owner"])  # runs this server
        self.home_name = row["name"]

    @property
    def home_owner(self) -> bool:
        return self.self_id == self.user_id


def who(authorization: str = Header(default=""), x_foyer_home: str = Header(default="")) -> Who:
    raw = authorization[7:].strip() if authorization.lower().startswith("bearer ") else ""
    if not raw:
        raise HTTPException(401, "Sign in first")
    h = _hash_token(raw)
    with closing(db()) as c, c:
        row = c.execute(
            "SELECT t.hash,t.id,t.user_id,t.kind,t.last,u.name,u.owner FROM tokens t "
            "JOIN users u ON u.id=t.user_id WHERE t.hash=?",
            (h,),
        ).fetchone()
        if not row:
            raise HTTPException(401, "Sign in again")
        if time.time() - (row["last"] or 0) > 60:
            c.execute("UPDATE tokens SET last=? WHERE hash=?", (time.time(), h))
        w = Who(row)
        home = x_foyer_home.strip()
        if home and row["kind"] == "web" and home != str(w.self_id):
            m = c.execute(
                "SELECT u.id,u.name FROM members m JOIN users u ON u.id=m.owner_id "
                "WHERE m.member_id=? AND m.owner_id=?",
                (w.self_id, int(home) if home.isdigit() else -1),
            ).fetchone()
            if not m:
                raise HTTPException(403, "You are not in that household any more.")
            w.user_id = m["id"]
            w.home_name = m["name"]
    return w


def web(w: Who = Depends(who)) -> Who:
    if w.kind != "web":
        raise HTTPException(403, "Do this from the web page")
    return w


def home_owner(w: Who = Depends(web)) -> Who:
    """For things only the household's owner may do (linking TVs, adding people)."""
    if not w.home_owner:
        raise HTTPException(403, f"Only {w.home_name} can do that in this household.")
    return w


def _join_owner(c, code: str):
    """The household a join code belongs to, or None."""
    code = re.sub(r"[^A-Z0-9]", "", code.upper())
    if not code:
        return None
    row = c.execute(
        "SELECT owner_id FROM joins WHERE hash=? AND expires>?", (_hash_token(code), time.time())
    ).fetchone()
    return row["owner_id"] if row else None


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
        join_home = None
        if not first:
            # either the server's invite code, or a household code from someone already here
            given = re.sub(r"[^A-Z0-9]", "", str(body.get("invite", "")).upper())
            server_code = re.sub(r"[^A-Z0-9]", "", _invite(c))
            if not given or not secrets.compare_digest(given, server_code):
                join_home = _join_owner(c, given)
                if join_home is None:
                    raise HTTPException(403, "That code is not right, or it ran out. Ask for a new one.")
        if c.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
            raise HTTPException(409, "That name is taken.")
        salt = secrets.token_bytes(16)
        cur = c.execute(
            "INSERT INTO users(name,pw,salt,owner,created) VALUES(?,?,?,?,?)",
            (name, _hash_pw(pw, salt), salt.hex(), 1 if first else 0, time.time()),
        )
        if first:
            _adopt_old_files(c, cur.lastrowid)
        if join_home is not None:
            c.execute(
                "INSERT OR IGNORE INTO members(owner_id,member_id,created) VALUES(?,?,?)",
                (join_home, cur.lastrowid, time.time()),
            )
        token = _new_token(c, cur.lastrowid, "web", "web")
    return {"token": token, "name": name, "owner": first, "id": cur.lastrowid, "home": join_home}


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
    return {"token": token, "name": u["name"], "owner": bool(u["owner"]), "id": u["id"]}


def make_reset(c, user_id: int) -> str:
    """A one-time code that lets someone choose a new password. Good for a day."""
    code = "-".join("".join(secrets.choice(CODE_LETTERS) for _ in range(4)) for _ in range(3))
    c.execute(
        "INSERT OR REPLACE INTO resets(user_id,hash,expires) VALUES(?,?,?)",
        (user_id, _hash_token(code), time.time() + 24 * 3600),
    )
    return code


def _set_password(c, user_id: int, pw: str):
    if len(pw) < 8:
        raise HTTPException(400, "Use a password of at least 8 characters.")
    salt = secrets.token_bytes(16)
    c.execute("UPDATE users SET pw=?, salt=? WHERE id=?", (_hash_pw(pw, salt), salt.hex(), user_id))


@app.get("/api/accounts")
def accounts(w: Who = Depends(web)):
    if not w.owner:
        raise HTTPException(403, "Only the owner can do that")
    with closing(db()) as c:
        rows = c.execute("SELECT name,owner,created FROM users ORDER BY created").fetchall()
    return {"accounts": [dict(r) for r in rows]}


@app.post("/api/accounts/{name}/reset")
def account_reset(name: str, w: Who = Depends(web)):
    """The owner makes a reset code and passes it on (text, in person...)."""
    if not w.owner:
        raise HTTPException(403, "Only the owner can do that")
    with closing(db()) as c, c:
        u = c.execute("SELECT id,name FROM users WHERE name=?", (name.strip().lower(),)).fetchone()
        if not u:
            raise HTTPException(404, "No account with that name")
        return {"name": u["name"], "code": make_reset(c, u["id"])}


@app.post("/api/reset")
def reset_password(body: dict, request: Request):
    """Signed out: use a reset code to choose a new password."""
    name = str(body.get("name", "")).strip().lower()
    key = f"reset:{_ip(request)}:{name}"
    if _limited(key, 8, 600, add=False):
        raise HTTPException(429, "Too many tries. Wait a few minutes.")
    code = re.sub(r"[^A-Z0-9]", "", str(body.get("code", "")).upper())
    code = "-".join(code[i:i + 4] for i in range(0, len(code), 4))
    with closing(db()) as c, c:
        row = c.execute(
            "SELECT u.id,u.name,u.owner,r.hash,r.expires FROM users u JOIN resets r ON r.user_id=u.id "
            "WHERE u.name=?",
            (name,),
        ).fetchone()
        ok = bool(row) and row["expires"] > time.time() and secrets.compare_digest(row["hash"], _hash_token(code))
        if not ok:
            _limited(key, 8, 600)
            raise HTTPException(403, "That reset code is not right, or it ran out. Ask the owner for a new one.")
        _set_password(c, row["id"], str(body.get("password", "")))
        c.execute("DELETE FROM resets WHERE user_id=?", (row["id"],))
        c.execute("DELETE FROM tokens WHERE user_id=? AND kind='web'", (row["id"],))  # sign out everywhere
        token = _new_token(c, row["id"], "web", "web")
    return {"token": token, "name": row["name"], "owner": bool(row["owner"]), "id": row["id"]}


@app.post("/api/password")
def change_password(body: dict, w: Who = Depends(web)):
    with closing(db()) as c, c:
        u = c.execute("SELECT * FROM users WHERE id=?", (w.self_id,)).fetchone()
        if not secrets.compare_digest(_hash_pw(str(body.get("old", "")), bytes.fromhex(u["salt"])), u["pw"]):
            raise HTTPException(403, "Your current password is not right.")
        _set_password(c, w.self_id, str(body.get("new", "")))
        # other phones signed in to this account have to sign in again
        c.execute("DELETE FROM tokens WHERE user_id=? AND kind='web' AND hash!=?", (w.self_id, w.token_hash))
    return {"ok": True}


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
        out = {
            "id": w.self_id,
            "name": w.name,
            "owner": w.owner,
            "tvs": [dict(r) for r in tvs],
            "home": {"id": w.user_id, "name": w.home_name, "mine": w.home_owner},
        }
        if w.owner:
            out["invite"] = _invite(c)
    return out


# ───────────────────────── households: several people, one TV ─────────────────────────

JOIN_HOURS = 24


@app.get("/api/homes")
def homes(w: Who = Depends(web)):
    """My own household, the ones I have joined, and the people in mine."""
    with closing(db()) as c:
        joined = c.execute(
            "SELECT u.id,u.name FROM members m JOIN users u ON u.id=m.owner_id WHERE m.member_id=? ORDER BY u.name",
            (w.self_id,),
        ).fetchall()
        people = c.execute(
            "SELECT u.id,u.name FROM members m JOIN users u ON u.id=m.member_id WHERE m.owner_id=? ORDER BY u.name",
            (w.self_id,),
        ).fetchall()
        my_tvs = c.execute(
            "SELECT COUNT(*) n FROM tokens WHERE user_id=? AND kind='tv'", (w.self_id,)
        ).fetchone()["n"]
    return {
        "homes": [{"id": w.self_id, "name": w.name, "mine": True, "tvs": my_tvs}]
        + [{"id": r["id"], "name": r["name"], "mine": False} for r in joined],
        "people": [dict(r) for r in people],
    }


@app.post("/api/home/invite")
def home_invite(w: Who = Depends(web)):
    """A code that lets someone join MY household (new account or existing one)."""
    code = "".join(secrets.choice(CODE_LETTERS) for _ in range(6))
    with closing(db()) as c, c:
        c.execute("DELETE FROM joins WHERE owner_id=? OR expires<?", (w.self_id, time.time()))
        c.execute(
            "INSERT INTO joins(hash,owner_id,expires) VALUES(?,?,?)",
            (_hash_token(code), w.self_id, time.time() + JOIN_HOURS * 3600),
        )
    return {"code": f"{code[:3]}-{code[3:]}", "hours": JOIN_HOURS}


@app.post("/api/home/join")
def home_join(body: dict, w: Who = Depends(web)):
    key = f"join:{w.self_id}"
    if _limited(key, 10, 600, add=False):
        raise HTTPException(429, "Too many wrong codes. Wait a few minutes.")
    with closing(db()) as c, c:
        owner_id = _join_owner(c, str(body.get("code", "")))
        if owner_id is None:
            _limited(key, 10, 600)
            raise HTTPException(404, "That code is not right, or it ran out. Ask for a new one.")
        if owner_id == w.self_id:
            raise HTTPException(400, "That is your own household's code. Give it to someone else.")
        c.execute(
            "INSERT OR IGNORE INTO members(owner_id,member_id,created) VALUES(?,?,?)",
            (owner_id, w.self_id, time.time()),
        )
        name = c.execute("SELECT name FROM users WHERE id=?", (owner_id,)).fetchone()["name"]
    return {"id": owner_id, "name": name}


@app.delete("/api/home/people/{member_id}")
def home_remove(member_id: int, w: Who = Depends(web)):
    """Remove someone from my household."""
    with closing(db()) as c, c:
        c.execute("DELETE FROM members WHERE owner_id=? AND member_id=?", (w.self_id, member_id))
    return {"ok": True}


@app.delete("/api/homes/{owner_id}")
def home_leave(owner_id: int, w: Who = Depends(web)):
    """Leave a household I joined."""
    with closing(db()) as c, c:
        c.execute("DELETE FROM members WHERE owner_id=? AND member_id=?", (owner_id, w.self_id))
    return {"ok": True}


@app.post("/api/invite/new")
def invite_new(w: Who = Depends(web)):
    if not w.owner:
        raise HTTPException(403, "Only the owner can do that")
    with closing(db()) as c, c:
        return {"invite": _invite(c, fresh=True)}


@app.delete("/api/tvs/{tv_id}")
def unlink_tv(tv_id: str, w: Who = Depends(home_owner)):
    with closing(db()) as c, c:
        cur = c.execute("DELETE FROM tokens WHERE id=? AND user_id=? AND kind='tv'", (tv_id, w.user_id))
        if cur.rowcount:
            c.execute("DELETE FROM tv_apps WHERE tv_id=?", (tv_id,))
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
            "device": re.sub(r"[^A-Za-z0-9_-]", "", str(body.get("device", "")))[:64],
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
def link_claim(body: dict, w: Who = Depends(home_owner)):
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
            v["token"] = _new_token(c, w.user_id, "tv", v["name"], v.get("device", ""))
        v["account"] = w.name
    return {"ok": True, "name": v["name"]}


# ───────────────────────── telling the TV right away ─────────────────────────
# The TV keeps one request open on /api/wait. The moment something is sent we answer it,
# so notes, drawings and photos show up instantly instead of on the next check.

_BOOT = int(time.time() * 1000)
_versions: dict = {}
_waiters: dict = {}
_loop = None


@app.on_event("startup")
async def _remember_loop():
    global _loop
    _loop = asyncio.get_running_loop()


def _wake(user_id: int):
    for ev in list(_waiters.get(user_id, ())):
        ev.set()


def bump(user_id: int):
    """Call after anything the TV shows has changed (safe from worker threads)."""
    _versions[user_id] = _versions.get(user_id, _BOOT) + 1
    if _loop is not None:
        _loop.call_soon_threadsafe(_wake, user_id)


@app.get("/api/wait")
async def wait(v: int = 0, w: Who = Depends(who)):
    cur = _versions.get(w.user_id, _BOOT)
    if w.kind == "tv":
        _tv_seen[w.token_id] = time.time()
    if v == cur:
        ev = asyncio.Event()
        _waiters.setdefault(w.user_id, set()).add(ev)
        try:
            await asyncio.wait_for(ev.wait(), timeout=25)
        except asyncio.TimeoutError:
            pass
        finally:
            _waiters.get(w.user_id, set()).discard(ev)
            if not _waiters.get(w.user_id):
                _waiters.pop(w.user_id, None)
        cur = _versions.get(w.user_id, _BOOT)
        if w.kind == "tv":
            _tv_seen[w.token_id] = time.time()
    return {"v": cur}


# ───────────────────────── open things on the TV from the phone ─────────────────────────

_tv_seen: dict = {}  # tv id -> last time Foyer was on screen and listening
_commands: dict = {}  # tv id -> things to do, delivered once
_cmd_lock = threading.Lock()
COMMAND_SECONDS = 20  # older than this is dropped, so nothing opens by surprise later
B64_RE = re.compile(r"^[A-Za-z0-9+/=]*$")


def _take_commands(tv_id: str):
    cutoff = time.time() - COMMAND_SECONDS
    with _cmd_lock:
        return [c for c in _commands.pop(tv_id, []) if c["created"] > cutoff]


# The remote: key presses and typed text. These go to a listener that also runs while another
# app is on screen, so they have their own queue, separate from "open this app".
_keys: dict = {}  # tv id -> waiting presses
_key_events: dict = {}  # tv id -> asyncio.Event for the TV that is listening
_remote_seen: dict = {}
KEY_SECONDS = 5
KEYS = {"up", "down", "left", "right", "ok", "back", "home", "menu", "play", "rewind", "forward"}


def _wake_keys(tv_id: str):
    ev = _key_events.get(tv_id)
    if ev:
        ev.set()


def _take_keys(tv_id: str):
    cutoff = time.time() - KEY_SECONDS
    with _cmd_lock:
        return [{"type": k["type"], "value": k["value"]} for k in _keys.pop(tv_id, []) if k["created"] > cutoff]


@app.get("/api/tv/keys")
async def tv_keys(w: Who = Depends(who)):
    """The TV waits here; we answer the moment a remote button is pressed on the phone."""
    if w.kind != "tv":
        raise HTTPException(403, "Only a TV listens here")
    tv = w.token_id
    _remote_seen[tv] = time.time()
    out = _take_keys(tv)
    if not out:
        ev = asyncio.Event()
        _key_events[tv] = ev
        try:
            await asyncio.wait_for(ev.wait(), timeout=25)
        except asyncio.TimeoutError:
            pass
        finally:
            if _key_events.get(tv) is ev:
                _key_events.pop(tv, None)
        out = _take_keys(tv)
        _remote_seen[tv] = time.time()
    return {"keys": out}


@app.post("/api/tvs/{tv_id}/key")
def tv_key(tv_id: str, body: dict, w: Who = Depends(web)):
    with closing(db()) as c:
        ok = c.execute(
            "SELECT 1 FROM tokens WHERE id=? AND user_id=? AND kind='tv'", (tv_id, w.user_id)
        ).fetchone()
    if not ok:
        raise HTTPException(404, "That TV is not linked any more")
    key = str(body.get("key", ""))
    text = body.get("text")
    if key in KEYS:
        k = {"type": "key", "value": key}
    elif isinstance(text, str):
        k = {"type": "text", "value": text[:300]}
    else:
        raise HTTPException(400, "Unknown button")
    k["created"] = time.time()
    with _cmd_lock:
        q = [x for x in _keys.get(tv_id, []) if x["created"] > k["created"] - KEY_SECONDS]
        _keys[tv_id] = (q + [k])[-30:]
    if _loop is not None:
        _loop.call_soon_threadsafe(_wake_keys, tv_id)
    return {"ok": True, "listening": time.time() - _remote_seen.get(tv_id, 0) < 40}


@app.post("/api/tv/apps")
def tv_apps(body: dict, w: Who = Depends(who)):
    """The TV tells us which apps it has, so the phone page can show them."""
    if w.kind != "tv":
        raise HTTPException(403, "Only a TV sends this")
    apps = []
    for a in (body.get("apps") or [])[:200]:
        if not isinstance(a, dict):
            continue
        pkg = str(a.get("package", ""))[:150]
        icon = str(a.get("icon", ""))
        if not re.match(r"^[A-Za-z0-9._]+$", pkg):
            continue
        if len(icon) > 60000 or not B64_RE.match(icon):
            icon = ""
        apps.append({"package": pkg, "label": str(a.get("label", pkg))[:60], "icon": icon})
    with closing(db()) as c, c:
        c.execute(
            "INSERT OR REPLACE INTO tv_apps(tv_id,apps,updated) VALUES(?,?,?)",
            (w.token_id, json.dumps(apps), time.time()),
        )
    return {"ok": True, "count": len(apps)}


@app.get("/api/tvs/apps")
def tvs_apps(w: Who = Depends(web)):
    now = time.time()
    with closing(db()) as c:
        rows = c.execute(
            "SELECT t.id,t.label,a.apps FROM tokens t LEFT JOIN tv_apps a ON a.tv_id=t.id "
            "WHERE t.user_id=? AND t.kind='tv' ORDER BY t.created DESC",
            (w.user_id,),
        ).fetchall()
    return {
        "tvs": [
            {
                "id": r["id"],
                "label": r["label"] or "Fire TV",
                "ready": now - _tv_seen.get(r["id"], 0) < 40,
                "remote": now - _remote_seen.get(r["id"], 0) < 40,
                "apps": json.loads(r["apps"]) if r["apps"] else [],
            }
            for r in rows
        ]
    }


@app.post("/api/tvs/{tv_id}/send")
def tv_send(tv_id: str, body: dict, w: Who = Depends(web)):
    """Open an app, or a link, on one of your TVs."""
    with closing(db()) as c:
        ok = c.execute(
            "SELECT 1 FROM tokens WHERE id=? AND user_id=? AND kind='tv'", (tv_id, w.user_id)
        ).fetchone()
    if not ok:
        raise HTTPException(404, "That TV is not linked any more")
    pkg = str(body.get("package", "")).strip()
    url = str(body.get("url", "")).strip()
    if pkg and re.match(r"^[A-Za-z0-9._]{1,150}$", pkg):
        cmd = {"type": "open", "value": pkg}
    elif url:
        if not re.match(r"^https?://[^\s]{3,800}$", url):
            raise HTTPException(400, "That does not look like a link. It should start with https://")
        cmd = {"type": "url", "value": url}
    else:
        raise HTTPException(400, "Nothing to open")
    cmd["created"] = time.time()
    with _cmd_lock:
        q = [c for c in _commands.get(tv_id, []) if c["created"] > cmd["created"] - COMMAND_SECONDS]
        _commands[tv_id] = (q + [cmd])[-5:]
    bump(w.user_id)
    return {"ok": True, "ready": time.time() - _tv_seen.get(tv_id, 0) < 40}


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
            (nid, w.user_id, text, (str(body.get("from", "")).strip() or w.name)[:30], now,
             None if hours <= 0 else now + hours * 3600),
        )
    bump(w.user_id)
    return {"id": nid}


@app.delete("/api/notes/{note_id}")
def delete_note(note_id: str, w: Who = Depends(who)):
    with closing(db()) as c, c:
        c.execute("DELETE FROM notes WHERE id=? AND user_id=?", (note_id, w.user_id))
    bump(w.user_id)
    return {"ok": True}


# ───────────────────────── photos and drawings ─────────────────────────

@app.get("/api/feed")
def feed(w: Who = Depends(who)):
    """Everything the TV's home screen needs in one quick call (it asks every few seconds)."""
    now = time.time()
    with closing(db()) as c:
        notes = c.execute(
            "SELECT id,text,sender FROM notes WHERE user_id=? AND (expires IS NULL OR expires>?) "
            "ORDER BY created DESC LIMIT 50",
            (w.user_id, now),
        ).fetchall()
        d = _media(c, w.user_id, "drawing", 1)
        photos = c.execute(
            "SELECT COUNT(*) n, MAX(created) m FROM media WHERE user_id=? AND kind='photo'", (w.user_id,)
        ).fetchone()
    out = {
        "notes": [{"id": r["id"], "text": r["text"], "from": r["sender"]} for r in notes],
        "drawing": {"id": d[0]["id"], "from": d[0]["sender"]} if d else None,
        "photos": f"{photos['n']}:{photos['m'] or 0}",
    }
    if w.kind == "tv":
        _tv_seen[w.token_id] = now
        out["commands"] = [{"type": c["type"], "value": c["value"]} for c in _take_commands(w.token_id)]
    return out

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
    bump(w.user_id)
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
    bump(w.user_id)
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
            (did, w.user_id, "drawing", (str(body.get("from", "")).strip() or w.name)[:30], time.time()),
        )
        old = c.execute(
            "SELECT id FROM media WHERE user_id=? AND kind='drawing' ORDER BY created DESC LIMIT -1 OFFSET 20",
            (w.user_id,),
        ).fetchall()
        for r in old:
            c.execute("DELETE FROM media WHERE id=?", (r["id"],))
            (DRAWINGS / f"{r['id']}.png").unlink(missing_ok=True)
    bump(w.user_id)
    return {"id": did}


@app.get("/drawings/{drawing_id}.png")
def get_drawing(drawing_id: str, w: Who = Depends(who)):
    return _serve(w, drawing_id, "drawing", DRAWINGS, "png", "image/png")


@app.delete("/api/drawings/{drawing_id}")
def delete_drawing(drawing_id: str, w: Who = Depends(who)):
    return _remove(w, drawing_id, "drawing", DRAWINGS, "png")



# ── Foyer updates for your people ──
# tools/publish.sh copies Foyer.apk and update.json into DATA/releases. Only TVs and people
# signed in to this server can see or download them, so Foyer is never public.
REL = DATA / "releases"


@app.get("/api/update")
def update_info(w: Who = Depends(who)):
    f = REL / "update.json"
    if not f.exists() or not (REL / "Foyer.apk").exists():
        raise HTTPException(404, "No Foyer release on this server yet")
    try:
        j = json.loads(f.read_text())
    except Exception:
        raise HTTPException(500, "update.json is not readable")
    return {"version": str(j.get("version", "")), "build": int(j.get("build", 0) or 0), "notes": str(j.get("notes", ""))}


@app.get("/api/update/apk")
def update_apk(w: Who = Depends(who)):
    f = REL / "Foyer.apk"
    if not f.exists():
        raise HTTPException(404, "No Foyer release on this server yet")
    return FileResponse(f, media_type="application/vnd.android.package-archive", filename="Foyer.apk")


app.mount("/", StaticFiles(directory=Path(__file__).parent / "static", html=True), name="static")
