"""add currency code to quit plans

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-24
"""

from alembic import op
import sqlalchemy as sa


revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "quit_plans",
        sa.Column("currency_code", sa.String(length=3), nullable=False, server_default="USD"),
    )


def downgrade() -> None:
    op.drop_column("quit_plans", "currency_code")
