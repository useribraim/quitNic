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
        for key, value in payload.model_dump().items():
            setattr(existing, key, value)
        await db.commit()
        await db.refresh(existing)
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
    # The page is ordered by occurred_at, so the cursor must be an occurred_at boundary.
    # This used to compare `CheckIn.id < cursor` — ids are random UUIDs with no relation
    # to occurred_at, so paging past the first page would skip and duplicate items in
    # whatever order the UUIDs happened to sort in.
    query = select(CheckIn).where(CheckIn.device_id == device.id)
    if cursor:
        try:
            cursor_time = datetime.fromisoformat(cursor.replace("Z", "+00:00"))
        except ValueError as exc:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid cursor") from exc
        if cursor_time.tzinfo is not None:
            cursor_time = cursor_time.astimezone(UTC).replace(tzinfo=None)
        query = query.where(CheckIn.occurred_at < cursor_time)
    items = list(
        (await db.execute(query.order_by(CheckIn.occurred_at.desc()).limit(limit + 1))).scalars()
    )
    next_cursor = items[limit - 1].occurred_at.isoformat() + "Z" if len(items) > limit else None
    return CheckInPage(
        items=[CheckInOutput.model_validate(item) for item in items[:limit]],
        next_cursor=next_cursor,
    )


@router.delete("/check-ins/{idempotency_key}", response_model=DeleteResponse)
async def delete_check_in(
    idempotency_key: str,
    device: DeviceAccount = Depends(current_device),
    db: AsyncSession = Depends(get_db),
) -> DeleteResponse:
    """Delete one device-owned check-in; repeating the request is safe."""
    check_in = (
        await db.execute(
            select(CheckIn).where(
                CheckIn.device_id == device.id,
                CheckIn.idempotency_key == idempotency_key,
            )
        )
    ).scalar_one_or_none()
    if check_in is not None:
        await db.delete(check_in)
        await db.commit()
    return DeleteResponse(deleted=True)


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
                await provider.respond(payload.message, provider_context[-9:], payload.style),
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
    last_use = (
        await db.execute(
            select(CheckIn.occurred_at)
            .where(CheckIn.device_id == device.id, CheckIn.used_nicotine.is_(True))
            .order_by(CheckIn.occurred_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if last_use is not None and last_use.tzinfo is None:
        last_use = last_use.replace(tzinfo=UTC)
    # A slip resets the nicotine-free streak, but it must not erase money and units
    # already saved before it — that history is real and happened regardless. Keep the
    # streak/milestone clock on `start_date` (resets on a slip) while money and avoided
    # units are computed from the full `quit_date` (never resets). Mirrors ProgressCalculator
    # on the iOS client; the two must agree or the server overwrites the client's number
    # with a smaller, wrong one the moment a sync succeeds.
    start_date = max(quit_date, last_use if last_use is not None else quit_date)
    seconds = max(0, int((now - start_date).total_seconds()))
    lifetime_days = max(0.0, (now - quit_date).total_seconds() / 86400)
    milestone_hours = [
        ("6 Hours", 6),
        ("1 Day", 24),
        ("3 Days", 72),
        ("1 Week", 168),
        ("2 Weeks", 336),
        ("1 Month", 672),
        ("6 Weeks", 1_008),
        ("3 Months", 2_160),
        ("6 Months", 4_380),
        ("1 Year", 8_760),
        ("2 Years", 17_520),
        ("5 Years", 43_800),
    ]
    next_item = next(
        ((title, hours) for title, hours in milestone_hours if seconds < hours * 3600), None
    )
    next_milestone = (
        Milestone(title=next_item[0], target_hours=next_item[1], achieved=False)
        if next_item
        else None
    )
    return ProgressResponse(
        nicotine_free_seconds=seconds,
        money_saved=round(lifetime_days * plan.daily_consumption * plan.unit_cost, 2),
        avoided_units=round(lifetime_days * plan.daily_consumption, 1),
        current_streak_days=max(0, ceil(seconds / 86400)),
        next_milestone=next_milestone,
    )


@router.delete("/coaching/messages", response_model=DeleteResponse)
async def delete_coaching_messages(
    device: DeviceAccount = Depends(current_device), db: AsyncSession = Depends(get_db)
) -> DeleteResponse:
    await db.execute(delete(CoachingMessage).where(CoachingMessage.device_id == device.id))
    await db.commit()
    return DeleteResponse(deleted=True)


@router.delete("/account", response_model=DeleteResponse)
async def delete_account(
    device: DeviceAccount = Depends(current_device), db: AsyncSession = Depends(get_db)
) -> DeleteResponse:
    await db.execute(delete(DeviceAccount).where(DeviceAccount.id == device.id))
    await db.commit()
    return DeleteResponse(deleted=True)
