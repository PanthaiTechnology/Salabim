"""POST /v1/identify — modo "ouvir" (fingerprint) ou "hum" (cantarolar/assobiar/cantar/instrumento)."""
from __future__ import annotations

import time

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status

from app.core.cache import check_rate_limit
from app.models.schemas import IdentifyResponse, ListenMode
from app.services.recognition_service import identify_from_audio

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

    # DEBUG temporário — investigando resposta instantânea/errada relatada
    # no modo Cantar (ver conversa). Remover depois de identificar a causa.
    t0 = time.monotonic()
    print(f"[DEBUG identify] mode={mode.value} audio_bytes={len(audio_bytes)} client={client_ip}", flush=True)

    track = await identify_from_audio(audio_bytes, mode)
    elapsed = time.monotonic() - t0
    print(
        f"[DEBUG identify] mode={mode.value} elapsed={elapsed:.2f}s "
        f"found={track is not None} title={getattr(track, 'title', None)!r} artist={getattr(track, 'artist', None)!r}",
        flush=True,
    )
    if track is None:
        return IdentifyResponse(found=False, message="Não conseguimos identificar essa música. Tente gravar de novo, mais perto da fonte de som.")
    return IdentifyResponse(found=True, track=track)
