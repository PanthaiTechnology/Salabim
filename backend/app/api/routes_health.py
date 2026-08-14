"""GET /v1/health — usado por load balancer, monitoramento, e pela tela de debug do app."""
from __future__ import annotations

from fastapi import APIRouter, Query

from app.config import get_settings
from app.models.schemas import HealthResponse, ListenSessionReport
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


@router.post("/debug/listen-session")
async def report_listen_session(payload: ListenSessionReport) -> dict:
    """Log leve do tempo TOTAL e nº de tentativas de UMA sessão do Ouvir,
    medido no cliente (mobile) — complementa /debug/identify-stats, que só
    mede a chamada à AudD (o tempo que o usuário sente de verdade é
    dominado pelo tempo de gravação entre tentativas, 100% client-side).
    Existe pra decidir onde apertar `_listenSegmentDurations` no app com
    dado real (ver ARCHITECTURE.md §4.3). Fogo-e-esquece do lado do app:
    nunca deve atrapalhar uma busca real."""
    await recognition_metrics.record_listen_session(
        outcome=payload.outcome, attempts=payload.attempts, total_ms=payload.total_ms
    )
    return {"ok": True}


@router.get("/debug/listen-session-stats")
async def listen_session_stats(
    outcome: str | None = Query(None, description="found | not_found | cancelled | error"),
    limit: int = Query(500, ge=1, le=2000, description="quantos eventos recentes considerar"),
) -> dict:
    """Agrega as sessões do Ouvir recentes: contagem por desfecho,
    histograma de quantas tentativas cada uma levou, tempo total
    médio/p50/p95 — ver recognition_metrics.recent_listen_session_stats."""
    return await recognition_metrics.recent_listen_session_stats(outcome=outcome, limit=limit)
