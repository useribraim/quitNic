from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "QuitNic API"
    environment: str = "development"
    database_url: str = "sqlite+aiosqlite:///./quitnic.db"
    openai_api_key: str | None = None
    openai_model: str = "gpt-4.1-mini"
    openai_transcription_model: str = "gpt-4o-transcribe"
    coaching_provider: str = "auto"
    coaching_requests_per_minute: int = 10
    token_pepper: str = "development-only-change-me"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
