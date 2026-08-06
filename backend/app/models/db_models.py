"""Modelos SQLAlchemy (persistência: usuários, histórico, favoritos)."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, Float
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


def _uuid() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    history: Mapped[list["SearchHistory"]] = relationship(back_populates="user")


class TrackCache(Base):
    """Cache local de faixas já identificadas, para não bater no provedor de novo."""

    __tablename__ = "tracks_cache"

    id: Mapped[str] = mapped_column(String, primary_key=True)  # hash estável (isrc ou provider_id)
    title: Mapped[str] = mapped_column(String)
    artist: Mapped[str] = mapped_column(String)
    album: Mapped[str | None] = mapped_column(String, nullable=True)
    artwork_url: Mapped[str | None] = mapped_column(String, nullable=True)
    isrc: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    preview_url: Mapped[str | None] = mapped_column(String, nullable=True)
    matched_provider: Mapped[str] = mapped_column(String)
    match_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    platform_links_json: Mapped[str] = mapped_column(String, default="[]")
    cached_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))


class SearchHistory(Base):
    __tablename__ = "search_history"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    track_id: Mapped[str] = mapped_column(ForeignKey("tracks_cache.id"))
    mode: Mapped[str] = mapped_column(String)  # listen | hum | lyrics | description
    searched_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    user: Mapped["User"] = relationship(back_populates="history")


class Favorite(Base):
    __tablename__ = "favorites"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    track_id: Mapped[str] = mapped_column(ForeignKey("tracks_cache.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
