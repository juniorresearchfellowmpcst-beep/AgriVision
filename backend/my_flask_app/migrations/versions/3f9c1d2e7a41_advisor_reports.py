"""advisor_reports — in-app reporting of crop-advisor answers

Google Play's AI-generated content policy requires apps that generate content
with AI to let users report offensive or harmful output from inside the app.
The crop advisor's answers come from Gemini, so each one now has a Report
action; this is the table those reports are written to.

The answer text is kept on the report because the advisor stores no
conversation history -- without a copy here, a report would reference
something nobody could read back.

Production has AUTO_CREATE_TABLES off, so this migration is the only way the
table reaches a deployed database. The root Procfile's `release` line runs
`flask db upgrade` before the new version takes traffic.

Revision ID: 3f9c1d2e7a41
Revises: 7b1e4a2c9d05
Create Date: 2026-09-11 10:00:00.000000
"""

import sqlalchemy as sa
from alembic import op

revision = "3f9c1d2e7a41"
down_revision = "7b1e4a2c9d05"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "advisor_reports",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("reason", sa.String(length=20), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("question", sa.Text(), nullable=True),
        sa.Column("answer", sa.Text(), nullable=False),
        sa.Column("model", sa.String(length=80), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(), server_default=sa.func.now(), nullable=True
        ),
    )
    op.create_index("ix_advisor_reports_user_id", "advisor_reports", ["user_id"])


def downgrade():
    op.drop_index("ix_advisor_reports_user_id", table_name="advisor_reports")
    op.drop_table("advisor_reports")
