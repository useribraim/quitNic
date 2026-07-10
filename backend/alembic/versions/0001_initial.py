"""initial schema"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table("device_accounts", sa.Column("id", sa.String(36), primary_key=True), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False), sa.Column("deleted_at", sa.DateTime(timezone=True)))
    op.create_table("tokens", sa.Column("id", sa.String(36), primary_key=True), sa.Column("device_id", sa.String(36), sa.ForeignKey("device_accounts.id", ondelete="CASCADE"), unique=True, nullable=False), sa.Column("token_hash", sa.String(64), unique=True, nullable=False), sa.Column("revoked_at", sa.DateTime(timezone=True)), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_tokens_token_hash", "tokens", ["token_hash"], unique=True)
    op.create_table("quit_plans", sa.Column("id", sa.String(36), primary_key=True), sa.Column("device_id", sa.String(36), sa.ForeignKey("device_accounts.id", ondelete="CASCADE"), unique=True, nullable=False), sa.Column("nicotine_type", sa.String(32), nullable=False), sa.Column("daily_consumption", sa.Float, nullable=False), sa.Column("unit_cost", sa.Float, nullable=False), sa.Column("quit_date", sa.DateTime(timezone=True), nullable=False), sa.Column("motivation", sa.Text, nullable=False), sa.Column("reminder_hour", sa.Integer), sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False))
    op.create_table("check_ins", sa.Column("id", sa.String(36), primary_key=True), sa.Column("device_id", sa.String(36), sa.ForeignKey("device_accounts.id", ondelete="CASCADE"), nullable=False), sa.Column("intensity", sa.Integer, nullable=False), sa.Column("trigger", sa.String(80), nullable=False), sa.Column("coping_action", sa.String(120), nullable=False), sa.Column("note", sa.Text), sa.Column("resisted", sa.Boolean, nullable=False), sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False), sa.Column("idempotency_key", sa.String(80), nullable=False), sa.UniqueConstraint("device_id", "idempotency_key"))
    op.create_index("ix_check_ins_device_id", "check_ins", ["device_id"])
    op.create_table("coaching_messages", sa.Column("id", sa.String(36), primary_key=True), sa.Column("device_id", sa.String(36), sa.ForeignKey("device_accounts.id", ondelete="CASCADE"), nullable=False), sa.Column("role", sa.String(16), nullable=False), sa.Column("content", sa.Text, nullable=False), sa.Column("created_at", sa.DateTime(timezone=True), nullable=False))
    op.create_index("ix_coaching_messages_device_id", "coaching_messages", ["device_id"])


def downgrade() -> None:
    op.drop_table("coaching_messages")
    op.drop_table("check_ins")
    op.drop_table("quit_plans")
    op.drop_table("tokens")
    op.drop_table("device_accounts")

