"""Cliente da Musixmatch — busca por trecho de letra.

Docs: https://developer.musixmatch.com/documentation
"""
from __future__ import annotations

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

SEARCH_ENDPOINT = "https://api.musixmatch.com/ws/1.1/track.search"


class LyricsSearchHit:
    def __init__(self, title: str, artist: str, album: str | None, isrc: str | None):
        self.title = title
        self.artist = artist
        self.album = album
        self.isrc = isrc


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def search_by_lyrics(query: str, limit: int = 10) -> list[LyricsSearchHit]:
    settings = get_settings()
    if not settings.musixmatch_api_key:
        raise RuntimeError("MUSIXMATCH_API_KEY não configurado — veja backend/.env.example")

    params = {
        "q_lyrics": query,
        "page_size": limit,
        "s_track_rating": "desc",
        "apikey": settings.musixmatch_api_key,
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(SEARCH_ENDPOINT, params=params)
        response.raise_for_status()
        payload = response.json()

    track_list = payload.get("message", {}).get("body", {}).get("track_list", [])
    hits = []
    for item in track_list:
        track = item.get("track", {})
        hits.append(
            LyricsSearchHit(
                title=track.get("track_name", "Desconhecido"),
                artist=track.get("artist_name", "Desconhecido"),
                album=track.get("album_name"),
                isrc=track.get("track_isrc") or None,
            )
        )
    return hits
