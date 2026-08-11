"""Testa a Fase 1 do sistema de correção: busca por similaridade, não só
igualdade exata de texto (ver feedback_service.py)."""
import json
from unittest.mock import AsyncMock, patch

import pytest

from app.services import feedback_service

_STORED = {
    "every breath you take (remastered 2003)::overdriver duo": json.dumps(
        {"title": "Every Breath You Take", "artist": "The Police"}
    ),
}


@pytest.mark.asyncio
@patch("app.services.feedback_service.get_redis")
async def test_exact_match_still_works(mock_get_redis):
    mock_redis = AsyncMock()
    mock_redis.hgetall.return_value = _STORED
    mock_get_redis.return_value = mock_redis

    result = await feedback_service.get_correction(
        "Every Breath You Take (Remastered 2003)", "Overdriver Duo"
    )
    assert result == {"title": "Every Breath You Take", "artist": "The Police"}


@pytest.mark.asyncio
@patch("app.services.feedback_service.get_redis")
async def test_similar_variation_matches(mock_get_redis):
    """Uma variação de sufixo/pontuação do mesmo erro (ex: "Remaster" em vez
    de "Remastered 2003") ainda deve bater na correção salva."""
    mock_redis = AsyncMock()
    mock_redis.hgetall.return_value = _STORED
    mock_get_redis.return_value = mock_redis

    result = await feedback_service.get_correction("Every Breath You Take (Remaster)", "Overdriver Duo")
    assert result == {"title": "Every Breath You Take", "artist": "The Police"}


@pytest.mark.asyncio
@patch("app.services.feedback_service.get_redis")
async def test_different_song_does_not_match(mock_get_redis):
    """Uma música genuinamente diferente não deve acionar a correção."""
    mock_redis = AsyncMock()
    mock_redis.hgetall.return_value = _STORED
    mock_get_redis.return_value = mock_redis

    result = await feedback_service.get_correction("Wonderwall", "Oasis")
    assert result is None


@pytest.mark.asyncio
@patch("app.services.feedback_service.get_redis")
async def test_no_corrections_stored_returns_none(mock_get_redis):
    mock_redis = AsyncMock()
    mock_redis.hgetall.return_value = {}
    mock_get_redis.return_value = mock_redis

    result = await feedback_service.get_correction("Qualquer Coisa", "Qualquer Artista")
    assert result is None
