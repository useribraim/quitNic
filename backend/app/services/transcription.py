from openai import AsyncOpenAI

from ..core.config import get_settings


class OpenAITranscriptionProvider:
    """Transcribes an ephemeral Push-to-Talk audio clip without persisting audio."""

    async def transcribe(self, filename: str, content: bytes, content_type: str) -> str:
        settings = get_settings()
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is not configured")
        if not content:
            raise ValueError("Audio clip was empty")
        client = AsyncOpenAI(api_key=settings.openai_api_key)
        response = await client.audio.transcriptions.create(
            model=settings.openai_transcription_model,
            file=(filename, content, content_type),
        )
        return response.text.strip()
