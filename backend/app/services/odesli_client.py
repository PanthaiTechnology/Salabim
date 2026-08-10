"""Cliente do Odesli (song.link) — a partir de um ISRC ou URL de qualquer plataforma,
devolve os links equivalentes em Spotify, Apple Music, Deezer, Tidal, YouTube Music etc.

Docs: https://odesli.co/documentation
"""
from __future__ import annotations

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings
from app.models.schemas import PlatformLink

ODESLI_ENDPOINT = "https://api.song.link/v1-alpha.1/links"

# Mapeamento das chaves que a Odesli usa -> nomes canônicos do Salabim
_PLATFORM_MAP = {
    "spotify": "spotify",
    "appleMusic": "apple_music",
    "deezer": "deezer",
    "tidal": "tidal",
    "youtubeMusic": "youtube_music",
    "youtube": "youtube",
    "amazonMusic": "amazon_music",
    "soundcloud": "soundcloud",
}


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def resolve_platform_links(*, isrc: str | None = None, source_url: str | None = None) -> list[PlatformLink]:
    """Passe `isrc` (preferível) ou uma `source_url` de qualquer plataforma suportada."""
    settings = get_settings()
    if not isrc and not source_url:
        return []

    params: dict[str, str] = {}
    if isrc:
        # Validado manualmente contra a API real: platform="isrc" + type="song"
        # (não "type=isrc" — isso retorna erro "invalid_entity_type").
        params["songIfSingle"] = "true"
        params["id"] = isrc
        params["platform"] = "isrc"
        params["type"] = "song"
    if source_url:
        params = {"url": source_url}
    if settings.odesli_api_key:
        params["key"] = settings.odesli_api_key

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(ODESLI_ENDPOINT, params=params)
        if response.status_code != 200:
            return []
        payload = response.json()

    links_by_platform = payload.get("linksByPlatform", {})
    result: list[PlatformLink] = []
    for provider_key, canonical in _PLATFORM_MAP.items():
        entry = links_by_platform.get(provider_key)
        if entry and entry.get("url"):
            result.append(PlatformLink(platform=canonical, url=entry["url"]))
    return result
