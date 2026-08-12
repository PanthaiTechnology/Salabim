"""Teste do fluxo /v1/identify com os provedores mockados (não bate na API real)."""
import io
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.main import app
from app.services.audd_client import AudDResult

client = TestClient(app)


@patch("app.services.recognition_service._save_track_cache", new_callable=AsyncMock)
@patch("app.api.routes_identify.check_rate_limit", new_callable=AsyncMock, return_value=True)
@patch("app.services.recognition_service.get_cached_json", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.set_cached_json", new_callable=AsyncMock)
@patch("app.services.recognition_service.spotify_client.search_track_url", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.odesli_client.resolve_platform_links", new_callable=AsyncMock, return_value=[])
@patch("app.services.recognition_service.itunes_client.search_by_title_artist", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.audd_client.identify_audio", new_callable=AsyncMock)
def test_identify_listen_mode_found(
    mock_audd, _mock_itunes, _mock_links, _mock_spotify, _mock_set_cache, _mock_get_cache, _mock_rate_limit,
    _mock_save_cache,
):
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


@patch("app.services.recognition_service._save_track_cache", new_callable=AsyncMock)
@patch("app.api.routes_identify.check_rate_limit", new_callable=AsyncMock, return_value=True)
@patch("app.services.recognition_service.get_cached_json", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.set_cached_json", new_callable=AsyncMock)
@patch("app.services.recognition_service.spotify_client.search_track_url", new_callable=AsyncMock, return_value=None)
@patch("app.services.recognition_service.odesli_client.resolve_platform_links", new_callable=AsyncMock, return_value=[])
@patch("app.services.recognition_service.itunes_client.search_by_title_artist", new_callable=AsyncMock)
@patch("app.services.recognition_service.audd_client.identify_audio", new_callable=AsyncMock)
def test_identify_listen_mode_enriches_missing_preview_from_itunes(
    mock_audd, mock_itunes, _mock_links, _mock_spotify, _mock_set_cache, _mock_get_cache, _mock_rate_limit,
    _mock_save_cache,
):
    """Bug real encontrado em produção: a AudD às vezes identifica a música
    certa mas não traz preview/capa junto (comum em faixas menos conhecidas)
    — o modo Ouvir precisa buscar isso no iTunes como reforço, igual o modo
    Cantar já fazia (ver _enrich_with_itunes em recognition_service.py)."""
    from app.services.itunes_client import ItunesTrackMatch

    mock_audd.return_value = AudDResult(
        title="Obscure Song", artist="Obscure Artist", album=None,
        isrc="US9876543210", artwork_url=None, preview_url=None, release_date=None,
    )
    mock_itunes.return_value = ItunesTrackMatch(
        title="Obscure Song", artist="Obscure Artist", album="Obscure Album",
        artwork_url="https://example.com/art.jpg", preview_url="https://example.com/preview.m4a",
        track_view_url="https://music.apple.com/track/1",
    )

    fake_audio = io.BytesIO(b"fake-audio-bytes")
    response = client.post(
        "/v1/identify",
        data={"mode": "listen"},
        files={"file": ("clip.m4a", fake_audio, "audio/m4a")},
    )

    assert response.status_code == 200
    track = response.json()["track"]
    assert track["preview_url"] == "https://example.com/preview.m4a"
    assert track["artwork_url"] == "https://example.com/art.jpg"
    mock_itunes.assert_awaited_once_with("Obscure Song", "Obscure Artist")


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
