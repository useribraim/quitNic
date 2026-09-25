from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "QuitNic API"
    environment: str = "development"
    database_url: str = "sqlite+aiosqlite:///./quitnic.db"
    openai_api_key: str | None = None
    # gpt-4.1-mini is deprecated. gpt-5.4-mini is the current budget-tier model:
    # meaningfully better instruction-following than 4.1-mini at a comparable per-word
    # cost for QuitNic's short, bounded coaching replies. gpt-5.4-nano is cheaper still
    # (~4x) but trades away reasoning quality this app leans on for reading craving
    # context and tone; not worth it for a wellbeing-facing product.
    openai_model: str = "gpt-5.4-mini"
    openai_transcription_model: str = "gpt-4o-transcribe"
    coaching_provider: str = "auto"
    coaching_requests_per_minute: int = 10
    token_pepper: str = "development-only-change-me"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
