"""Teste do fluxo /v1/identify com os provedores mockados (não bate na API real)."""
import io
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.audd_client import AudDResult

client = TestClient(app)


@patch("app.api.routes_identify.check_rate_limit", new_callable=AsyncMock, return_value=True)
@patch("app.services.recognition_service.get_cached_json", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.set_cached_json", new_callable=AsyncMock)
@patch("app.services.recognition_service.odesli_client.resolve_platform_links", new_callable=AsyncMock, return_value=[])
@patch("app.services.recognition_service.audd_client.identify_audio", new_callable=AsyncMock)
def test_identify_listen_mode_found(mock_audd, _mock_links, _mock_set_cache, _mock_get_cache, _mock_rate_limit):
    mock_audd.return_value = AudDResult(
        title="Test Song", artist="Test Artist", album="Test Album",
        isrc="US1234567890", artwork_url=None, preview_url=None, release_date="2020-01-01",
    )

    fake_audio = io.BytesIO(b"fake-audio-bytes")
    response = client.post(
        "/v1/identify",
        data={"mode": "listen"},
        files={"file": ("clip.m4a", fake_audio, "audio/m4a")},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["found"] is True
    assert body["track"]["title"] == "Test Song"
    assert body["track"]["matched_provider"] == "audd"


@patch("app.api.routes_identify.check_rate_limit", new_callable=AsyncMock, return_value=True)
@patch("app.services.recognition_service.get_cached_json", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.audd_client.identify_audio", new_callable=AsyncMock, return_value=None)
def test_identify_not_found(_mock_audd, _mock_get_cache, _mock_rate_limit):
    fake_audio = io.BytesIO(b"fake-audio-bytes")
    response = client.post(
        "/v1/identify",
        data={"mode": "listen"},
        files={"file": ("clip.m4a", fake_audio, "audio/m4a")},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["found"] is False
