"""GET /v1/health — usado por load balancer, monitoramento, e pela tela de debug do app."""
from __future__ import annotations

from fastapi import APIRouter

from app.config import get_settings
from app.models.schemas import HealthResponse

router = APIRouter(prefix="/v1", tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(status="ok", providers=settings.recognition_providers_configured)
