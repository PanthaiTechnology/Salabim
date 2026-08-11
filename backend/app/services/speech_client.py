"""Transcrição de voz (Whisper, roda local — sem custo, sem chave de API).

Usado como sinal complementar à busca por melodia no modo Cantar: se a
pessoa está cantando palavras de verdade (não só "lá lá lá"), transcrever
o que foi cantado ajuda a confirmar/corrigir qual candidato do ACRCloud é o
correto — validado manualmente: cantando "Every Breath You Take" a
transcrição saiu "Every breath you take, every move you make... I'll be
watching you", quase idêntica à letra real.

Roda num thread separado (CPU-bound, bloqueante) pra não travar o event
loop do FastAPI. Os modelos são carregados uma vez só e reaproveitados.

Dois tamanhos de modelo: "base" pra transcrever o que o usuário cantou (é o
sinal principal, vale gastar mais tempo com melhor qualidade), "tiny" pra
transcrever os previews dos candidatos (é só validação/desempate — mais
rápido, e não precisa de tanta precisão pra comparar palavras-chave).

Importante: cada modelo só processa UMA transcrição por vez (lock dedicado
por tamanho). O código que compara candidatos roda 2 transcrições "tiny" em
paralelo via asyncio.gather — sem esse lock, isso significa duas threads
chamando model.transcribe() ao mesmo tempo na MESMA instância do modelo, o
que derrubou o servidor sem nenhum traceback (crash nativo do PyTorch, não
um erro Python normal) — Whisper/PyTorch não é garantidamente seguro pra
inferência concorrente numa única instância de modelo.
"""
from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

_models: dict[str, object] = {}
_load_lock = asyncio.Lock()
_inference_locks: dict[str, asyncio.Lock] = {}


async def _get_model(size: str):
    if size not in _models:
        async with _load_lock:
            if size not in _models:  # checa de novo dentro do lock
                import whisper

                _models[size] = await asyncio.to_thread(whisper.load_model, size)
                _inference_locks[size] = asyncio.Lock()
    return _models[size]


async def transcribe(audio_bytes: bytes, suffix: str = ".wav", model_size: str = "base") -> str:
    """Retorna o texto transcrito do áudio, em minúsculas. String vazia se
    não conseguir transcrever nada reconhecível (ex: só melodia sem letra,
    assobio, batida de ritmo)."""
    model = await _get_model(model_size)

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        # Serializa por tamanho de modelo — ver aviso no docstring do módulo.
        async with _inference_locks[model_size]:
            result = await asyncio.to_thread(model.transcribe, tmp_path, fp16=False)
        return (result.get("text") or "").strip().lower()
    except Exception:
        # Transcrição é um sinal complementar — se falhar, a busca por
        # melodia continua funcionando sozinha.
        return ""
    finally:
        Path(tmp_path).unlink(missing_ok=True)
