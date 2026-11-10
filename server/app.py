"""Foyer Drop: notes and photos you send from a phone to the Foyer launcher on your TV.

One small container. Set FOYER_TOKEN to a long random string. Data lives in /data.
"""
import json
import os
import secrets
import threading
import time
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps

TOKEN = os.environ.get("FOYER_TOKEN", "")
DATA = Path(os.environ.get("DATA_DIR", "/data"))
PHOTOS = DATA / "photos"
NOTES_FILE = DATA / "notes.json"
MAX_PHOTO_PX = int(os.environ.get("MAX_PHOTO_PX", "1920"))  # keeps the stick's memory happy
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "25"))
DEFAULT_NOTE_HOURS = float(os.environ.get("NOTE_HOURS", "24"))

PHOTOS.mkdir(parents=True, exist_ok=True)
_lock = threading.Lock()
app = FastAPI(title="Foyer Drop", docs_url=None, redoc_url=None)


def auth(authorization: str = Header(default=""), token: str = ""):
    """Accepts 'Authorization: Bearer <token>' or ?token=<token> (for images in the TV app)."""
    if not TOKEN:
        raise HTTPException(500, "FOYER_TOKEN is not set on the server")
    given = authorization[7:] if authorization.lower().startswith("bearer ") else token
    if not given or not secrets.compare_digest(given, TOKEN):
        raise HTTPException(401, "Wrong token")


def _load_notes():
    try:
        return json.loads(NOTES_FILE.read_text())
    except Exception:
        return []


def _save_notes(notes):
    tmp = NOTES_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(notes))
    tmp.replace(NOTES_FILE)


def _live(notes):
    now = time.time()
    return [n for n in notes if not n.get("expires") or n["expires"] > now]


@app.get("/api/ping")
def ping(_: None = Depends(auth)):
    return {"ok": True, "time": time.time()}


@app.get("/api/notes")
def list_notes(_: None = Depends(auth)):
    with _lock:
        notes = _live(_load_notes())
    return {"notes": sorted(notes, key=lambda n: n["created"], reverse=True)}


@app.post("/api/notes")
def add_note(body: dict, _: None = Depends(auth)):
    text = str(body.get("text", "")).strip()[:300]
    if not text:
        raise HTTPException(400, "Empty note")
    hours = body.get("hours", DEFAULT_NOTE_HOURS)
    try:
        hours = float(hours)
    except Exception:
        hours = DEFAULT_NOTE_HOURS
    now = time.time()
    note = {
        "id": uuid.uuid4().hex[:10],
        "text": text,
        "from": str(body.get("from", "")).strip()[:30],
        "created": now,
        "expires": None if hours <= 0 else now + hours * 3600,
    }
    with _lock:
        notes = _live(_load_notes())
        notes.append(note)
        _save_notes(notes[-50:])
    return note


@app.delete("/api/notes/{note_id}")
def delete_note(note_id: str, _: None = Depends(auth)):
    with _lock:
        notes = [n for n in _load_notes() if n["id"] != note_id]
        _save_notes(notes)
    return {"ok": True}


def _photo_ids():
    files = sorted(PHOTOS.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
    return [p.stem for p in files]


@app.get("/api/photos")
def list_photos(_: None = Depends(auth)):
    return {"photos": _photo_ids()}


@app.post("/api/photos")
async def add_photos(files: list[UploadFile] = File(...), _: None = Depends(auth)):
    saved = []
    for f in files:
        raw = await f.read()
        if len(raw) > MAX_UPLOAD_MB * 1024 * 1024:
            raise HTTPException(413, f"{f.filename} is bigger than {MAX_UPLOAD_MB} MB")
        pid = uuid.uuid4().hex[:12]
        tmp = PHOTOS / f"{pid}.upload"
        tmp.write_bytes(raw)
        try:
            with Image.open(tmp) as im:
                im = ImageOps.exif_transpose(im).convert("RGB")
                im.thumbnail((MAX_PHOTO_PX, MAX_PHOTO_PX))
                im.save(PHOTOS / f"{pid}.jpg", "JPEG", quality=85, optimize=True)
            saved.append(pid)
        except Exception:
            raise HTTPException(400, f"{f.filename} is not a picture I can read")
        finally:
            tmp.unlink(missing_ok=True)
    return {"saved": saved}


@app.get("/photos/{photo_id}.jpg")
def get_photo(photo_id: str, _: None = Depends(auth)):
    if not photo_id.isalnum():
        raise HTTPException(404)
    p = PHOTOS / f"{photo_id}.jpg"
    if not p.exists():
        raise HTTPException(404)
    return FileResponse(p, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=86400"})


@app.delete("/api/photos/{photo_id}")
def delete_photo(photo_id: str, _: None = Depends(auth)):
    if photo_id.isalnum():
        (PHOTOS / f"{photo_id}.jpg").unlink(missing_ok=True)
    return {"ok": True}


app.mount("/", StaticFiles(directory=Path(__file__).parent / "static", html=True), name="static")
