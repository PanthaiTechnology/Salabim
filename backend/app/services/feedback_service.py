"""Memória de correções do modo Cantar.

Importante ser honesto sobre o que isso é e o que não é: isso NÃO retreina
o modelo de IA do ACRCloud (é deles, fechado, não temos acesso). O que isso
faz de verdade — e que é genuinamente útil — é guardar cada correção que um
usuário confirma ("essa música tá errada, o certo é X") e aplicar
automaticamente essa mesma correção sempre que o motor de melodia bater de
novo no mesmo resultado errado. É uma memória de erros conhecidos, não um
modelo aprendendo sozinho — mas evita repetir o mesmo engano depois que
alguém já corrigiu ele uma vez.
"""
from __future__ import annotations

import json
import time

from app.core.cache import get_redis
from app.models.schemas import FeedbackRequest

_FEEDBACK_LOG_KEY = "salabim:feedback:log"  # todo feedback recebido, pra auditoria/análise futura
_CORRECTIONS_KEY = "salabim:feedback:corrections"  # hash: "título::artista" errado -> correção


def _normalize_key(title: str, artist: str) -> str:
    return f"{title.strip().lower()}::{artist.strip().lower()}"


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
    """Se alguém já corrigiu esse exato par (título, artista) errado antes,
    devolve a correção salva. Usado no orquestrador antes de fechar um
    resultado do modo Cantar."""
    r = get_redis()
    raw = await r.hget(_CORRECTIONS_KEY, _normalize_key(title, artist))
    return json.loads(raw) if raw else None
