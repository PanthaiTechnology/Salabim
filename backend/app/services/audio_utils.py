"""Pré-processamento de áudio antes de mandar pro provedor de reconhecimento.

Primeiro (e único, por enquanto) tratamento: normalização de ganho por pico
— ver `normalize_gain` abaixo. Roda em thread separada (pydub/ffmpeg são
bloqueantes/CPU-bound) pra não travar o event loop do FastAPI, no mesmo
padrão já usado em speech_client.py pro Whisper.
"""
from __future__ import annotations

import asyncio
import io
import logging

from pydub import AudioSegment
from pydub.effects import normalize as _peak_normalize

logger = logging.getLogger(__name__)


def _normalize_gain_sync(audio_bytes: bytes, input_format: str) -> bytes:
    audio = AudioSegment.from_file(io.BytesIO(audio_bytes), format=input_format)
    normalized = _peak_normalize(audio)  # sobe o pico até ~0dBFS (headroom padrão de 0.1dB)
    buf = io.BytesIO()
    normalized.export(buf, format="wav")
    return buf.getvalue()


async def normalize_gain(audio_bytes: bytes, *, input_format: str = "m4a") -> bytes:
    """Normaliza o VOLUME (não o conteúdo) do áudio gravado antes de mandar
    pro fingerprint: sobe o pico da gravação até quase 0dBFS, usando todo o
    range dinâmico disponível.

    Motivação (14/ago/2026): usuário relatou que o modo Ouvir só acerta
    quando o celular está bem perto da caixa de som, ao contrário do Shazam,
    que reconhece de mais longe no mesmo lugar/volume. Uma gravação captada
    longe da fonte tem o pico bem abaixo de 0dBFS (soa "baixo") — o app hoje
    manda esse áudio cru pro provedor sem nenhum tratamento. Normalizar o
    pico sobe o volume percebido da gravação inteira (útil ou ruído) na
    mesma proporção — não é redução de ruído, é só parar de desperdiçar o
    range dinâmico disponível no arquivo antes de comprimir/enviar.

    Retorna WAV sem perdas (evita comprimir em AAC duas vezes: uma na
    gravação, outra aqui — dado que já precisamos decodificar pra
    normalizar, não faz sentido recomprimir com perda de novo). Se a
    decodificação falhar por qualquer motivo (arquivo corrompido, bytes de
    teste/mock, formato inesperado), cai pros bytes originais sem levantar
    — pré-processamento é um reforço, nunca deve ser o motivo de uma busca
    falhar.
    """
    try:
        return await asyncio.to_thread(_normalize_gain_sync, audio_bytes, input_format)
    except Exception:
        logger.warning("Falha ao normalizar ganho do áudio — seguindo com o arquivo original.", exc_info=True)
        return audio_bytes
