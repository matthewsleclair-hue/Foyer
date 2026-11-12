#!/usr/bin/env python3
"""Release notes from CHANGELOG.md: everything after one version, up to and including another.
  python3 tools/release_notes.py 1.23.0            just 1.23.0
  python3 tools/release_notes.py 1.23.0 1.22.1     everything new since 1.22.1 (1.22.2, 1.22.3, 1.23.0)
Prints Markdown for a GitHub release (or the TV's Updates screen)."""
import re
import sys
from pathlib import Path

LOG = Path(__file__).resolve().parent.parent / "CHANGELOG.md"


def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s.split("+")[0])[:3])


def sections():
    out, cur, lines = [], None, []
    for line in LOG.read_text().splitlines():
        m = re.match(r"^## (\d+\.\d+\.\d+)\s*$", line)
        if m:
            if cur:
                out.append((cur, "\n".join(lines).strip()))
            cur, lines = m.group(1), []
        elif cur:
            lines.append(line)
    if cur:
        out.append((cur, "\n".join(lines).strip()))
    return out


def notes(upto, after=None):
    hi, lo = ver(upto), (ver(after) if after else None)
    picked = [(v, body) for v, body in sections()
              if ver(v) <= hi and (ver(v) > lo if lo else ver(v) == hi)]
    if not picked:
        return f"Foyer {upto}"
    if len(picked) == 1:
        return picked[0][1]
    # several versions in one release: newest first, each under its own heading
    return "\n\n".join(f"### {v}\n{body}" for v, body in picked)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    print(notes(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
