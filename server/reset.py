"""Locked out of the owner account? Run this on the server to get a reset code:

    docker compose exec foyer-drop python reset.py <account name>

Then choose "Forgot password?" on the sign-in page and enter the code.
"""
import sys
from contextlib import closing

from app import db, make_reset

if len(sys.argv) != 2:
    sys.exit(__doc__)
with closing(db()) as c, c:
    u = c.execute("SELECT id,name FROM users WHERE name=?", (sys.argv[1].strip().lower(),)).fetchone()
    if not u:
        names = ", ".join(r["name"] for r in c.execute("SELECT name FROM users")) or "(none yet)"
        sys.exit(f"No account called {sys.argv[1]!r}. Accounts: {names}")
    print(f"Reset code for {u['name']} (works for 24 hours): {make_reset(c, u['id'])}")
