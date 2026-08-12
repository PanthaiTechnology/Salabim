"""Orquestrador central: decide qual provedor chamar, monta o objeto Track final
com links cross-platform, e cuida do cache. Este módulo é o coração proprietário
do Salabim — a "cola" entre Shazam-style e Hum-to-Search-style em um único produto.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import re

import httpx

from app.core.cache import audio_fingerprint_key, get_cached_json, get_redis, set_cached_json
from app.models.schemas import ListenMode, PlatformLink, Track
from app.services import (
    acrcloud_client,
    audd_client,
    feedback_service,
    itunes_client,
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


_TRACK_CACHE_TTL = 60 * 60 * 6  # 6h — tempo de sobra pra navegar a busca e abrir um resultado


async def _save_track_cache(track: Track, *, source_url: str | None, links_resolved: bool) -> None:
    """Guarda a faixa pelo ID pra `get_track_details` conseguir achar depois
    (`source_url` fica salvo só pra permitir resolver os links de plataforma
    sob demanda mais tarde, quando ainda não foram resolvidos agora)."""
    r = get_redis()
    payload = {"track": track.model_dump(), "source_url": source_url, "links_resolved": links_resolved}
    await r.set(f"salabim:track:{track.id}", json.dumps(payload), ex=_TRACK_CACHE_TTL)


async def get_track_details(track_id: str) -> Track | None:
    """Busca uma faixa pelo ID e resolve os links de plataforma agora, se
    ainda não tiverem sido resolvidos — é assim que a busca por texto evita
    gastar a cota do Odesli em bloco pra cada resultado da lista (só resolve
    quando o usuário realmente abre uma faixa específica). Ver
    odesli_client.py para o motivo dessa cota importar tanto."""
    r = get_redis()
    raw = await r.get(f"salabim:track:{track_id}")
    if raw is None:
        return None

    cached = json.loads(raw)
    track = Track.model_validate(cached["track"])

    if cached.get("links_resolved"):
        return track

    source_url = cached.get("source_url")
    if source_url or track.isrc:
        track.platform_links = await odesli_client.resolve_platform_links(isrc=track.isrc, source_url=source_url)
    await _save_track_cache(track, source_url=source_url, links_resolved=True)
    return track


_spellcheckers: dict[str, object] = {}


def _get_spellchecker(lang: str):
    if lang not in _spellcheckers:
        from spellchecker import SpellChecker

        _spellcheckers[lang] = SpellChecker(language=lang)
    return _spellcheckers[lang]


def _autocorrect_query(query: str, lang: str) -> str | None:
    """Corrige palavras com erro de digitação na consulta (dicionário local,
    sem chave/custo) — cobre erro de ortografia de verdade (ex: "fantasi" ->
    "fantasy", "pransha" -> "prancha"). Retorna None se nada precisou mudar.

    Limite honesto: isso NÃO corrige uma palavra escrita certa mas errada
    pro contexto (ex: alguém escreve "reel" quando a letra real é "real" —
    ambas são palavras válidas, o corretor ortográfico não tem como saber
    qual é a certa sem uma base de letras completa pra comparar contra, que
    esbarra no mesmo problema de licenciamento discutido em ARCHITECTURE.md
    §4.2 — "mondegreen"/palavra parecida trocada continua sendo um limite
    real, não só de digitação).
    """
    checker = _get_spellchecker(lang)
    words = query.split()
    corrected = []
    changed = False

    for word in words:
        clean = re.sub(r"[^\w]", "", word.lower())
        if not clean or clean in checker:
            corrected.append(word)
            continue
        suggestion = checker.correction(clean)
        if suggestion and suggestion != clean:
            corrected.append(suggestion)
            changed = True
        else:
            corrected.append(word)

    return " ".join(corrected) if changed else None


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
        await _save_track_cache(track, source_url=result.source_url, links_resolved=True)
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
    await _save_track_cache(track, source_url=None, links_resolved=True)
    return track


async def _search_with_word_dropout(query: str, limit: int) -> list[itunes_client.ItunesTrackMatch]:
    """Quando a frase completa não acha nada, tenta variações removendo uma
    palavra de cada vez — cobre o caso de erro de digitação ou palavra
    trocada/mal-lembrada ("sempre cantei assim") sem precisar de corretor
    ortográfico: se o resto da frase ainda estiver certo, a busca encontra
    mesmo com uma palavra errada no meio.

    Roda as variações em paralelo e "vota": faixas que aparecem em mais de
    uma variação sobem no ranking — sinal de que a palavra removida não era
    a peça essencial pra identificar a música.
    """
    words = query.split()
    if len(words) < 3:
        return []

    # No máximo 8 variações — o suficiente pra pegar a maioria dos casos
    # sem gerar chamadas demais numa frase muito longa.
    variants = [" ".join(words[:i] + words[i + 1 :]) for i in range(min(len(words), 8))]
    results = await asyncio.gather(*(itunes_client.search_by_text(v, limit=limit) for v in variants))

    counts: dict[tuple[str, str], int] = {}
    by_key: dict[tuple[str, str], itunes_client.ItunesTrackMatch] = {}
    for hits in results:
        for hit in hits[:3]:  # só os top resultados de cada tentativa contam voto
            key = (hit.title.lower(), hit.artist.lower())
            counts[key] = counts.get(key, 0) + 1
            by_key[key] = hit

    ranked = sorted(by_key.items(), key=lambda kv: counts[kv[0]], reverse=True)
    return [hit for _, hit in ranked[:limit]]


async def search_tracks_by_text(query: str, limit: int = 10) -> list[Track]:
    """Busca por texto: nome da música, nome do artista, OU qualquer trecho
    da letra — tudo pelo mesmo campo, via iTunes Search (gratuito, sem
    chave; Musixmatch não tem mais plano gratuito pra Lyrics API, por isso
    não é mais o caminho principal — ver ARCHITECTURE.md §5).
    """
    hits = await itunes_client.search_by_text(query, limit=limit)

    if not hits:
        # Tenta corrigir erro de digitação (português e inglês, os idiomas
        # mais prováveis) antes de recorrer ao fallback mais bruto.
        for lang in ("pt", "en"):
            corrected = _autocorrect_query(query, lang)
            if corrected:
                hits = await itunes_client.search_by_text(corrected, limit=limit)
                if hits:
                    break

    if not hits:
        hits = await _search_with_word_dropout(query, limit)

    tracks: list[Track] = []
    seen: set[tuple[str, str]] = set()
    for hit in hits:
        key = (hit.title.lower(), hit.artist.lower())
        if key in seen:
            continue
        seen.add(key)

        track = Track(
            id=_stable_track_id(None, hit.title, hit.artist),
            title=hit.title,
            artist=hit.artist,
            album=hit.album,
            artwork_url=hit.artwork_url,
            preview_url=hit.preview_url,
            matched_provider="itunes",
        )
        # Não resolve os links de plataforma aqui: uma busca pode trazer
        # até `limit` resultados, e resolver pra todos de uma vez foi o que
        # estourou a cota do Odesli e derrubou os links de TODAS as buscas
        # (inclusive Ouvir/Cantar) até resetar — bug real, já corrigido. Só
        # resolve quando o app abre um resultado específico (GET
        # /v1/tracks/{id} -> get_track_details), usando o cache abaixo.
        await _save_track_cache(track, source_url=hit.track_view_url, links_resolved=False)
        tracks.append(track)
    return tracks


async def search_by_lyrics(query: str, limit: int = 10) -> list[Track]:
    return await search_tracks_by_text(query, limit=limit)


async def search_by_description(query: str, limit: int = 10) -> list[Track]:
    """Descrição livre da música (ex: "aquela música do comercial dos anos
    90"). Busca semântica de verdade (embeddings) é Fase 2 — ver
    ARCHITECTURE.md §7. Hoje cai no mesmo caminho de busca por texto: se a
    descrição incluir um pedaço reconhecível do título/artista/letra, ainda
    encontra; descrições puramente conceituais (sem nenhuma palavra-chave
    da música em si) não têm como funcionar sem o índice semântico.
    """
    return await search_tracks_by_text(query, limit=limit)
