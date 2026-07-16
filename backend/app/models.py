from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .core.database import Base


def utcnow() -> datetime:
    return datetime.now(UTC)


class DeviceAccount(Base):
    __tablename__ = "device_accounts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    token: Mapped["Token"] = relationship(back_populates="device", cascade="all, delete-orphan")
    quit_plan: Mapped["QuitPlan | None"] = relationship(
        back_populates="device", cascade="all, delete-orphan"
    )


class Token(Base):
    __tablename__ = "tokens"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    device_id: Mapped[str] = mapped_column(
        ForeignKey("device_accounts.id", ondelete="CASCADE"), unique=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    device: Mapped[DeviceAccount] = relationship(back_populates="token")


class QuitPlan(Base):
    __tablename__ = "quit_plans"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    device_id: Mapped[str] = mapped_column(
        ForeignKey("device_accounts.id", ondelete="CASCADE"), unique=True
    )
    nicotine_type: Mapped[str] = mapped_column(String(32))
    daily_consumption: Mapped[float] = mapped_column(Float)
    unit_cost: Mapped[float] = mapped_column(Float)
    quit_date: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    motivation: Mapped[str] = mapped_column(Text, default="")
    reminder_hour: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )
    device: Mapped[DeviceAccount] = relationship(back_populates="quit_plan")


class CheckIn(Base):
    __tablename__ = "check_ins"
    __table_args__ = (UniqueConstraint("device_id", "idempotency_key"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    device_id: Mapped[str] = mapped_column(
        ForeignKey("device_accounts.id", ondelete="CASCADE"), index=True
    )
    intensity: Mapped[int] = mapped_column(Integer)
    trigger: Mapped[str] = mapped_column(String(80))
    coping_action: Mapped[str] = mapped_column(String(120))
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    resisted: Mapped[bool] = mapped_column(Boolean)
    used_nicotine: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    idempotency_key: Mapped[str] = mapped_column(String(80))


class CoachingMessage(Base):
    __tablename__ = "coaching_messages"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    device_id: Mapped[str] = mapped_column(
        ForeignKey("device_accounts.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16))
    content: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
