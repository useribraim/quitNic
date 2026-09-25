import hashlib
import re
import unicodedata
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
    # Self-harm and suicidality
    "suicide",
    "suicidal",
    "kill myself",
    "killing myself",
    "end my life",
    "ending my life",
    "end it all",
    "take my own life",
    "want to die",
    "wanna die",
    "better off dead",
    "dont want to live",
    "dont want to be here anymore",
    "no reason to live",
    "hurt myself",
    "harm myself",
    "hurting myself",
    "cut myself",
    "kms",
    # Acute medical
    "overdose",
    "overdosed",
    "chest pain",
    "chest is tight",
    "tightness in my chest",
    "pain in my chest",
    "crushing chest",
    "cant breathe",
    "cannot breathe",
    "cant catch my breath",
    "struggling to breathe",
    "trouble breathing",
    "difficulty breathing",
    "heart attack",
    "stroke",
    "passing out",
    "passed out",
    "fainted",
    "coughing up blood",
    "poisoning",
    "nicotine poisoning",
)

# Characters that iOS smart punctuation, autocorrect, or a paste can substitute for a
# plain ASCII apostrophe. Without folding these, "can't breathe" typed on an iPhone
# arrives as "can’t breathe" and never matches a term list written with "'".
_APOSTROPHES = "’‘ʼʻ′´`"
_WHITESPACE_RUN = re.compile(r"\s+")
_STRIPPABLE = re.compile(r"[^a-z0-9\s]")


def normalize(message: str) -> str:
    """Fold a message to a comparable form: lowercase, apostrophes removed, punctuation
    dropped and whitespace collapsed. Terms above are written in this same folded form."""
    folded = unicodedata.normalize("NFKC", message).casefold()
    for character in _APOSTROPHES:
        folded = folded.replace(character, "'")
    folded = folded.replace("'", "")
    folded = _STRIPPABLE.sub(" ", folded)
    return _WHITESPACE_RUN.sub(" ", folded).strip()
SYSTEM_PROMPT = """You are a brief, supportive nicotine-quit coach. Use practical behavioural
strategies such as delaying, breathing, changing location, drinking water, and recalling motivation.
Do not diagnose, provide medication instructions, invent health claims, or claim to replace
a clinician.

Write in plain conversational sentences, the way a supportive friend would text — never
Markdown, never bullet points, never numbered lists, never bold or headers. The reply is
shown as a plain chat bubble that cannot render formatting, so a list reads as broken text.

Do not default to the same checklist of tactics every time. Read what is actually distinct
about this message — the setting, the trigger, whether it is a craving, a slip, or a win —
and let that shape which one or two suggestions you offer, in your own words, rather than
repeating a fixed five-step routine.

Ask at most one question. Keep responses under 140 words. Do not request identifying information."""


VOICE_STYLE_PROMPT = """This reply is spoken out loud in a live voice conversation, not read on a
screen. Answer in at most three short sentences, under 60 words total. Use spoken words only:
no lists, no headings, no emoji, no asterisks, no numerals written as digits when a word reads
better. Sound like a calm person talking, not like a document. End with one short question the
person can answer out loud, or with nothing at all."""


class CoachingProvider(ABC):
    @abstractmethod
    async def respond(
        self, message: str, context: list[ConversationTurn], style: str = "chat"
    ) -> str: ...


class OpenAICoachingProvider(CoachingProvider):
    def __init__(self) -> None:
        settings = get_settings()
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is not configured")
        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.openai_model

    async def respond(
        self, message: str, context: list[ConversationTurn], style: str = "chat"
    ) -> str:
        input_messages: Any = [
            {"role": turn.role, "content": turn.content} for turn in context[-10:]
        ]
        input_messages.append({"role": "user", "content": message})
        instructions = SYSTEM_PROMPT
        if style == "voice":
            instructions = f"{SYSTEM_PROMPT}\n\n{VOICE_STYLE_PROMPT}"
        response = await self.client.responses.create(
            model=self.model,
            instructions=instructions,
            input=input_messages,
            max_output_tokens=250 if style == "chat" else 160,
        )
        return response.output_text.strip()


class DevelopmentCoachingProvider(CoachingProvider):
    """Deterministic, offline coach used when no AI provider is configured.

    It is intentionally not a single canned string: it reads the message for a theme,
    reflects a word back, and rotates between a few worded variants so a person who
    sends two different messages gets two different replies. The same message always
    produces the same reply, which keeps it testable and predictable.
    """

    # Ordered by specificity — the first theme whose keywords appear wins.
    _THEMES: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = (
        (
            "craving",
            (
                "craving", "crave", "urge", "want one", "want a",
                "want to smoke", "want to vape", "need a", "dying for",
            ),
            (
                "Cravings peak and pass, usually within a few minutes. Try a two-minute reset: "
                "step somewhere different, take five slow breaths, and drink some water. What is "
                "one thing you could do with your hands right now?",
                "This urge is real, and it is also temporary. Give it a two-minute reset — five "
                "slow breaths and a change of room or posture. The wave crests and then it drops. "
                "What usually helps you ride out the first few minutes?",
                "You do not have to fight the whole day, only the next few minutes. Start a "
                "two-minute reset: long, slow breaths and a little movement. Cravings shrink when "
                "you stop feeding them attention. What small action fits your next ten minutes?",
            ),
        ),
        (
            "slip",
            (
                "slip", "relapse", "gave in", "caved", "i smoked", "i vaped", "i used",
                "bought a", "one cigarette", "messed up", "failed", "broke my streak",
            ),
            (
                "A slip is a moment, not the end of your progress. What matters is the next "
                "choice, and you are already making it by checking in. What was happening just "
                "before it? Naming the trigger takes some of its power away.",
                "One slip does not erase the days you have already put behind you. Be as kind to "
                "yourself as you would be to a friend, then pick the very next small step. What "
                "would help you steady the next hour?",
                "Thank you for being honest — that is how this stays useful. A lapse is data, not "
                "a verdict. Let us look at what led up to it and set up one guardrail for the same "
                "moment tomorrow. What triggered it?",
            ),
        ),
        (
            "stress",
            (
                "stress", "stressed", "overwhelm", "anxious", "anxiety",
                "panic", "worried", "tense", "on edge",
            ),
            (
                "Stress can make an old routine feel automatic. Pause and name what is weighing on "
                "you, then pick one short release — a walk, a glass of water, or a message to "
                "someone. Which feels doable right now?",
                "When everything feels tight, shrink the problem: the only task is the next slow "
                "breath. Nicotine promises relief it never really delivers. What is the smallest "
                "part of this you could set down for ten minutes?",
                "That pressure is real. Try lengthening your exhale — breathe out for longer than "
                "you breathe in, a few times. Then choose one grounding action. What tends to calm "
                "you when you are not reaching for nicotine?",
            ),
        ),
        (
            "bored",
            ("bored", "boredom", "nothing to do", "restless", "idle"),
            (
                "Boredom is one of the sneakiest triggers because the urge fills empty time. Give "
                "your hands and attention something else for ten minutes — a short walk, tidying "
                "one surface, a quick message. What could you start in the next minute?",
                "An idle moment does not have to become a craving. Line up a two-minute activity "
                "you actually enjoy so the gap is already filled. What is something small that "
                "usually holds your focus?",
            ),
        ),
        (
            "social",
            (
                "party", "friends", "everyone is", "everyone's", "drinking", "bar",
                "social", "people are vaping", "people are smoking", "offered me",
            ),
            (
                "Being around it is one of the hardest tests, so give yourself credit for staying "
                "aware. Plan a simple line to decline and something to hold — a drink, your phone. "
                "Can you step outside for two minutes of air?",
                "Social settings pair nicotine with everything you enjoy, which makes the pull "
                "strong. Anchor to your reason for quitting and keep your hands busy. Is there one "
                "person there you could stand near who is not using?",
            ),
        ),
        (
            "coffee",
            (
                "coffee", "after a meal", "after eating", "morning routine",
                "with my coffee", "after lunch", "after dinner",
            ),
            (
                "Routine pairings are strong because your brain expects the two together. Break "
                "the chain: change where you sit, hold the cup differently, or take a short walk "
                "right after. What could you swap in for the usual next move?",
                "That after-the-meal moment is a classic trigger. Try standing up and changing "
                "rooms as soon as you finish, so the old cue does not get its usual answer. What "
                "small new habit could take that slot?",
            ),
        ),
        (
            "plan",
            (
                "plan", "next hour", "get through", "what should i do",
                "help me", "what do i do", "advice", "tips",
            ),
            (
                "Let us make the next hour concrete. Pick one thing to do, one place to be, and "
                "one person or activity to lean on if an urge shows up. What does the next hour "
                "actually look like for you?",
                "A good plan is small and specific. Name the next trigger you expect, decide your "
                "response in advance, and keep water nearby. When do you think the next tough "
                "moment will come?",
            ),
        ),
        (
            "win",
            (
                "proud", "did it", "resisted", "made it", "day ", "days ",
                "week ", "feeling good", "went well", "milestone",
            ),
            (
                "That is worth pausing on — you chose your goal over an old habit, and that "
                "choice compounds. Notice how you did it so you can repeat it. What helped most "
                "this time?",
                "Real progress. Every craving you move through rewires the routine a little more. "
                "Bank this win somewhere you will see it later. What would make tomorrow just as "
                "steady?",
            ),
        ),
    )

    _FALLBACKS: tuple[str, ...] = (
        "You are taking a useful step just by checking in. Revisit why you started, then pick "
        "one manageable action for the next ten minutes. What feels most doable right now?",
        "I am here with you. Tell me a little more about what is happening — is this a craving, "
        "a stressful moment, or something else? We can find one small next step together.",
        "Checking in is exactly the right move. Name what you are feeling and choose a single "
        "small action to carry you through the next few minutes. What is on your mind?",
    )

    async def respond(
        self, message: str, context: list[ConversationTurn], style: str = "chat"
    ) -> str:
        normalized = normalize(message)
        variant = int(hashlib.sha256(normalized.encode("utf-8")).hexdigest(), 16)
        reply = self._FALLBACKS[variant % len(self._FALLBACKS)]
        for _name, keywords, replies in self._THEMES:
            if any(keyword.strip() in normalized for keyword in keywords):
                reply = replies[variant % len(replies)]
                break
        return shorten_for_speech(reply) if style == "voice" else reply


def shorten_for_speech(reply: str) -> str:
    """Trim a written reply down to something short enough to listen to.

    The offline coach writes screen-length paragraphs. Spoken aloud those run past the
    point where a person in a craving is still following, so voice turns keep the opening
    sentences and the closing question, which is the part that hands the turn back.
    """
    sentences = [part.strip() for part in re.split(r"(?<=[.!?])\s+", reply.strip()) if part.strip()]
    if len(sentences) <= 2:
        return " ".join(sentences)
    question = next((part for part in reversed(sentences) if part.endswith("?")), None)
    kept = [part for part in sentences[:2] if part != question]
    if question:
        kept.append(question)
    return " ".join(kept)


def is_crisis(message: str) -> bool:
    normalized = normalize(message)
    return any(term in normalized for term in CRISIS_TERMS)


def get_coaching_provider() -> CoachingProvider:
    settings = get_settings()
    if settings.coaching_provider == "mock":
        return DevelopmentCoachingProvider()
    if settings.coaching_provider == "openai":
        return OpenAICoachingProvider()
    if settings.environment == "development" and not settings.openai_api_key:
        return DevelopmentCoachingProvider()
    return OpenAICoachingProvider()
