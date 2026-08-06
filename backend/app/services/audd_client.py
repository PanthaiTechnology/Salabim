"""Cliente do AudD — fingerprint de áudio gravado (modo "ouvir", equivalente ao Shazam).

Docs: https://docs.audd.io/
"""
from __future__ import annotations

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

AUDD_ENDPOINT = "https://api.audd.io/"


class AudDResult:
    def __init__(self, title: str, artist: str, album: str | None, isrc: str | None,
                 artwork_url: str | None, preview_url: str | None, release_date: str | None):
        self.title = title
        self.artist = artist
        self.album = album
        self.isrc = isrc
        self.artwork_url = artwork_url
        self.preview_url = preview_url
        self.release_date = release_date


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def identify_audio(audio_bytes: bytes, filename: str = "audio.m4a") -> AudDResult | None:
    settings = get_settings()
    if not settings.audd_api_token:
        raise RuntimeError("AUDD_API_TOKEN não configurado — veja backend/.env.example")

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(
            AUDD_ENDPOINT,
            data={
                "api_token": settings.audd_api_token,
                "return": "apple_music,spotify",
            },
            files={"file": (filename, audio_bytes)},
        )
        response.raise_for_status()
        payload = response.json()

    if payload.get("status") != "success" or not payload.get("result"):
        return None

    result = payload["result"]
    apple = result.get("apple_music") or {}
    spotify = result.get("spotify") or {}

    artwork_url = None
    if apple.get("artwork"):
        artwork_url = apple["artwork"]["url"].replace("{w}", "500").replace("{h}", "500")
    elif spotify.get("album", {}).get("images"):
        artwork_url = spotify["album"]["images"][0]["url"]

    preview_url = apple.get("previews", [{}])[0].get("url") if apple.get("previews") else None

    return AudDResult(
        title=result.get("title", "Desconhecido"),
        artist=result.get("artist", "Desconhecido"),
        album=result.get("album"),
        isrc=result.get("isrc") or apple.get("isrc"),
        artwork_url=artwork_url,
        preview_url=preview_url,
        release_date=result.get("release_date"),
    )
