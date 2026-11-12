#!/usr/bin/env python3
"""Copies Foyer's font and shaders into the Flutter project and lists them in pubspec.yaml (once each).
  - fonts/    Plus Jakarta Sans, the font used everywhere
  - shaders/  fire.frag, the fireplace
Usage: python3 tools/patch_fonts.py <project-path>    (update.sh and release.sh run it for you)"""
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
proj = Path(sys.argv[1] if len(sys.argv) > 1 else Path.home() / "Downloads" / "leclair_home")

for folder, keep in (("fonts", (".ttf", ".txt")), ("shaders", (".frag",))):
    dst = proj / folder
    dst.mkdir(exist_ok=True)
    for f in (HERE / folder).iterdir():
        if f.suffix in keep:
            shutil.copy2(f, dst / f.name)

pub = proj / "pubspec.yaml"
text = pub.read_text()
added = []

weights = [(200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
           (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold")]
blocks = ""
if "family: PlusJakartaSans" not in text:
    blocks += "  fonts:\n    - family: PlusJakartaSans\n      fonts:\n" + "".join(
        f"        - asset: fonts/PlusJakartaSans-{n}.ttf\n          weight: {w}\n" for w, n in weights)
    added.append("Plus Jakarta Sans")
if "shaders/fire.frag" not in text:
    blocks += "  shaders:\n    - shaders/fire.frag\n"
    added.append("the fireplace shader")

if blocks:
    lines = text.splitlines(keepends=True)
    out, done = [], False
    for line in lines:
        out.append(line)
        # the top-level "flutter:" section (not "flutter:" under dependencies, which is indented)
        if not done and re.match(r"^flutter:\s*(#.*)?$", line):
            out.append(blocks)
            done = True
    if not done:
        out.append("\nflutter:\n" + blocks)
    pub.write_text("".join(out))
    print("Added to pubspec.yaml: " + " and ".join(added))
