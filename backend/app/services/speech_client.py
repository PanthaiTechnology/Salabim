"""Transcrição de voz (Whisper, roda local — sem custo, sem chave de API).

Usado como sinal complementar à busca por melodia no modo Cantar: se a
pessoa está cantando palavras de verdade (não só "lá lá lá"), transcrever
o que foi cantado ajuda a confirmar/corrigir qual candidato do ACRCloud é o
correto — validado manualmente: cantando "Every Breath You Take" a
transcrição saiu "Every breath you take, every move you make... I'll be
watching you", quase idêntica à letra real.

Roda num thread separado (CPU-bound, bloqueante) pra não travar o event
loop do FastAPI. O modelo é carregado uma vez só e reaproveitado.
"""
from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

_model = None
_model_lock = asyncio.Lock()


async def _get_model():
    global _model
    if _model is None:
        async with _model_lock:
            if _model is None:  # checa de novo dentro do lock (outra request pode ter carregado)
                import whisper

                # "base" é um bom equilíbrio entre velocidade (roda em CPU, sem
                # GPU) e qualidade pra clipes curtos de ~15s.
                _model = await asyncio.to_thread(whisper.load_model, "base")
    return _model


async def transcribe(audio_bytes: bytes, suffix: str = ".wav") -> str:
    """Retorna o texto transcrito do áudio, em minúsculas. String vazia se
    não conseguir transcrever nada reconhecível (ex: só melodia sem letra,
    assobio, batida de ritmo)."""
    model = await _get_model()

    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        result = await asyncio.to_thread(model.transcribe, tmp_path, fp16=False)
        return (result.get("text") or "").strip().lower()
    except Exception:
        # Transcrição é um sinal complementar — se falhar, a busca por
        # melodia continua funcionando sozinha.
        return ""
    finally:
        Path(tmp_path).unlink(missing_ok=True)
