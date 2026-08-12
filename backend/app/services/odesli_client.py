"""Cliente do Odesli (song.link) — a partir de um ISRC ou URL de qualquer plataforma,
devolve os links equivalentes em Spotify, Apple Music, Deezer, Tidal, YouTube Music etc.

Docs: https://odesli.co/documentation

Importante (bug real encontrado em produção): a cota gratuita do Odesli é
baixa e retorna 429 (Too Many Requests) rápido — bastou a busca por texto
resolver link pra vários resultados de uma vez pra estourar a cota e
derrubar os links de TODAS as buscas (inclusive Ouvir/Cantar) até resetar.
Por isso: cache local agressivo (nunca gasta cota duas vezes pra mesma
música) e retry com espera quando bate 429, em vez de desistir na hora.
"""
from __future__ import annotations

import json

import httpx
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from app.config import get_settings
from app.core.cache import get_redis
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

_CACHE_TTL_FOUND = 60 * 60 * 24 * 7  # 7 dias — links de plataforma raramente mudam
_CACHE_TTL_EMPTY = 60 * 30  # resultado vazio cacheia por menos tempo (pode ter sido só rate limit)


class _RateLimited(Exception):
    pass


def _cache_key(isrc: str | None, source_url: str | None) -> str:
    return f"salabim:odesli:{isrc or source_url}"


@retry(
    retry=retry_if_exception_type(_RateLimited),
    stop=stop_after_attempt(3),
    wait=wait_exponential(min=2, max=20),
    retry_error_callback=lambda _retry_state: [],
)
async def _fetch_from_odesli(params: dict) -> list[PlatformLink]:
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(ODESLI_ENDPOINT, params=params)

    if response.status_code == 429:
        # Vale a pena esperar e tentar de novo (o decorator cuida do
        # backoff) — desistir na hora é o que causava links sumindo em
        # busca inteira só porque um resultado bateu rate limit.
        raise _RateLimited()
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


async def resolve_platform_links(*, isrc: str | None = None, source_url: str | None = None) -> list[PlatformLink]:
    """Passe `isrc` (preferível) ou uma `source_url` de qualquer plataforma suportada."""
    settings = get_settings()
    if not isrc and not source_url:
        return []

    r = get_redis()
    cache_key = _cache_key(isrc, source_url)
    cached = await r.get(cache_key)
    if cached is not None:
        return [PlatformLink(**item) for item in json.loads(cached)]

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

    result = await _fetch_from_odesli(params)

    ttl = _CACHE_TTL_FOUND if result else _CACHE_TTL_EMPTY
    await r.set(cache_key, json.dumps([link.model_dump() for link in result]), ex=ttl)
    return result
