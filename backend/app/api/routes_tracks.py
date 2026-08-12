"""GET /v1/tracks/{id} — detalhe completo de uma faixa, resolvendo os links
de plataforma sob demanda se ainda não tiverem sido resolvidos (ver
recognition_service.get_track_details)."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.models.schemas import Track
from app.services import recognition_service

router = APIRouter(prefix="/v1", tags=["tracks"])


@router.get("/tracks/{track_id}", response_model=Track)
async def get_track(track_id: str) -> Track:
    track = await recognition_service.get_track_details(track_id)
    if track is None:
        raise HTTPException(404, "Faixa não encontrada ou expirada — busca de novo.")
    return track
