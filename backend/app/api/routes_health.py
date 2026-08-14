"""GET /v1/health — usado por load balancer, monitoramento, e pela tela de debug do app."""
from __future__ import annotations

from fastapi import APIRouter, Query

from app.config import get_settings
from app.models.schemas import HealthResponse
from app.services import recognition_metrics

router = APIRouter(prefix="/v1", tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(status="ok", providers=settings.recognition_providers_configured)


@router.get("/debug/identify-stats")
async def identify_stats(
    mode: str | None = Query(None, description="listen | hum — filtra por modo"),
    provider: str | None = Query(None, description="audd | acrcloud — filtra por provedor"),
    limit: int = Query(500, ge=1, le=2000, description="quantos eventos recentes considerar"),
) -> dict:
    """Latência e taxa de acerto dos identifies recentes (ver
    recognition_metrics.py) — existe pra comparar configurações (provedor,
    duração de segmento, etc.) com número real em vez de teste manual "por
    sensação". Sem autenticação: só expõe agregados de latência/taxa de
    acerto, nada sensível (sem áudio, sem conteúdo de faixa, sem
    identificador de usuário)."""
    return await recognition_metrics.recent_stats(mode=mode, provider=provider, limit=limit)
