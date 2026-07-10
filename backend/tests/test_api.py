from datetime import UTC, datetime, timedelta

import pytest

from app.main import app
from app.services.coaching import CoachingProvider, get_coaching_provider


class FakeCoach(CoachingProvider):
    async def respond(self, message, context):
        return "Take one slow breath, drink some water, and revisit your reason for quitting."


@pytest.mark.asyncio
async def test_health_and_auth_boundary(client):
    assert (await client.get("/health")).json() == {"status": "ok"}
    response = await client.get("/v1/quit-plan")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "http_401"


@pytest.mark.asyncio
async def test_quit_plan_progress_and_check_in_idempotency(authenticated):
    quit_date = datetime.now(UTC) - timedelta(days=2)
    plan = {
        "nicotine_type": "cigarettes",
        "daily_consumption": 10,
        "unit_cost": 0.75,
        "quit_date": quit_date.isoformat(),
        "motivation": "More energy",
        "reminder_hour": 20,
    }
    assert (await authenticated.put("/v1/quit-plan", json=plan)).status_code == 200
    progress = (await authenticated.get("/v1/progress")).json()
    assert progress["nicotine_free_seconds"] >= 172799
    assert progress["money_saved"] >= 15
    payload = {
        "intensity": 7,
        "trigger": "After dinner",
        "coping_action": "Walk",
        "note": "It passed",
        "resisted": True,
        "occurred_at": datetime.now(UTC).isoformat(),
    }
    first = await authenticated.post(
        "/v1/check-ins", json=payload, headers={"Idempotency-Key": "same-event-123"}
    )
    second = await authenticated.post(
        "/v1/check-ins", json=payload, headers={"Idempotency-Key": "same-event-123"}
    )
    assert first.json()["id"] == second.json()["id"]
    assert len((await authenticated.get("/v1/check-ins")).json()["items"]) == 1


@pytest.mark.asyncio
async def test_timestamps_are_rfc3339_utc_for_ios_date_decoding(authenticated):
    quit_date = datetime.now(UTC).replace(microsecond=123456)
    plan = {
        "nicotine_type": "vape",
        "daily_consumption": 5,
        "unit_cost": 0.5,
        "quit_date": quit_date.isoformat(),
        "motivation": "Sleep better",
        "reminder_hour": None,
    }
    plan_body = (await authenticated.put("/v1/quit-plan", json=plan)).json()
    check_in = await authenticated.post(
        "/v1/check-ins",
        json={
            "intensity": 4,
            "trigger": "Coffee",
            "coping_action": "Water",
            "note": None,
            "resisted": True,
            "occurred_at": datetime.now(UTC).replace(microsecond=987654).isoformat(),
        },
        headers={"Idempotency-Key": "utc-format-check"},
    )
    for value in (plan_body["quit_date"], plan_body["updated_at"], check_in.json()["occurred_at"]):
        # Swift's .iso8601 decoding requires a zone designator and rejects
        # fractional seconds; naive timestamps stall the client's outbox.
        assert value.endswith("Z"), value
        assert "." not in value, value


@pytest.mark.asyncio
async def test_coaching_and_fixed_safety_response(authenticated):
    app.dependency_overrides[get_coaching_provider] = FakeCoach
    try:
        normal = await authenticated.post(
            "/v1/coaching/messages", json={"message": "A craving hit", "recent_context": []}
        )
        assert normal.status_code == 200
        assert normal.json()["is_safety_response"] is False
        crisis = await authenticated.post(
            "/v1/coaching/messages", json={"message": "I might kill myself", "recent_context": []}
        )
        assert crisis.json()["is_safety_response"] is True
        assert "emergency services" in crisis.json()["message"]
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_delete_revokes_access(authenticated):
    assert (await authenticated.delete("/v1/account")).json() == {"deleted": True}
    assert (await authenticated.get("/v1/check-ins")).status_code == 401
