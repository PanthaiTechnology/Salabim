"""POST /v1/search/text — busca por trecho de letra ou descrição livre da música."""
from __future__ import annotations

from fastapi import APIRouter

from app.models.schemas import TextSearchKind, TextSearchRequest, TextSearchResponse
from app.services.recognition_service import search_by_description, search_by_lyrics

router = APIRouter(prefix="/v1", tags=["search"])


@router.post("/search/text", response_model=TextSearchResponse)
async def search_text(payload: TextSearchRequest) -> TextSearchResponse:
    if payload.kind == TextSearchKind.lyrics:
        results = await search_by_lyrics(payload.query)
    else:
        results = await search_by_description(payload.query)
    return TextSearchResponse(results=results)
