"""Modelos Pydantic (contrato público da API)."""
from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, Field


class ListenMode(str, Enum):
    listen = "listen"  # música tocando no ambiente -> AudD
    hum = "hum"  # cantarolar / cantar / assobiar / instrumento -> ACRCloud Humming


class TextSearchKind(str, Enum):
    lyrics = "lyrics"  # trecho da letra -> Musixmatch
    description = "description"  # descrição livre -> busca semântica própria


class PlatformLink(BaseModel):
    platform: str = Field(..., description="spotify | apple_music | deezer | tidal | youtube_music | amazon_music")
    url: str


class Track(BaseModel):
    id: str = Field(..., description="ID interno estável (hash do ISRC ou do provedor)")
    title: str
    artist: str
    album: str | None = None
    artwork_url: str | None = None
    isrc: str | None = None
    release_date: str | None = None
    preview_url: str | None = Field(None, description="URL de preview OFICIAL (iTunes/Deezer/Spotify), nunca recorte próprio")
    matched_provider: str = Field(..., description="audd | acrcloud | musixmatch")
    match_confidence: float | None = None
    platform_links: list[PlatformLink] = []


class IdentifyResponse(BaseModel):
    found: bool
    track: Track | None = None
    message: str | None = None


class TextSearchRequest(BaseModel):
    query: str = Field(..., min_length=2, max_length=500)
    kind: TextSearchKind = TextSearchKind.lyrics


class TextSearchResponse(BaseModel):
    results: list[Track] = []


class HistoryItem(BaseModel):
    track: Track
    searched_at: str
    mode: str


class HealthResponse(BaseModel):
    status: str
    providers: dict[str, bool]
