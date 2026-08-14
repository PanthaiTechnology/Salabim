"""Cliente do ACRCloud — fingerprint de áudio "normal" (Music Recognition),
candidato a substituir a AudD no modo "ouvir" (equivalente ao Shazam).

Importante: exige criar um PROJETO DO TIPO "Audio & Video Recognition" no
console do ACRCloud — é DIFERENTE do projeto "Humming" já usado no modo
Cantar (acrcloud_client.py). Cada tipo de projeto tem sua própria
ACCESS_KEY/SECRET; a assinatura da request e o `data_type="audio"` são
idênticos entre os dois tipos (confirmado com o suporte deles pro projeto de
Humming — mesmo mecanismo vale aqui), só a chave usada e o formato da
resposta (`metadata.music` em vez de `metadata.humming`) mudam.

Teste (14/ago/2026): usuário relatou que o modo Ouvir só reconhecia com o
celular bem perto da caixa de som, ao contrário do Shazam — candidato a
causa raiz é a própria AudD ser menos robusta que o motor do ACRCloud pra
esse cenário (áudio mais baixo/ruidoso). Ver `Settings.listen_recognition_provider`
em app/config.py pra trocar entre os dois sem precisar mudar código.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import time

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings


class ACRCloudFingerprintResult:
    def __init__(self, title: str, artist: str, album: str | None, isrc: str | None,
                 release_date: str | None, score: float):
        self.title = title
        self.artist = artist
        self.album = album
        self.isrc = isrc
        self.release_date = release_date
        self.score = score


def _build_signature(access_key: str, access_secret: str, timestamp: str) -> str:
    # Mesma construção de assinatura do projeto de Humming (ver
    # acrcloud_client.py) — path, método e data_type são iguais entre os
    # dois tipos de projeto, só a chave muda.
    string_to_sign = "\n".join(
        ["POST", "/v1/identify", access_key, "audio", "1", timestamp]
    )
    signature = base64.b64encode(
        hmac.new(access_secret.encode(), string_to_sign.encode(), hashlib.sha1).digest()
    )
    return signature.decode()


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def identify_audio(audio_bytes: bytes, filename: str = "audio.wav") -> ACRCloudFingerprintResult | None:
    settings = get_settings()
    if not (settings.acrcloud_fingerprint_access_key and settings.acrcloud_fingerprint_access_secret):
        raise RuntimeError(
            "ACRCLOUD_FINGERPRINT_ACCESS_KEY/SECRET não configurados — veja backend/.env.example"
        )

    timestamp = str(time.time())
    signature = _build_signature(
        settings.acrcloud_fingerprint_access_key, settings.acrcloud_fingerprint_access_secret, timestamp
    )

    data = {
        "access_key": settings.acrcloud_fingerprint_access_key,
        "sample_bytes": str(len(audio_bytes)),
        "timestamp": timestamp,
        "signature": signature,
        "data_type": "audio",
        "signature_version": "1",
    }

    url = f"https://{settings.acrcloud_fingerprint_host}/v1/identify"
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(url, data=data, files={"sample": (filename, audio_bytes)})
        response.raise_for_status()
        payload = response.json()

    status_code = payload.get("status", {}).get("code")
    if status_code != 0:
        return None

    music = (payload.get("metadata") or {}).get("music", [])
    if not music:
        return None

    # Só o melhor candidato — ao contrário do Humming, fingerprint de áudio
    # normal não tem a mesma ambiguidade de cover/versão (o trecho gravado
    # é da gravação exata tocando, não uma melodia cantarolada), então não
    # precisa do reranking por letra/canonicidade que o modo Cantar faz.
    best = music[0]
    artists = ", ".join(a["name"] for a in best.get("artists", [])) or "Desconhecido"

    return ACRCloudFingerprintResult(
        title=best.get("title", "Desconhecido"),
        artist=artists,
        album=(best.get("album") or {}).get("name"),
        isrc=best.get("external_ids", {}).get("isrc"),
        release_date=best.get("release_date"),
        # Validado contra a doc do ACRCloud: o score do fingerprint normal
        # vem 0-100 (diferente do Humming, que já vem 0.0-1.0) — normaliza
        # aqui pra manter match_confidence consistente entre provedores.
        score=float(best.get("score", 0)) / 100.0,
    )
