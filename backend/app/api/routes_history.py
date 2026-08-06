"""Histórico e favoritos do usuário autenticado."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db
from app.models import db_models
from app.models.schemas import HistoryItem

router = APIRouter(prefix="/v1", tags=["history"])


@router.get("/history", response_model=list[HistoryItem])
async def get_history(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[HistoryItem]:
    stmt = (
        select(db_models.SearchHistory, db_models.TrackCache)
        .join(db_models.TrackCache, db_models.SearchHistory.track_id == db_models.TrackCache.id)
        .where(db_models.SearchHistory.user_id == user_id)
        .order_by(db_models.SearchHistory.searched_at.desc())
        .limit(100)
    )
    rows = (await db.execute(stmt)).all()

    items: list[HistoryItem] = []
    for history_row, track_row in rows:
        items.append(
            HistoryItem(
                mode=history_row.mode,
                searched_at=history_row.searched_at.isoformat(),
                track={
                    "id": track_row.id,
                    "title": track_row.title,
                    "artist": track_row.artist,
                    "album": track_row.album,
                    "artwork_url": track_row.artwork_url,
                    "isrc": track_row.isrc,
                    "preview_url": track_row.preview_url,
                    "matched_provider": track_row.matched_provider,
                    "match_confidence": track_row.match_confidence,
                    "platform_links": [],
                },
            )
        )
    return items


@router.post("/favorites/{track_id}", status_code=201)
async def add_favorite(
    track_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict:
    favorite = db_models.Favorite(user_id=user_id, track_id=track_id, created_at=datetime.now(timezone.utc))
    db.add(favorite)
    await db.commit()
    return {"ok": True}
