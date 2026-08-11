"""POST /v1/feedback — usuário confirma ou corrige um resultado."""
from __future__ import annotations

from fastapi import APIRouter

from app.models.schemas import FeedbackRequest
from app.services import feedback_service

router = APIRouter(prefix="/v1", tags=["feedback"])


@router.post("/feedback", status_code=201)
async def submit_feedback(payload: FeedbackRequest) -> dict:
    await feedback_service.save_feedback(payload)
    return {"ok": True}
