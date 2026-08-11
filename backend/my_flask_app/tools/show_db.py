#!/usr/bin/env python
"""Look inside the database the backend is actually using.

    python tools/show_db.py                # every table + row count
    python tools/show_db.py users          # the user accounts
    python tools/show_db.py users --full   # ...including profile rows

Goes through the app's own config, so it points at whatever the backend
points at: the local SQLite file by default, or the Postgres in DATABASE_URL
when one is set. That distinction matters — the accounts you see in the phone
app live in the *server's* database, not in the local file, unless the app's
BASE_URL is your machine.

Password hashes are never printed.
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import create_app  # noqa: E402
from app.core.database import db  # noqa: E402


def _describe_target(app) -> str:
    uri = app.config["SQLALCHEMY_DATABASE_URI"]
    if uri.startswith("sqlite:///"):
        path = uri.replace("sqlite:///", "", 1)
        if not os.path.isabs(path):
            path = os.path.join(app.instance_path, path)
        exists = "exists" if os.path.isfile(path) else "MISSING"
        size = f"{os.path.getsize(path) / 1024:.0f} KB" if os.path.isfile(path) else ""
        return f"SQLite  {path}  ({exists} {size})".strip()
    # Never echo a Postgres password back at the terminal.
    scheme, _, rest = uri.partition("://")
    host = rest.split("@")[-1] if "@" in rest else rest
    return f"{scheme}  …@{host}"


def show_tables(app) -> None:
    inspector = db.inspect(db.engine)
    names = sorted(inspector.get_table_names())
    if not names:
        print("\nNo tables. Start the backend once (python run.py) to create them.")
        return

    print(f"\n{len(names)} table(s):")
    for name in names:
        count = db.session.execute(
            db.text(f'SELECT COUNT(*) FROM "{name}"')
        ).scalar()
        print(f"  {name:<24} {count:>6} row(s)")


def show_users(app, full: bool) -> None:
    from app.api.models.user import User, UserProfile

    users = User.query.order_by(User.id).all()
    if not users:
        print("\nNo user accounts in this database.")
        return

    print(f"\n{len(users)} user account(s):")
    for user in users:
        created = getattr(user, "created_at", None)
        print(
            f"  #{user.id:<4} {str(user.username):<22} {str(user.email):<32} "
            f"{created or ''}"
        )

    if not full:
        return

    profiles = UserProfile.query.all()
    print(f"\n{len(profiles)} pilot profile(s):")
    for profile in profiles:
        print(f"  user_id={profile.user_id} {profile.to_dict()}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("what", nargs="?", default="tables",
                        choices=("tables", "users"))
    parser.add_argument("--full", action="store_true",
                        help="with 'users', also print the pilot profile rows")
    args = parser.parse_args()

    app = create_app()
    print("Database:", _describe_target(app))

    with app.app_context():
        if args.what == "users":
            show_users(app, args.full)
        else:
            show_tables(app)


if __name__ == "__main__":
    main()
