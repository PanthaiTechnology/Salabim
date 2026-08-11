"""Orquestrador central: decide qual provedor chamar, monta o objeto Track final
com links cross-platform, e cuida do cache. Este módulo é o coração proprietário
do Salabim — a "cola" entre Shazam-style e Hum-to-Search-style em um único produto.
"""
from __future__ import annotations

import hashlib

from app.core.cache import audio_fingerprint_key, get_cached_json, set_cached_json
from app.models.schemas import ListenMode, PlatformLink, Track
from app.services import acrcloud_client, audd_client, itunes_client, musixmatch_client, odesli_client


def _stable_track_id(isrc: str | None, title: str, artist: str) -> str:
    basis = isrc or f"{title.lower()}::{artist.lower()}"
    return hashlib.sha1(basis.encode()).hexdigest()[:16]


async def _enrich_with_itunes(track: Track) -> Track:
    """Preenche capa e preview quando o provedor que fez o match (ACRCloud,
    Musixmatch) não retorna isso — só a AudD já vem com essa info de graça.
    Sem isso, a tela de resultado do modo Cantar/busca por letra ficava sem
    o botão de preview que o modo Ouvir sempre teve.
    """
    if track.artwork_url and track.preview_url:
        return track

    result = await itunes_client.search_by_title_artist(track.title, track.artist)
    if result is None:
        return track

    if not track.artwork_url:
        track.artwork_url = result.artwork_url
    if not track.preview_url:
        track.preview_url = result.preview_url
    if not track.album:
        track.album = result.album
    return track


async def identify_from_audio(audio_bytes: bytes, mode: ListenMode) -> Track | None:
    cache_key = audio_fingerprint_key(audio_bytes, mode.value)
    cached = await get_cached_json(cache_key)
    if cached:
        return Track.model_validate(cached)

    if mode == ListenMode.listen:
        result = await audd_client.identify_audio(audio_bytes)
        if not result:
            return None
        track = Track(
            id=_stable_track_id(result.isrc, result.title, result.artist),
            title=result.title,
            artist=result.artist,
            album=result.album,
            artwork_url=result.artwork_url,
            isrc=result.isrc,
            release_date=result.release_date,
            preview_url=result.preview_url,
            matched_provider="audd",
            match_confidence=1.0,
        )
        track.platform_links = await odesli_client.resolve_platform_links(
            isrc=track.isrc, source_url=result.source_url
        )
        await set_cached_json(cache_key, track.model_dump())
        return track
    else:  # hum
        result = await acrcloud_client.identify_humming(audio_bytes)
        if not result:
            return None
        track = Track(
            id=_stable_track_id(result.isrc, result.title, result.artist),
            title=result.title,
            artist=result.artist,
            album=result.album,
            isrc=result.isrc,
            matched_provider="acrcloud",
            match_confidence=result.score,
        )

    track = await _enrich_with_itunes(track)
    track.platform_links = await odesli_client.resolve_platform_links(isrc=track.isrc)
    await set_cached_json(cache_key, track.model_dump())
    return track


async def search_by_lyrics(query: str, limit: int = 10) -> list[Track]:
    hits = await musixmatch_client.search_by_lyrics(query, limit=limit)
    tracks: list[Track] = []
    for hit in hits:
        track = Track(
            id=_stable_track_id(hit.isrc, hit.title, hit.artist),
            title=hit.title,
            artist=hit.artist,
            album=hit.album,
            isrc=hit.isrc,
            matched_provider="musixmatch",
        )
        track = await _enrich_with_itunes(track)
        track.platform_links = await odesli_client.resolve_platform_links(isrc=track.isrc)
        tracks.append(track)
    return tracks


async def search_by_description(query: str, limit: int = 10) -> list[Track]:
    """Fase 2 (ver ARCHITECTURE.md §7): busca semântica própria por descrição livre.
    Placeholder hoje — cai de volta para busca por texto na Musixmatch como aproximação
    até o índice de embeddings próprio existir.
    """
    return await search_by_lyrics(query, limit=limit)
