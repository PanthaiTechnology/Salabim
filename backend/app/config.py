"""Configuração central da aplicação, lida a partir de variáveis de ambiente (.env)."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "development"
    app_secret_key: str = "dev-secret-change-me"

    # Reconhecimento de áudio
    audd_api_token: str = ""
    acrcloud_host: str = "identify-eu-west-1.acrcloud.com"
    acrcloud_access_key: str = ""
    acrcloud_access_secret: str = ""

    # Links cross-platform e letras
    odesli_api_key: str = ""
    musixmatch_api_key: str = ""

    # Infra
    database_url: str = "postgresql+asyncpg://salabim:salabim@localhost:5432/salabim"
    redis_url: str = "redis://localhost:6379/0"

    s3_endpoint_url: str = ""
    s3_bucket: str = "salabim-audio-temp"
    s3_access_key: str = ""
    s3_secret_key: str = ""

    allowed_origins: str = "*"

    # Diretório opcional a servir em /downloads — usado só pra distribuir o
    # APK de debug pra testers via um túnel temporário (ver TESTING.md). Vazio
    # = desabilitado; nunca deve apontar pra nada em produção de verdade.
    apk_downloads_dir: str = ""

    @property
    def cors_origins(self) -> list[str]:
        if self.allowed_origins == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def recognition_providers_configured(self) -> dict[str, bool]:
        return {
            "audd": bool(self.audd_api_token),
            "acrcloud": bool(self.acrcloud_access_key and self.acrcloud_access_secret),
            "odesli": True,  # funciona sem chave em baixo volume
            "musixmatch": bool(self.musixmatch_api_key),
        }


@lru_cache
def get_settings() -> Settings:
    return Settings()
