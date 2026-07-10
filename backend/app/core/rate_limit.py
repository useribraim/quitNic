import asyncio
import time
from collections import defaultdict, deque

from fastapi import HTTPException

from .config import get_settings


class SlidingWindowLimiter:
    def __init__(self) -> None:
        self.events: dict[str, deque[float]] = defaultdict(deque)
        self.lock = asyncio.Lock()

    async def check(self, key: str) -> None:
        now = time.monotonic()
        limit = get_settings().coaching_requests_per_minute
        async with self.lock:
            events = self.events[key]
            while events and events[0] <= now - 60:
                events.popleft()
            if len(events) >= limit:
                raise HTTPException(429, "Coaching request limit reached")
            events.append(now)


coaching_limiter = SlidingWindowLimiter()
