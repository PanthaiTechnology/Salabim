"""Cliente Redis para cache de resultados e rate limiting simples."""
from __future__ import annotations

import hashlib
import json

import redis.asyncio as redis

from app.config import get_settings

settings = get_settings()
_redis: redis.Redis | None = None


def get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.redis_url, decode_responses=True)
    return _redis


def audio_fingerprint_key(audio_bytes: bytes, mode: str) -> str:
    digest = hashlib.sha256(audio_bytes).hexdigest()
    return f"salabim:identify:{mode}:{digest}"


async def get_cached_json(key: str) -> dict | None:
    raw = await get_redis().get(key)
    return json.loads(raw) if raw else None


async def set_cached_json(key: str, value: dict, ttl_seconds: int = 60 * 60 * 24) -> None:
    await get_redis().set(key, json.dumps(value), ex=ttl_seconds)


async def check_rate_limit(identifier: str, max_requests: int = 30, window_seconds: int = 60) -> bool:
    """Retorna True se a requisição pode passar, False se estourou o limite."""
    key = f"salabim:ratelimit:{identifier}"
    r = get_redis()
    current = await r.incr(key)
    if current == 1:
        await r.expire(key, window_seconds)
    return current <= max_requests
