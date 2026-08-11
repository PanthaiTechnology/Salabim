"""Memória de correções do modo Cantar.

Importante ser honesto sobre o que isso é e o que não é: isso NÃO retreina
o modelo de IA do ACRCloud (é deles, fechado, não temos acesso). O que isso
faz de verdade — e que é genuinamente útil — é guardar cada correção que um
usuário confirma ("essa música tá errada, o certo é X") e aplicar
automaticamente essa mesma correção sempre que o motor de melodia bater de
novo num resultado errado PARECIDO. É uma memória de erros conhecidos, não
um modelo aprendendo sozinho — mas evita repetir o mesmo engano depois que
alguém já corrigiu ele uma vez.

Fase 1 (este módulo): a busca da correção é por SIMILARIDADE de texto, não
igualdade exata — assim uma correção salva pra "Every Breath You Take
(Remastered 2003)" também vale se o próximo erro vier como "Every Breath
You Take (Remaster)" ou variações parecidas de pontuação/sufixo, sem
precisar corrigir de novo pra cada pequena variação de nome.

Fase 2 (roadmap, ainda não implementada — precisa de volume real de
correções pra valer a pena): treinar um classificador leve (ex: regressão
logística) usando como features os sinais que já calculamos por busca
(score de melodia, similaridade da transcrição com o preview oficial,
quantos candidatos convergem pro mesmo título, se passou pela troca
cover->original) pra aprender os pesos de decisão sozinho, em vez dos pesos
fixos "no chute" (0.6/0.4) que o orquestrador usa hoje. Só compensa
implementar depois que o app tiver uso real suficiente pra gerar um dataset
de correções minimamente representativo (algumas centenas de exemplos,
não só os testes manuais que fizemos até agora).
"""
from __future__ import annotations

import difflib
import json
import time

from app.core.cache import get_redis
from app.models.schemas import FeedbackRequest

_FEEDBACK_LOG_KEY = "salabim:feedback:log"  # todo feedback recebido, pra auditoria/análise futura
_CORRECTIONS_KEY = "salabim:feedback:corrections"  # hash: "título::artista" errado -> correção

# Quão parecido precisa ser pra considerar "é o mesmo erro de antes". Testado
# manualmente: 0.82 pega variações de sufixo/pontuação (remaster, feat.,
# maiúsculas) sem confundir músicas genuinamente diferentes.
_MATCH_THRESHOLD = 0.82


def _normalize_key(title: str, artist: str) -> str:
    return f"{title.strip().lower()}::{artist.strip().lower()}"


def _similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a.strip().lower(), b.strip().lower()).ratio()


async def save_feedback(payload: FeedbackRequest) -> None:
    r = get_redis()

    entry = payload.model_dump()
    entry["received_at"] = time.time()
    await r.rpush(_FEEDBACK_LOG_KEY, json.dumps(entry))

    # Só vira correção automática pro modo Cantar — é onde a ambiguidade de
    # melodia realmente causa esse tipo de erro. Fingerprint de áudio normal
    # (modo Ouvir) não erra a ponto de precisar disso.
    if not payload.was_correct and payload.corrected_title and payload.mode == "acrcloud":
        key = _normalize_key(payload.matched_title, payload.matched_artist)
        correction = {"title": payload.corrected_title, "artist": payload.corrected_artist or ""}
        await r.hset(_CORRECTIONS_KEY, key, json.dumps(correction))


async def get_correction(title: str, artist: str) -> dict | None:
    """Encontra uma correção salva pra um (título, artista) parecido —
    não exige igualdade exata de texto (ver docstring do módulo, Fase 1).
    Usado no orquestrador antes de fechar um resultado do modo Cantar.
    """
    r = get_redis()
    stored = await r.hgetall(_CORRECTIONS_KEY)
    if not stored:
        return None

    best_value: str | None = None
    best_score = 0.0

    for stored_key, raw_value in stored.items():
        if "::" not in stored_key:
            continue
        stored_title, _, stored_artist = stored_key.partition("::")

        title_score = _similarity(title, stored_title)
        # Sem artista informado de nenhum dos dois lados, não penaliza —
        # deixa o título carregar a decisão sozinho.
        artist_score = _similarity(artist, stored_artist) if (artist and stored_artist) else 1.0
        combined = 0.7 * title_score + 0.3 * artist_score

        if combined > best_score:
            best_score = combined
            best_value = raw_value

    if best_value is not None and best_score >= _MATCH_THRESHOLD:
        return json.loads(best_value)
    return None
