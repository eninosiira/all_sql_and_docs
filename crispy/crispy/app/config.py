"""Settings, read once at startup.

The model is an environment variable and never a literal in the code. Moving
CRISpy to a newer model is an env change and a restart.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    openai_api_key: str = ""
    openai_model: str = "gpt-4o"
    openai_temperature: float = 0.0
    openai_timeout: int = 60

    cris_database: str = "AUDIENCE_DEV_DB"
    cris_schema: str = "CRIS"


settings = Settings()
