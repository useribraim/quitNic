from collections import Counter
from datetime import UTC, datetime
from math import ceil

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, UploadFile, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.database import get_db
from ..core.rate_limit import coaching_limiter
from ..core.security import current_device, new_token, token_hash
from ..models import CheckIn, CoachingMessage, DeviceAccount, QuitPlan, Token
from ..schemas import (
    CheckInInput,
    CheckInOutput,
    CheckInPage,
    CoachingRequest,
    CoachingResponse,
    ConversationTurn,
    DeleteResponse,
    DeviceRegistration,
    Milestone,
    ProgressResponse,
    QuitPlanInput,
    QuitPlanOutput,
    TranscriptionResponse,
)
from ..services.coaching import SAFETY_RESPONSE, CoachingProvider, get_coaching_provider, is_crisis
from ..services.transcription import OpenAITranscriptionProvider

router = APIRouter(prefix="/v1")
MAX_TRANSCRIPTION_BYTES = 8 * 1024 * 1024


def _coaching_profile(plan: QuitPlan | None, check_ins: list[CheckIn]) -> str | None:
    """Build a small, purpose-limited context block for the coaching provider."""
    if plan is None and not check_ins:
        return None
    lines = ["Private quit-coaching context; use only to personalize practical support."]
    if plan is not None:
        quit_date = plan.quit_date if plan.quit_date.tzinfo else plan.quit_date.replace(tzinfo=UTC)
        days = max(0, int((datetime.now(UTC) - quit_date).total_seconds() // 86_400))
        lines.append(
            f"Plan: {plan.nicotine_type}, about {plan.daily_consumption:g} units/day, "
            f"quit journey day {days + 1}."
        )
        if plan.motivation:
            lines.append(f"Motivation: {plan.motivation[:240]}")
    if check_ins:
        triggers = Counter(item.trigger for item in check_ins).most_common(3)
        actions = Counter(item.coping_action for item in check_ins).most_common(3)
        average = sum(item.intensity for item in check_ins) / len(check_ins)
        lines.append(
            f"Recent cravings: {len(check_ins)} recorded, average intensity {average:.1f}/10."
        )
        lines.append(
            "Common triggers: " + ", ".join(f"{name} ({count})" for name, count in triggers) + "."
        )
        lines.append(
            "Coping actions tried: "
            + ", ".join(f"{name} ({count})" for name, count in actions)
            + "."
        )
    return " ".join(lines)[:1800]


@router.post("/devices/register", response_model=DeviceRegistration, status_code=201)
async def register(db: AsyncSession = Depends(get_db)) -> DeviceRegistration:
    raw_token = new_token()
    device = DeviceAccount()
    db.add(device)
    await db.flush()
    db.add(Token(device_id=device.id, token_hash=token_hash(raw_token)))
    await db.commit()
    return DeviceRegistration(device_id=device.id, access_token=raw_token)


@router.get("/quit-plan", response_model=QuitPlanOutput)
async def get_quit_plan(
    device: DeviceAccount = Depends(current_device), db: AsyncSession = Depends(get_db)
) -> QuitPlan:
    plan = (
        await db.execute(select(QuitPlan).where(QuitPlan.device_id == device.id))
    ).scalar_one_or_none()
    if plan is None:
        raise HTTPException(404, "Quit plan not found")
    return plan


@router.put("/quit-plan", response_model=QuitPlanOutput)
async def put_quit_plan(
    payload: QuitPlanInput,
    device: DeviceAccount = Depends(current_device),
    db: AsyncSession = Depends(get_db),
) -> QuitPlan:
    plan = (
        await db.execute(select(QuitPlan).where(QuitPlan.device_id == device.id))
    ).scalar_one_or_none()
    values = payload.model_dump()
    if plan is None:
        plan = QuitPlan(device_id=device.id, **values)
        db.add(plan)
    else:
        for key, value in values.items():
            setattr(plan, key, value)
    await db.commit()
    await db.refresh(plan)
    return plan


@router.post("/check-ins", response_model=CheckInOutput, status_code=201)
async def create_check_in(
    payload: CheckInInput,
    device: DeviceAccount = Depends(current_device),
    db: AsyncSession = Depends(get_db),
    idempotency_key: str = Header(min_length=8, max_length=80),
) -> CheckIn:
    existing = (
        await db.execute(
            select(CheckIn).where(
                CheckIn.device_id == device.id, CheckIn.idempotency_key == idempotency_key
            )
        )
    ).scalar_one_or_none()
    if existing:
        return existing
    check_in = CheckIn(device_id=device.id, idempotency_key=idempotency_key, **payload.model_dump())
    db.add(check_in)
    await db.commit()
    await db.refresh(check_in)
    return check_in


@router.get("/check-ins", response_model=CheckInPage)
async def list_check_ins(
    device: DeviceAccount = Depends(current_device),
    db: AsyncSession = Depends(get_db),
    cursor: str | None = None,
    limit: int = Query(20, ge=1, le=100),
) -> CheckInPage:
    query = select(CheckIn).where(CheckIn.device_id == device.id)
    if cursor:
        query = query.where(CheckIn.id < cursor)
    items = list(
        (await db.execute(query.order_by(CheckIn.occurred_at.desc()).limit(limit + 1))).scalars()
    )
    next_cursor = items[limit - 1].id if len(items) > limit else None
    return CheckInPage(items=items[:limit], next_cursor=next_cursor)


@router.post("/coaching/messages", response_model=CoachingResponse)
async def coaching(
    payload: CoachingRequest,
    device: DeviceAccount = Depends(current_device),
    db: AsyncSession = Depends(get_db),
    provider: CoachingProvider = Depends(get_coaching_provider),
) -> CoachingResponse:
    await coaching_limiter.check(device.id)
    if is_crisis(payload.message):
        response_text, safety = SAFETY_RESPONSE, True
    else:
        plan = (
            await db.execute(select(QuitPlan).where(QuitPlan.device_id == device.id))
        ).scalar_one_or_none()
        recent_check_ins = list(
            (
                await db.execute(
                    select(CheckIn)
                    .where(CheckIn.device_id == device.id)
                    .order_by(CheckIn.occurred_at.desc())
                    .limit(8)
                )
            ).scalars()
        )
        profile = _coaching_profile(plan, recent_check_ins)
        provider_context = payload.recent_context[-8:]
        if profile:
            provider_context = [ConversationTurn(role="user", content=profile), *provider_context]
        try:
            response_text, safety = (
                await provider.respond(payload.message, provider_context[-9:]),
                False,
            )
        except Exception as exc:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE, "Coaching service temporarily unavailable"
            ) from exc
    db.add_all(
        [
            CoachingMessage(device_id=device.id, role="user", content=payload.message),
            CoachingMessage(device_id=device.id, role="assistant", content=response_text),
        ]
    )
    await db.commit()
    return CoachingResponse(message=response_text, is_safety_response=safety)


@router.post("/transcriptions", response_model=TranscriptionResponse)
async def transcribe(
    audio: UploadFile = File(...),
    device: DeviceAccount = Depends(current_device),
) -> TranscriptionResponse:
    """Transcribe one user-initiated Push-to-Talk clip; never retain its audio."""
    await coaching_limiter.check(device.id)
    if not (audio.content_type or "").startswith("audio/"):
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Audio file required")
    content = await audio.read(MAX_TRANSCRIPTION_BYTES + 1)
    if len(content) > MAX_TRANSCRIPTION_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Audio clip is too large")
    try:
        text = await OpenAITranscriptionProvider().transcribe(
            audio.filename or "push-to-talk.m4a", content, audio.content_type or "audio/m4a"
        )
    except ValueError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, "Transcription service temporarily unavailable"
        ) from exc
    return TranscriptionResponse(text=text)


@router.get("/progress", response_model=ProgressResponse)
async def progress(
    device: DeviceAccount = Depends(current_device), db: AsyncSession = Depends(get_db)
) -> ProgressResponse:
    plan = (
        await db.execute(select(QuitPlan).where(QuitPlan.device_id == device.id))
    ).scalar_one_or_none()
    if plan is None:
        raise HTTPException(404, "Quit plan not found")
    now = datetime.now(UTC)
    quit_date = plan.quit_date if plan.quit_date.tzinfo else plan.quit_date.replace(tzinfo=UTC)
    seconds = max(0, int((now - quit_date).total_seconds()))
    days = seconds / 86400
    milestones = [
        ("First day", 24),
        ("First week", 168),
        ("First month", 720),
        ("Three months", 2160),
    ]
    next_item = next(
        ((title, hours) for title, hours in milestones if seconds < hours * 3600), None
    )
    next_milestone = (
        Milestone(title=next_item[0], target_hours=next_item[1], achieved=False)
        if next_item
        else None
    )
    return ProgressResponse(
        nicotine_free_seconds=seconds,
        money_saved=round(days * plan.daily_consumption * plan.unit_cost, 2),
        avoided_units=round(days * plan.daily_consumption, 1),
        current_streak_days=max(0, ceil(days)),
        next_milestone=next_milestone,
    )


@router.delete("/account", response_model=DeleteResponse)
async def delete_account(
    device: DeviceAccount = Depends(current_device), db: AsyncSession = Depends(get_db)
) -> DeleteResponse:
    await db.execute(delete(DeviceAccount).where(DeviceAccount.id == device.id))
    await db.commit()
    return DeleteResponse(deleted=True)
