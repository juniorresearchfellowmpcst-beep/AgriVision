"""survey_runs — one flight, from camera selection to a sprayed field

Adds the table behind /api/survey. A run records what the aircraft was told to
look at (which cameras, which crop, disease or weeds), what it found, and --
separately, and only when a human said so -- that the tank was filled and
spraying was authorised.

The tank and the authorisation are deliberately several columns rather than
one boolean. "The farmer filled the tank" and "the farmer agreed to spray" are
two different statements, and a run that opened a valve has to be able to show
both, with who and when.

Production has AUTO_CREATE_TABLES off, so this migration is the only way the
table reaches a deployed database. The root Procfile's `release` line runs
`flask db upgrade` before the new version takes traffic.

Revision ID: 24cc47c367df
Revises: c9428fb30df7
Create Date: 2026-08-31 11:26:18.449469

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '24cc47c367df'
down_revision = 'c9428fb30df7'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('survey_runs',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', sa.Integer(), nullable=True),
    sa.Column('session_id', sa.String(length=60), nullable=False),
    sa.Column('field_name', sa.String(length=120), nullable=True),
    sa.Column('camera_mode', sa.String(length=20), nullable=False),
    sa.Column('detection_target', sa.String(length=20), nullable=False),
    sa.Column('crop', sa.String(length=40), nullable=True),
    sa.Column('rgb_camera_id', sa.Integer(), nullable=True),
    sa.Column('status', sa.String(length=20), nullable=False),
    sa.Column('frames_scanned', sa.Integer(), nullable=True),
    sa.Column('diseased_frames', sa.Integer(), nullable=True),
    sa.Column('weed_percent', sa.Integer(), nullable=True),
    sa.Column('health_score', sa.Integer(), nullable=True),
    sa.Column('dominant_condition', sa.String(length=120), nullable=True),
    sa.Column('prescription_id', sa.Integer(), nullable=True),
    sa.Column('tank_filled', sa.Boolean(), nullable=True),
    sa.Column('tank_litres', sa.Float(), nullable=True),
    sa.Column('tank_product', sa.String(length=200), nullable=True),
    sa.Column('spray_authorised', sa.Boolean(), nullable=True),
    sa.Column('authorised_by', sa.String(length=120), nullable=True),
    sa.Column('authorised_at', sa.DateTime(), nullable=True),
    sa.Column('chosen_option', sa.String(length=30), nullable=True),
    sa.Column('summary', sa.Text(), nullable=True),
    sa.Column('started_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=True),
    sa.Column('finished_at', sa.DateTime(), nullable=True),
    sa.Column('created_at', sa.DateTime(), server_default=sa.text('(CURRENT_TIMESTAMP)'), nullable=True),
    sa.ForeignKeyConstraint(['prescription_id'], ['spray_prescriptions.id'], ),
    sa.ForeignKeyConstraint(['rgb_camera_id'], ['camera_feeds.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('survey_runs', schema=None) as batch_op:
        # Not unique: a run's session id is also stamped on every frame it
        # captures, and the lookup that matters is "this run's captures".
        batch_op.create_index(
            batch_op.f('ix_survey_runs_session_id'), ['session_id'], unique=False
        )


def downgrade():
    with op.batch_alter_table('survey_runs', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_survey_runs_session_id'))

    op.drop_table('survey_runs')
