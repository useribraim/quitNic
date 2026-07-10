import os
from pathlib import Path

os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test-quitnic.db"
os.environ["TOKEN_PEPPER"] = "test-pepper"

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.core.database import Base, engine
from app.main import app


@pytest_asyncio.fixture(autouse=True)
async def clean_database():
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()
    Path("test-quitnic.db").unlink(missing_ok=True)


@pytest_asyncio.fixture
async def client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as value:
        yield value


@pytest_asyncio.fixture
async def authenticated(client):
    registration = await client.post("/v1/devices/register")
    token = registration.json()["access_token"]
    client.headers["Authorization"] = f"Bearer {token}"
    return client
