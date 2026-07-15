from datetime import UTC, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, PlainSerializer


def _serialize_utc(value: datetime) -> str:
    """Emit RFC 3339 UTC timestamps (trailing Z, whole seconds).

    Stored datetimes are naive UTC; without an explicit zone designator the
    iOS client's ISO 8601 date decoding rejects the value, and fractional
    seconds are equally unparseable there.
    """
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    value = value.astimezone(UTC).replace(microsecond=0)
    return value.isoformat().replace("+00:00", "Z")


UTCDateTime = Annotated[
    datetime, PlainSerializer(_serialize_utc, return_type=str, when_used="json")
]


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorEnvelope(BaseModel):
    error: ErrorDetail


class DeviceRegistration(BaseModel):
    device_id: str
    access_token: str
    token_type: Literal["bearer"] = "bearer"


class QuitPlanInput(BaseModel):
    nicotine_type: Literal["cigarettes", "vape", "pouches", "other"]
    daily_consumption: float = Field(gt=0, le=1000)
    unit_cost: float = Field(ge=0, le=1000)
    quit_date: UTCDateTime
    motivation: str = Field(default="", max_length=500)
    reminder_hour: int | None = Field(default=None, ge=0, le=23)


class QuitPlanOutput(QuitPlanInput):
    model_config = ConfigDict(from_attributes=True)
    id: str
    updated_at: UTCDateTime


class CheckInInput(BaseModel):
    intensity: int = Field(ge=1, le=10)
    trigger: str = Field(min_length=1, max_length=80)
    coping_action: str = Field(min_length=1, max_length=120)
    note: str | None = Field(default=None, max_length=1000)
    resisted: bool
    occurred_at: UTCDateTime


class CheckInOutput(CheckInInput):
    model_config = ConfigDict(from_attributes=True)
    id: str


class CheckInPage(BaseModel):
    items: list[CheckInOutput]
    next_cursor: str | None


class ConversationTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class CoachingRequest(BaseModel):
    message: str = Field(min_length=1, max_length=2000)
    recent_context: list[ConversationTurn] = Field(default_factory=list, max_length=10)


class CoachingResponse(BaseModel):
    message: str
    is_safety_response: bool = False


class TranscriptionResponse(BaseModel):
    text: str


class Milestone(BaseModel):
    title: str
    target_hours: int
    achieved: bool


class ProgressResponse(BaseModel):
    nicotine_free_seconds: int
    money_saved: float
    avoided_units: float
    current_streak_days: int
    next_milestone: Milestone | None


class DeleteResponse(BaseModel):
    deleted: bool
