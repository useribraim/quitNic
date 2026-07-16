"""add nicotine-use outcome to check-ins

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-16
"""

from alembic import op
import sqlalchemy as sa


revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("check_ins", sa.Column("used_nicotine", sa.Boolean(), nullable=True))


def downgrade() -> None:
    op.drop_column("check_ins", "used_nicotine")
