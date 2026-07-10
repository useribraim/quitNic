from abc import ABC, abstractmethod
from typing import Any

from openai import AsyncOpenAI

from ..core.config import get_settings
from ..schemas import ConversationTurn

SAFETY_RESPONSE = (
    "I’m sorry you’re dealing with this. I can’t provide emergency or medical care. "
    "If you may be in immediate danger, contact local emergency services now. "
    "Otherwise, please contact a qualified healthcare professional or crisis service in your area."
)
CRISIS_TERMS = (
    "suicide",
    "kill myself",
    "overdose",
    "chest pain",
    "can't breathe",
    "cannot breathe",
)
SYSTEM_PROMPT = """You are a brief, supportive nicotine-quit coach. Use practical behavioural
strategies such as delaying, breathing, changing location, drinking water, and recalling motivation.
Do not diagnose, provide medication instructions, invent health claims, or claim to replace
a clinician.
Ask at most one question. Keep responses under 140 words. Do not request identifying information."""


class CoachingProvider(ABC):
    @abstractmethod
    async def respond(self, message: str, context: list[ConversationTurn]) -> str: ...


class OpenAICoachingProvider(CoachingProvider):
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is not configured")
        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.openai_model

    async def respond(self, message: str, context: list[ConversationTurn]) -> str:
        input_messages: Any = [
            {"role": turn.role, "content": turn.content} for turn in context[-10:]
        ]
        input_messages.append({"role": "user", "content": message})
        response = await self.client.responses.create(
            model=self.model,
            instructions=SYSTEM_PROMPT,
            input=input_messages,
            max_output_tokens=250,
        )
        return response.output_text.strip()


def is_crisis(message: str) -> bool:
    normalized = message.casefold()
    return any(term in normalized for term in CRISIS_TERMS)


def get_coaching_provider() -> CoachingProvider:
    return OpenAICoachingProvider()
