"""Teste do fluxo de feedback/correção (Redis mockado, não bate no real)."""
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


@patch("app.services.feedback_service.get_redis")
def test_submit_feedback_correct(mock_get_redis):
    mock_redis = AsyncMock()
    mock_get_redis.return_value = mock_redis

    response = client.post(
        "/v1/feedback",
        json={
            "matched_title": "Wonderwall",
            "matched_artist": "Eden xo",
            "mode": "acrcloud",
            "was_correct": True,
        },
    )

    assert response.status_code == 201
    assert response.json() == {"ok": True}
    mock_redis.rpush.assert_awaited_once()
    mock_redis.hset.assert_not_awaited()  # só confirma, não é correção


@patch("app.services.feedback_service.get_redis")
def test_submit_feedback_wrong_saves_correction(mock_get_redis):
    mock_redis = AsyncMock()
    mock_get_redis.return_value = mock_redis

    response = client.post(
        "/v1/feedback",
        json={
            "matched_title": "Every Breath You Take",
            "matched_artist": "Overdriver Duo",
            "mode": "acrcloud",
            "was_correct": False,
            "corrected_title": "Every Breath You Take",
            "corrected_artist": "The Police",
        },
    )

    assert response.status_code == 201
    mock_redis.hset.assert_awaited_once()
    key_arg = mock_redis.hset.call_args.args[1]
    assert key_arg == "every breath you take::overdriver duo"
