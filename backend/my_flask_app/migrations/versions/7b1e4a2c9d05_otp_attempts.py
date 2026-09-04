"""password_reset_otps.attempts — a guess budget per reset code

The route that verifies a code is rate-limited per caller address, which stops
one machine hammering it and does nothing about several machines taking a share
each. A six-digit code is a million possibilities, so the budget has to belong
to the code rather than to whoever is asking: five wrong guesses and the code is
burned, which is generous for a mistyped digit and useless for searching.

Backfills existing rows to 0 rather than NULL — an outstanding code issued
before this migration should start with its full budget, not with an unknown
one that `>=` would then compare against None.

Production has AUTO_CREATE_TABLES off, so this migration is the only way the
column reaches a deployed database. The root Procfile's `release` line runs
`flask db upgrade` before the new version takes traffic.

Revision ID: 7b1e4a2c9d05
Revises: 24cc47c367df
Create Date: 2026-09-04 09:20:00.000000
"""

import sqlalchemy as sa
from alembic import op

revision = "7b1e4a2c9d05"
down_revision = "24cc47c367df"
branch_labels = None
depends_on = None


def upgrade():
    # server_default so rows inserted by an older app process during the
    # rollover still land at 0 rather than failing the NOT NULL.
    with op.batch_alter_table("password_reset_otps") as batch:
        batch.add_column(
            sa.Column(
                "attempts",
                sa.Integer(),
                nullable=False,
                server_default="0",
            )
        )


def downgrade():
    with op.batch_alter_table("password_reset_otps") as batch:
        batch.drop_column("attempts")
