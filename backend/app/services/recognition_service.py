"""Orquestrador central: decide qual provedor chamar, monta o objeto Track final
com links cross-platform, e cuida do cache. Este módulo é o coração proprietário
do Salabim — a "cola" entre Shazam-style e Hum-to-Search-style em um único produto.
"""
from __future__ import annotations

import asyncio
import hashlib
import re

import httpx

from app.core.cache import audio_fingerprint_key, get_cached_json, set_cached_json
from app.models.schemas import ListenMode, PlatformLink, Track
from app.services import (
    acrcloud_client,
    audd_client,
    feedback_service,
    itunes_client,
    musixmatch_client,
    odesli_client,
    speech_client,
)

# Palavras comuns demais em título de música pra servirem de sinal — em
# português e inglês, os dois idiomas mais prováveis do usuário/catálogo.
_STOPWORDS = {
    "a", "o", "as", "os", "de", "da", "do", "das", "dos", "e", "é", "em", "um", "uma",
    "the", "of", "an", "in", "on", "to", "and", "my", "you", "your", "me", "is", "it",
}


def _stable_track_id(isrc: str | None, title: str, artist: str) -> str:
    basis = isrc or f"{title.lower()}::{artist.lower()}"
    return hashlib.sha1(basis.encode()).hexdigest()[:16]


def _text_similarity(a: str, b: str) -> float:
    """Similaridade de Jaccard entre os conjuntos de palavras de dois textos
    (ignorando stopwords) — usado pra comparar a transcrição do que o
    usuário cantou com a transcrição do preview oficial de um candidato.
    """
    words_a = {w for w in re.findall(r"[\w']+", a.lower()) if w not in _STOPWORDS and len(w) > 2}
    words_b = {w for w in re.findall(r"[\w']+", b.lower()) if w not in _STOPWORDS and len(w) > 2}
    if not words_a or not words_b:
        return 0.0
    return len(words_a & words_b) / len(words_a | words_b)


async def _transcribe_preview(preview_url: str) -> str:
    """Baixa o preview oficial de 30s de uma faixa e transcreve — usado como
    "letra de referência" de um candidato, sem depender de nenhum banco de
    letras externo (que sempre tem buracos pra faixas menos conhecidas,
    mesmo licenciadas — testado: nem busca na web achava a letra de uma
    faixa disponível no Spotify). Falha silenciosa: sem preview, sem sinal
    extra, mas a busca por melodia continua funcionando sozinha."""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(preview_url)
            response.raise_for_status()
            audio_bytes = response.content
        # "tiny" aqui: isso é só validação/desempate, não o sinal principal —
        # bem mais rápido que "base", que é o que sobrecarregava a latência
        # total (cada transcrição extra levava vários segundos).
        return await speech_client.transcribe(audio_bytes, suffix=".m4a", model_size="tiny")
    except Exception:
        return ""


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


def _normalize_name(name: str) -> str:
    return name.lower().replace("the ", "").strip()


async def _prefer_canonical_version(track: Track) -> Track:
    """Busca por melodia (ACRCloud) às vezes acerta a MÚSICA mas bate numa
    gravação obscura/cover em vez do original (validado com "Every Breath You
    Take": o catálogo tinha 3 gravações diferentes da mesma música entre os
    candidatos, e o cover tinha score mais alto que o original do The Police).

    Detecta isso comparando com quem aparece como resultado mais relevante do
    iTunes pra esse TÍTULO sozinho (sem o artista que o ACRCloud achou) — se
    for um artista diferente, troca pra essa versão mais popular/mainstream.
    Só usado no modo Cantar; fingerprint de áudio (Ouvir/AudD) já casa a
    gravação exata, não tem essa ambiguidade.
    """
    canonical = await itunes_client.search_by_title_only(track.title)
    if canonical is None:
        return track

    if _normalize_name(canonical.artist) == _normalize_name(track.artist):
        return track  # já é a versão canônica, nada a trocar

    # Guarda contra o iTunes ter achado um título só remotamente parecido
    # (busca por texto livre pode ser imprecisa) — exige que um título
    # contenha o outro depois de normalizado.
    a, b = track.title.lower().strip(), canonical.title.lower().strip()
    if a not in b and b not in a:
        return track

    track.title = canonical.title
    track.artist = canonical.artist
    track.album = canonical.album
    track.artwork_url = canonical.artwork_url
    track.preview_url = canonical.preview_url
    track.isrc = None  # não temos o ISRC dessa versão específica
    track.id = _stable_track_id(track.isrc, track.title, track.artist)  # recalcula: título/artista mudaram
    if canonical.track_view_url:
        track.platform_links = await odesli_client.resolve_platform_links(source_url=canonical.track_view_url)
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
        # Melodia (ACRCloud) e letra transcrita da voz (Whisper, local) rodam
        # em paralelo — são sinais independentes que, combinados, aproximam
        # bastante do que um humano faz ao reconhecer uma música cantada:
        # "essa melodia soa parecida" + "essas palavras batem".
        candidates, transcription = await asyncio.gather(
            acrcloud_client.identify_humming_candidates(audio_bytes),
            speech_client.transcribe(audio_bytes),
        )
        if not candidates:
            return None

        if not transcription:
            # Sem palavras reconhecíveis (cantarolou/assobiou/tocou sem
            # letra) — não tem o que validar por texto, fica só a melodia.
            result = max(candidates, key=lambda c: c.score)
        else:
            # Só vale buscar+transcrever preview dos candidatos mais
            # prováveis pela melodia (limita custo e latência).
            top_candidates = sorted(candidates, key=lambda c: c.score, reverse=True)[:2]

            async def _score_candidate(c: acrcloud_client.ACRCloudResult):
                itunes_hit = await itunes_client.search_by_title_artist(c.title, c.artist)
                if itunes_hit is None or not itunes_hit.preview_url:
                    return c, 0.0
                preview_transcription = await _transcribe_preview(itunes_hit.preview_url)
                return c, _text_similarity(transcription, preview_transcription)

            scored = await asyncio.gather(*(_score_candidate(c) for c in top_candidates))
            # Melodia continua o sinal principal (é o que sempre temos);
            # letra reforça/corrige quando a comparação com o preview oficial
            # do candidato bate com o que a pessoa realmente cantou.
            result, _ = max(scored, key=lambda pair: 0.5 * pair[0].score + 0.5 * pair[1])

        # Alguém já corrigiu esse exato resultado errado antes? Aplica a
        # correção direto, sem precisar rodar o resto do reranking de novo —
        # é a memória de correções (ver feedback_service.py).
        correction = await feedback_service.get_correction(result.title, result.artist)
        if correction:
            result.title = correction["title"]
            result.artist = correction["artist"] or result.artist
            result.isrc = None  # não temos o ISRC da correção manual

        track = Track(
            id=_stable_track_id(result.isrc, result.title, result.artist),
            title=result.title,
            artist=result.artist,
            album=result.album,
            isrc=result.isrc,
            matched_provider="acrcloud",
            match_confidence=result.score,
        )
        track = await _prefer_canonical_version(track)

    track = await _enrich_with_itunes(track)
    if not track.platform_links:
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
