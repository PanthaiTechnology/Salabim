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
    matched_provider: str = Field(..., description="audd | acrcloud | musixmatch | itunes")
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


class ListenSessionReport(BaseModel):
    """Sessão do Ouvir de ponta a ponta, medida no cliente (mobile) — ver
    recognition_metrics.record_listen_session para o motivo de existir."""

    outcome: str = Field(..., description="found | not_found | cancelled | error")
    attempts: int = Field(..., ge=0)
    total_ms: int = Field(..., ge=0)


class EnrichTrackRequest(BaseModel):
    """Metadado já identificado por fora (SDK on-device do ACRCloud —
    branch de teste, ver ARCHITECTURE.md §4.3/4.4) que só precisa ser
    completado com capa/preview/links — ver
    recognition_service.enrich_track_from_metadata."""

    title: str
    artist: str
    album: str | None = None
    isrc: str | None = None
    match_confidence: float | None = None


class FeedbackRequest(BaseModel):
    """Feedback do usuário sobre um resultado: confirma se está certo, ou
    informa o nome real quando está errado. Vira uma correção persistente
    aplicada automaticamente da próxima vez que o mesmo engano acontecer no
    modo Cantar — ver app/services/feedback_service.py."""

    matched_title: str
    matched_artist: str
    mode: str = Field(..., description="audd | acrcloud | musixmatch — qual motor gerou esse resultado")
    was_correct: bool
    corrected_title: str | None = None
    corrected_artist: str | None = None
