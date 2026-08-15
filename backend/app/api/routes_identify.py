"""POST /v1/identify — modo "ouvir" (fingerprint) ou "hum" (cantarolar/assobiar/cantar/instrumento)."""
from __future__ import annotations

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status

from app.core.cache import check_rate_limit
from app.models.schemas import EnrichTrackRequest, IdentifyResponse, ListenMode, Track
from app.services.recognition_service import enrich_track_from_metadata, identify_from_audio

router = APIRouter(prefix="/v1", tags=["identify"])

MAX_AUDIO_BYTES = 10 * 1024 * 1024  # 10MB, ~ suficiente para 12s de áudio não comprimido


@router.post("/identify", response_model=IdentifyResponse)
async def identify(
    request: Request,
    file: UploadFile = File(..., description="Trecho de áudio gravado no app (8-12s)"),
    mode: ListenMode = Form(ListenMode.listen),
) -> IdentifyResponse:
    client_ip = request.client.host if request.client else "unknown"
    if not await check_rate_limit(client_ip):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Muitas buscas em pouco tempo, tente novamente em instantes.")

    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Arquivo de áudio vazio.")
    if len(audio_bytes) > MAX_AUDIO_BYTES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Áudio muito grande (máx 10MB).")

    track = await identify_from_audio(audio_bytes, mode)
    if track is None:
        return IdentifyResponse(found=False, message="Não conseguimos identificar essa música. Tente gravar de novo, mais perto da fonte de som.")
    return IdentifyResponse(found=True, track=track)


@router.post("/identify/enrich", response_model=Track)
async def identify_enrich(request: Request, payload: EnrichTrackRequest) -> Track:
    """Completa um resultado que já veio identificado de fora (branch de
    teste do SDK on-device do ACRCloud, ver ARCHITECTURE.md §4.3/4.4) com
    capa/preview/links — mesmo enriquecimento que os outros caminhos
    (AudD, ACRCloud REST) já fazem, ver
    recognition_service.enrich_track_from_metadata."""
    client_ip = request.client.host if request.client else "unknown"
    if not await check_rate_limit(client_ip):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Muitas buscas em pouco tempo, tente novamente em instantes.")

    return await enrich_track_from_metadata(
        title=payload.title,
        artist=payload.artist,
        album=payload.album,
        isrc=payload.isrc,
        matched_provider="acrcloud",
        match_confidence=payload.match_confidence,
    )
