import pytest

from app.services.coaching import DevelopmentCoachingProvider, get_coaching_provider, is_crisis


def test_development_defaults_to_deterministic_provider_without_api_key():
    assert isinstance(get_coaching_provider(), DevelopmentCoachingProvider)


@pytest.mark.asyncio
async def test_development_coach_returns_practical_craving_response():
    provider = DevelopmentCoachingProvider()
    response = await provider.respond("I have a strong craving after lunch", [])

    assert "two-minute reset" in response
    assert "breaths" in response
    assert len(response) < 500


@pytest.mark.asyncio
async def test_development_coach_is_deterministic():
    provider = DevelopmentCoachingProvider()

    first = await provider.respond("I feel stressed", [])
    second = await provider.respond("I feel stressed", [])

    assert first == second


@pytest.mark.asyncio
async def test_development_coach_reflects_the_theme_of_the_message():
    provider = DevelopmentCoachingProvider()

    stress = await provider.respond("work is so stressful today", [])
    slip = await provider.respond("I gave in and smoked one", [])

    assert stress != slip
    assert "stress" in stress.casefold() or "pressure" in stress.casefold()
    assert "slip" in slip.casefold() or "lapse" in slip.casefold() or "honest" in slip.casefold()


@pytest.mark.asyncio
async def test_development_coach_does_not_return_one_canned_string():
    provider = DevelopmentCoachingProvider()
    messages = [
        "I have a craving",
        "I feel stressed",
        "I am bored",
        "I am at a party and everyone is vaping",
        "I slipped yesterday",
        "help me plan the next hour",
    ]
    replies = {await provider.respond(message, []) for message in messages}
    # Distinct themes must not collapse to the same sentence.
    assert len(replies) >= 5


@pytest.mark.parametrize(
    "message",
    [
        "I might kill myself",
        "I cannot breathe",
        "chest pain",
        "I can’t breathe",
        "my chest is tight and I can't breathe",
        "I just want to die",
        "thinking about ending my life",
        "I think I have nicotine poisoning",
    ],
)
def test_crisis_detection_bypasses_all_coaching_providers(message):
    assert is_crisis(message)


@pytest.mark.parametrize(
    "message",
    ["I have a craving after coffee", "I feel proud of my progress", "help me plan tonight"],
)
def test_ordinary_messages_are_not_flagged_as_crisis(message):
    assert not is_crisis(message)


@pytest.mark.parametrize(
    "message",
    [
        # iOS smart punctuation substitutes a curly apostrophe as the user types.
        "my chest is tight and I can’t breathe",
        "I can’t breathe",
        "I can't breathe",
        "I don’t want to live anymore",
        "I want to hurt myself",
        "I think I'm having a heart attack",
        "CHEST PAIN!!!",
        "  i   am   suicidal  ",
    ],
)
def test_crisis_detection_survives_real_keyboard_output(message):
    assert is_crisis(message)


@pytest.mark.parametrize(
    "message",
    [
        "I have a craving after coffee",
        "work is stressful today",
        "I killed it at the gym instead of smoking",
    ],
)
def test_ordinary_messages_are_not_escalated(message):
    assert not is_crisis(message)
