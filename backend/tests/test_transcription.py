import pytest

from app.services.transcription import OpenAITranscriptionProvider


@pytest.mark.asyncio
async def test_transcription_without_a_configured_key_fails_clearly():
    # conftest clears OPENAI_API_KEY for test isolation, so this exercises the guard that
    # stops the app from making a doomed network call and surfacing a raw SDK error.
    with pytest.raises(RuntimeError):
        await OpenAITranscriptionProvider().transcribe("clip.m4a", b"audio-bytes", "audio/m4a")
