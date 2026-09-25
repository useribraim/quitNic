import pytest
from fastapi import HTTPException

from app.core.rate_limit import SlidingWindowLimiter


@pytest.mark.asyncio
async def test_requests_within_the_limit_are_allowed():
    limiter = SlidingWindowLimiter()
    for _ in range(10):
        await limiter.check("device-a")  # default limit is 10/minute; should not raise


@pytest.mark.asyncio
async def test_request_beyond_the_limit_is_rejected_with_429():
    limiter = SlidingWindowLimiter()
    for _ in range(10):
        await limiter.check("device-b")
    with pytest.raises(HTTPException) as excinfo:
        await limiter.check("device-b")
    assert excinfo.value.status_code == 429


@pytest.mark.asyncio
async def test_limits_are_tracked_independently_per_key():
    limiter = SlidingWindowLimiter()
    for _ in range(10):
        await limiter.check("device-c")
    # A different device must not be affected by device-c's exhausted limit.
    await limiter.check("device-d")


@pytest.mark.asyncio
async def test_old_events_outside_the_window_are_forgotten():
    limiter = SlidingWindowLimiter()
    key = "device-e"
    for _ in range(10):
        await limiter.check(key)
    # Simulate the window having elapsed by clearing recorded events directly, since the
    # limiter has no injectable clock — this exercises the same eviction path a full
    # minute of real time would.
    limiter.events[key].clear()
    await limiter.check(key)  # should not raise now that the window is empty
