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


@pytest.mark.parametrize("message", ["I might kill myself", "I cannot breathe", "chest pain"])
def test_crisis_detection_bypasses_all_coaching_providers(message):
    assert is_crisis(message)
