from datetime import UTC, datetime, timedelta

import pytest

from app.main import app
from app.services.coaching import CoachingProvider, get_coaching_provider


class FakeCoach(CoachingProvider):
    last_context = []

    async def respond(self, message, context, style="chat"):
        FakeCoach.last_context = context
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
async def test_check_in_can_be_corrected_and_deleted_by_its_idempotency_key(authenticated):
    key = "correctable-event-123"
    occurred_at = datetime.now(UTC).isoformat()
    original = {
        "intensity": 4,
        "trigger": "Coffee",
        "coping_action": "Water",
        "note": None,
        "resisted": True,
        "occurred_at": occurred_at,
    }
    corrected = {
        **original,
        "intensity": 8,
        "trigger": "Work stress",
        "coping_action": "Short walk",
        "resisted": False,
        "used_nicotine": True,
    }

    created = await authenticated.post(
        "/v1/check-ins", json=original, headers={"Idempotency-Key": key}
    )
    updated = await authenticated.post(
        "/v1/check-ins", json=corrected, headers={"Idempotency-Key": key}
    )

    assert created.status_code == 201
    assert updated.status_code == 201
    assert updated.json()["id"] == created.json()["id"]
    assert updated.json()["trigger"] == "Work stress"
    assert updated.json()["used_nicotine"] is True
    items = (await authenticated.get("/v1/check-ins")).json()["items"]
    assert len(items) == 1
    assert items[0]["intensity"] == 8

    assert (await authenticated.delete(f"/v1/check-ins/{key}")).json() == {"deleted": True}
    assert (await authenticated.get("/v1/check-ins")).json()["items"] == []
    assert (await authenticated.delete(f"/v1/check-ins/{key}")).json() == {"deleted": True}


@pytest.mark.asyncio
async def test_nicotine_use_resets_server_progress(authenticated):
    quit_date = datetime.now(UTC) - timedelta(days=4)
    await authenticated.put(
        "/v1/quit-plan",
        json={
            "nicotine_type": "cigarettes",
            "daily_consumption": 10,
            "unit_cost": 0.75,
            "quit_date": quit_date.isoformat(),
            "motivation": "More energy",
            "reminder_hour": None,
        },
    )
    lapse_at = datetime.now(UTC) - timedelta(hours=2)
    response = await authenticated.post(
        "/v1/check-ins",
        json={
            "intensity": 8,
            "trigger": "Stress",
            "coping_action": "Pause",
            "note": None,
            "resisted": False,
            "used_nicotine": True,
            "occurred_at": lapse_at.isoformat(),
        },
        headers={"Idempotency-Key": "lapse-progress-123"},
    )
    assert response.status_code == 201
    assert response.json()["used_nicotine"] is True
    progress = (await authenticated.get("/v1/progress")).json()
    assert 7_000 <= progress["nicotine_free_seconds"] <= 7_400


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
async def test_coaching_receives_bounded_quit_context(authenticated):
    app.dependency_overrides[get_coaching_provider] = FakeCoach
    try:
        await authenticated.put(
            "/v1/quit-plan",
            json={
                "nicotine_type": "cigarettes",
                "daily_consumption": 10,
                "unit_cost": 0.75,
                "quit_date": (datetime.now(UTC) - timedelta(days=2)).isoformat(),
                "motivation": "Be more present with my family",
                "reminder_hour": 20,
            },
        )
        await authenticated.post(
            "/v1/check-ins",
            json={
                "intensity": 7,
                "trigger": "After dinner",
                "coping_action": "Walk",
                "note": None,
                "resisted": True,
                "occurred_at": datetime.now(UTC).isoformat(),
            },
            headers={"Idempotency-Key": "coach-context-123"},
        )
        response = await authenticated.post(
            "/v1/coaching/messages", json={"message": "I have a craving", "recent_context": []}
        )
        assert response.status_code == 200
        joined = " ".join(turn.content for turn in FakeCoach.last_context)
        assert "quit journey day" in joined
        assert "After dinner" in joined
        assert "Walk" in joined
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_money_saved_and_avoided_units_survive_a_slip(authenticated):
    # Regression test: money_saved/avoided_units must be computed from the full quit_date
    # (lifetime), not the streak-reset start_date — a slip resets the nicotine-free timer
    # but must never erase money and units already genuinely saved before it.
    quit_date = datetime.now(UTC) - timedelta(days=10)
    await authenticated.put(
        "/v1/quit-plan",
        json={
            "nicotine_type": "cigarettes",
            "daily_consumption": 10,
            "unit_cost": 1.0,
            "quit_date": quit_date.isoformat(),
            "motivation": "Health",
            "reminder_hour": None,
        },
    )
    before = (await authenticated.get("/v1/progress")).json()
    assert before["money_saved"] >= 99  # ~10 days * 10/day * $1

    lapse_at = datetime.now(UTC) - timedelta(hours=1)
    await authenticated.post(
        "/v1/check-ins",
        json={
            "intensity": 8,
            "trigger": "Stress",
            "coping_action": "Pause",
            "note": None,
            "resisted": False,
            "used_nicotine": True,
            "occurred_at": lapse_at.isoformat(),
        },
        headers={"Idempotency-Key": "slip-money-saved-123"},
    )
    after = (await authenticated.get("/v1/progress")).json()
    # The streak resets...
    assert after["nicotine_free_seconds"] < 3_700
    # ...but the lifetime savings do not shrink because of it.
    assert after["money_saved"] >= before["money_saved"] - 0.5


@pytest.mark.asyncio
async def test_quit_plan_round_trips_currency_code(authenticated):
    quit_date = datetime.now(UTC)
    response = await authenticated.put(
        "/v1/quit-plan",
        json={
            "nicotine_type": "pouches",
            "daily_consumption": 12,
            "unit_cost": 0.4,
            "quit_date": quit_date.isoformat(),
            "motivation": "Health",
            "reminder_hour": None,
            "currency_code": "GBP",
        },
    )
    assert response.status_code == 200
    assert response.json()["currency_code"] == "GBP"
    fetched = await authenticated.get("/v1/quit-plan")
    assert fetched.json()["currency_code"] == "GBP"


@pytest.mark.asyncio
async def test_quit_plan_currency_code_defaults_to_usd_when_omitted(authenticated):
    response = await authenticated.put(
        "/v1/quit-plan",
        json={
            "nicotine_type": "vape",
            "daily_consumption": 5,
            "unit_cost": 0.5,
            "quit_date": datetime.now(UTC).isoformat(),
            "motivation": "Health",
            "reminder_hour": None,
        },
    )
    assert response.json()["currency_code"] == "USD"


@pytest.mark.asyncio
async def test_progress_milestone_titles_match_the_expanded_set(authenticated):
    quit_date = datetime.now(UTC) - timedelta(hours=1)
    await authenticated.put(
        "/v1/quit-plan",
        json={
            "nicotine_type": "cigarettes",
            "daily_consumption": 10,
            "unit_cost": 0.75,
            "quit_date": quit_date.isoformat(),
            "motivation": "Health",
            "reminder_hour": None,
        },
    )
    progress = (await authenticated.get("/v1/progress")).json()
    assert progress["next_milestone"]["title"] == "6 Hours"
    assert progress["next_milestone"]["target_hours"] == 6


@pytest.mark.asyncio
async def test_progress_returns_404_without_a_quit_plan(authenticated):
    response = await authenticated.get("/v1/progress")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_quit_plan_returns_404_before_one_is_created(authenticated):
    response = await authenticated.get("/v1/quit-plan")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_delete_revokes_access(authenticated):
    assert (await authenticated.delete("/v1/account")).json() == {"deleted": True}
    assert (await authenticated.get("/v1/check-ins")).status_code == 401


@pytest.mark.asyncio
async def test_idempotency_key_is_scoped_per_device(client):
    payload = {
        "intensity": 5,
        "trigger": "Coffee",
        "coping_action": "Water",
        "note": None,
        "resisted": True,
        "occurred_at": datetime.now(UTC).isoformat(),
    }
    first_device = client
    first_registration = await first_device.post("/v1/devices/register")
    first_token = first_registration.json()["access_token"]
    first_device_headers = {"Authorization": f"Bearer {first_token}"}
    await first_device.post(
        "/v1/check-ins",
        json=payload,
        headers={**first_device_headers, "Idempotency-Key": "shared-key"},
    )

    second_registration = await first_device.post("/v1/devices/register")
    second_token = second_registration.json()["access_token"]
    second_device_headers = {"Authorization": f"Bearer {second_token}"}
    response = await first_device.post(
        "/v1/check-ins",
        json=payload,
        headers={**second_device_headers, "Idempotency-Key": "shared-key"},
    )
    assert response.status_code == 201
    # Each device's own history must contain exactly its own check-in, not the other's.
    first_items = (
        await first_device.get("/v1/check-ins", headers=first_device_headers)
    ).json()["items"]
    second_items = (
        await first_device.get("/v1/check-ins", headers=second_device_headers)
    ).json()["items"]
    assert len(first_items) == 1
    assert len(second_items) == 1
    assert first_items[0]["id"] != second_items[0]["id"]


@pytest.mark.asyncio
async def test_check_in_pagination_walks_every_item_exactly_once(authenticated):
    for index in range(5):
        await authenticated.post(
            "/v1/check-ins",
            json={
                "intensity": 5,
                "trigger": f"Trigger {index}",
                "coping_action": "Walk",
                "note": None,
                "resisted": True,
                "occurred_at": (datetime.now(UTC) - timedelta(minutes=index)).isoformat(),
            },
            headers={"Idempotency-Key": f"page-item-{index}"},
        )
    seen_ids: set[str] = set()
    cursor = None
    for _ in range(10):  # generous upper bound so a pagination bug fails instead of hanging
        params = {"limit": 2}
        if cursor:
            params["cursor"] = cursor
        page = (await authenticated.get("/v1/check-ins", params=params)).json()
        seen_ids.update(item["id"] for item in page["items"])
        cursor = page["next_cursor"]
        if cursor is None:
            break
    assert len(seen_ids) == 5


@pytest.mark.asyncio
async def test_coaching_requests_beyond_the_limit_are_rejected(authenticated):
    app.dependency_overrides[get_coaching_provider] = FakeCoach
    try:
        responses = [
            await authenticated.post(
                "/v1/coaching/messages", json={"message": f"message {i}", "recent_context": []}
            )
            for i in range(11)
        ]
        assert responses[-1].status_code == 429
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_delete_coaching_history_keeps_account(authenticated):
    app.dependency_overrides[get_coaching_provider] = FakeCoach
    try:
        assert (
            await authenticated.post(
                "/v1/coaching/messages", json={"message": "A craving hit", "recent_context": []}
            )
        ).status_code == 200
        assert (await authenticated.delete("/v1/coaching/messages")).json() == {"deleted": True}
        assert (await authenticated.get("/v1/check-ins")).status_code == 200
    finally:
        app.dependency_overrides.clear()
