from datetime import UTC, datetime
from math import ceil

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
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
    DeleteResponse,
    DeviceRegistration,
    Milestone,
    ProgressResponse,
    QuitPlanInput,
    QuitPlanOutput,
)
from ..services.coaching import SAFETY_RESPONSE, CoachingProvider, get_coaching_provider, is_crisis

router = APIRouter(prefix="/v1")


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
        try:
            response_text, safety = (
                await provider.respond(payload.message, payload.recent_context),
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
