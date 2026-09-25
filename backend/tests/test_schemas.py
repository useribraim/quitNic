from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from app.schemas import CheckInInput, ConversationTurn, QuitPlanInput


def _valid_plan(**overrides):
    values = {
        "nicotine_type": "cigarettes",
        "daily_consumption": 10,
        "unit_cost": 0.75,
        "quit_date": datetime.now(UTC),
        "motivation": "Health",
        "reminder_hour": 20,
    }
    values.update(overrides)
    return values


def test_quit_plan_defaults_currency_to_usd_when_omitted():
    plan = QuitPlanInput(**_valid_plan())
    assert plan.currency_code == "USD"


def test_quit_plan_accepts_an_explicit_currency_code():
    plan = QuitPlanInput(**_valid_plan(currency_code="EUR"))
    assert plan.currency_code == "EUR"


@pytest.mark.parametrize("currency_code", ["E", "EURO", ""])
def test_quit_plan_rejects_a_currency_code_that_is_not_three_letters(currency_code):
    with pytest.raises(ValidationError):
        QuitPlanInput(**_valid_plan(currency_code=currency_code))


@pytest.mark.parametrize("nicotine_type", ["cigarettes", "vape", "pouches", "other"])
def test_quit_plan_accepts_every_supported_nicotine_type(nicotine_type):
    plan = QuitPlanInput(**_valid_plan(nicotine_type=nicotine_type))
    assert plan.nicotine_type == nicotine_type


def test_quit_plan_rejects_an_unsupported_nicotine_type():
    with pytest.raises(ValidationError):
        QuitPlanInput(**_valid_plan(nicotine_type="cigars"))


@pytest.mark.parametrize("daily_consumption", [0, -1, 1_001])
def test_quit_plan_rejects_daily_consumption_outside_the_allowed_range(daily_consumption):
    with pytest.raises(ValidationError):
        QuitPlanInput(**_valid_plan(daily_consumption=daily_consumption))


def test_quit_plan_accepts_zero_unit_cost_for_a_free_habit():
    # A pouch or vape user might genuinely report a zero marginal cost (already owned
    # supply); the field allows ge=0 deliberately.
    plan = QuitPlanInput(**_valid_plan(unit_cost=0))
    assert plan.unit_cost == 0


def test_quit_plan_rejects_a_negative_unit_cost():
    with pytest.raises(ValidationError):
        QuitPlanInput(**_valid_plan(unit_cost=-0.01))


@pytest.mark.parametrize("reminder_hour", [-1, 24])
def test_quit_plan_rejects_reminder_hour_outside_a_day(reminder_hour):
    with pytest.raises(ValidationError):
        QuitPlanInput(**_valid_plan(reminder_hour=reminder_hour))


def test_quit_plan_allows_no_reminder():
    plan = QuitPlanInput(**_valid_plan(reminder_hour=None))
    assert plan.reminder_hour is None


def test_check_in_rejects_intensity_outside_one_to_ten():
    with pytest.raises(ValidationError):
        CheckInInput(
            intensity=11,
            trigger="Stress",
            coping_action="Walk",
            note=None,
            resisted=True,
            occurred_at=datetime.now(UTC),
        )


def test_check_in_requires_a_non_empty_trigger():
    with pytest.raises(ValidationError):
        CheckInInput(
            intensity=5,
            trigger="",
            coping_action="Walk",
            note=None,
            resisted=True,
            occurred_at=datetime.now(UTC),
        )


def test_conversation_turn_rejects_an_invalid_role():
    with pytest.raises(ValidationError):
        ConversationTurn(role="system", content="hello")
