"""Cliente da API oficial do Spotify — usado como camada extra pra garantir o
link do Spotify quando o Odesli não tiver ele mapeado pra uma faixa específica.

Bug real encontrado em produção: pra várias músicas (confirmado com "Karma"
de Summer Walker), a resposta do Odesli simplesmente não traz uma entrada
"spotify" no linksByPlatform, mesmo a faixa estando lançada lá oficialmente —
não é bug do nosso filtro, é uma lacuna real no banco de correspondência
cruzada deles. Como o Spotify é a plataforma mais usada (pedido explícito do
produto: sempre mostrar primeiro, logo abaixo do nome do artista, quando
disponível), esse cliente busca direto no catálogo do Spotify como reforço
quando isso acontece.

Flufo "Client Credentials"
(https://developer.spotify.com/documentation/web-api/tutorials/client-credentials-flow)
— só dá acesso ao catálogo público (busca), sem precisar de login do usuário
final. Token cacheado no Redis até expirar (dura ~1h).
"""
from __future__ import annotations

import base64

import httpx

from app.config import get_settings
from app.core.cache import get_redis

TOKEN_ENDPOINT = "https://accounts.spotify.com/api/token"
SEARCH_ENDPOINT = "https://api.spotify.com/v1/search"

_TOKEN_CACHE_KEY = "salabim:spotify:token"


async def _get_access_token() -> str | None:
    settings = get_settings()
    if not settings.spotify_client_id or not settings.spotify_client_secret:
        return None

    r = get_redis()
    cached = await r.get(_TOKEN_CACHE_KEY)
    if cached is not None:
        return cached.decode() if isinstance(cached, bytes) else cached

    credentials = f"{settings.spotify_client_id}:{settings.spotify_client_secret}"
    basic_auth = base64.b64encode(credentials.encode()).decode()

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(
            TOKEN_ENDPOINT,
            data={"grant_type": "client_credentials"},
            headers={"Authorization": f"Basic {basic_auth}"},
        )
    if response.status_code != 200:
        return None

    payload = response.json()
    token = payload.get("access_token")
    expires_in = payload.get("expires_in", 3600)
    if token:
        # Margem de 60s de segurança antes do token expirar de verdade.
        await r.set(_TOKEN_CACHE_KEY, token, ex=max(expires_in - 60, 60))
    return token


def _normalize(name: str) -> str:
    return name.lower().strip()


async def search_track_url(title: str, artist: str) -> str | None:
    """Busca uma faixa pelo título+artista direto no catálogo do Spotify e
    devolve a URL pública (open.spotify.com/track/...), ou None se não achar
    com confiança ou se as credenciais não estiverem configuradas (ver
    .env.example — SPOTIFY_CLIENT_ID/SPOTIFY_CLIENT_SECRET)."""
    token = await _get_access_token()
    if not token:
        return None

    query = f"track:{title} artist:{artist}"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                SEARCH_ENDPOINT,
                params={"q": query, "type": "track", "limit": 5},
                headers={"Authorization": f"Bearer {token}"},
            )
    except httpx.HTTPError:
        return None

    if response.status_code != 200:
        return None

    items = response.json().get("tracks", {}).get("items", [])
    if not items:
        return None

    # Confirma que título/artista batem de verdade antes de aceitar — busca
    # do Spotify às vezes traz um resultado só remotamente parecido primeiro
    # (ex: cover, remix, faixa de outro artista com nome parecido).
    target_title = _normalize(title)
    target_artist = _normalize(artist)
    for item in items:
        item_title = _normalize(item.get("name", ""))
        item_artists = [_normalize(a.get("name", "")) for a in item.get("artists", [])]
        title_matches = target_title in item_title or item_title in target_title
        artist_matches = any(target_artist in a or a in target_artist for a in item_artists)
        if title_matches and artist_matches:
            return item.get("external_urls", {}).get("spotify")

    return None
