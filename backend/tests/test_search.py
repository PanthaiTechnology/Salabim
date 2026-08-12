"""Testes da busca por texto (título/artista/trecho de letra via iTunes,
com tolerância a erro de digitação/palavra trocada)."""
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services import recognition_service
from app.services.itunes_client import ItunesTrackMatch


def _hit(title: str, artist: str) -> ItunesTrackMatch:
    return ItunesTrackMatch(
        title=title, artist=artist, album="Album Teste",
        artwork_url="https://example.com/art.jpg", preview_url="https://example.com/preview.m4a",
        track_view_url="https://music.apple.com/track/1",
    )


def _mock_redis() -> MagicMock:
    """Resultados de busca são cacheados (pra resolver os links de
    plataforma sob demanda depois, ver GET /v1/tracks/{id}) — mocka isso
    pra não depender de Redis de verdade nesses testes isolados."""
    redis = MagicMock()
    redis.set = AsyncMock()
    return redis


@pytest.mark.asyncio
@patch("app.services.recognition_service.get_redis", return_value=_mock_redis())
@patch("app.services.itunes_client.search_by_text", new_callable=AsyncMock)
async def test_search_returns_direct_hit_without_fallback(mock_search, _mock_redis_fn):
    mock_search.return_value = [_hit("Every Breath You Take", "The Police")]

    results = await recognition_service.search_tracks_by_text("every breath you take")

    assert len(results) == 1
    assert results[0].title == "Every Breath You Take"
    assert results[0].matched_provider == "itunes"
    mock_search.assert_awaited_once()  # não deveria precisar do fallback


@pytest.mark.asyncio
@patch("app.services.recognition_service.get_redis", return_value=_mock_redis())
@patch("app.services.itunes_client.search_by_text", new_callable=AsyncMock)
async def test_search_falls_back_when_full_phrase_finds_nothing(mock_search, _mock_redis_fn):
    # 1a chamada (frase completa) não acha nada; uma das variações do
    # fallback (removendo uma palavra) acha.
    async def side_effect(query, limit=10):
        if query == "is this the reel life is this just fantasy":
            return []
        if "reel" not in query:
            return [_hit("Bohemian Rhapsody", "Queen")]
        return []

    mock_search.side_effect = side_effect

    results = await recognition_service.search_tracks_by_text(
        "is this the reel life is this just fantasy"
    )

    assert len(results) == 1
    assert results[0].title == "Bohemian Rhapsody"


@pytest.mark.asyncio
@patch("app.services.recognition_service.get_redis", return_value=_mock_redis())
@patch("app.services.itunes_client.search_by_text", new_callable=AsyncMock)
async def test_search_corrects_typo_before_fallback(mock_search, _mock_redis_fn):
    """Erro de digitação de verdade (não uma palavra válida trocada por
    outra) deve ser corrigido antes de recorrer ao fallback mais bruto."""
    async def side_effect(query, limit=10):
        if query == "bohemian rhapsody fantasi":
            return []
        if query == "bohemian rhapsody fantasy":
            return [_hit("Bohemian Rhapsody", "Queen")]
        return []

    mock_search.side_effect = side_effect

    results = await recognition_service.search_tracks_by_text("bohemian rhapsody fantasi")

    assert len(results) == 1
    assert results[0].title == "Bohemian Rhapsody"


@pytest.mark.asyncio
@patch("app.services.itunes_client.search_by_text", new_callable=AsyncMock, return_value=[])
async def test_search_no_results_anywhere_returns_empty(mock_search):
    results = await recognition_service.search_tracks_by_text("asdkjaslkdjaslkdj completamente aleatorio")
    assert results == []


@pytest.mark.asyncio
@patch("app.services.recognition_service.get_redis", return_value=_mock_redis())
@patch("app.services.itunes_client.search_by_text", new_callable=AsyncMock)
async def test_search_deduplicates_repeated_tracks(mock_search, _mock_redis_fn):
    mock_search.return_value = [
        _hit("Wonderwall", "Oasis"),
        _hit("Wonderwall", "Oasis"),
    ]

    results = await recognition_service.search_tracks_by_text("wonderwall")

    assert len(results) == 1


@pytest.mark.asyncio
@patch("app.services.recognition_service.odesli_client.resolve_platform_links", new_callable=AsyncMock)
async def test_get_track_details_resolves_links_lazily(mock_resolve):
    """GET /v1/tracks/{id} é onde os links de plataforma são resolvidos de
    verdade pra resultados vindos da busca por texto (ver
    search_tracks_by_text — não resolve mais por item da lista, só sob
    demanda aqui, pra não estourar a cota do Odesli numa lista inteira)."""
    from app.models.schemas import PlatformLink

    mock_resolve.return_value = [PlatformLink(platform="spotify", url="https://open.spotify.com/track/1")]

    redis = _mock_redis()
    import json as json_module

    cached_payload = json_module.dumps({
        "track": {
            "id": "abc123",
            "title": "Some Song",
            "artist": "Some Artist",
            "matched_provider": "itunes",
            "platform_links": [],
        },
        "source_url": "https://music.apple.com/track/1",
        "links_resolved": False,
    })
    redis.get = AsyncMock(return_value=cached_payload)

    with patch("app.services.recognition_service.get_redis", return_value=redis):
        track = await recognition_service.get_track_details("abc123")

    assert track is not None
    assert len(track.platform_links) == 1
    assert track.platform_links[0].platform == "spotify"
    mock_resolve.assert_awaited_once()


@pytest.mark.asyncio
async def test_get_track_details_returns_none_when_not_cached():
    redis = _mock_redis()
    redis.get = AsyncMock(return_value=None)

    with patch("app.services.recognition_service.get_redis", return_value=redis):
        track = await recognition_service.get_track_details("nao-existe")

    assert track is None
