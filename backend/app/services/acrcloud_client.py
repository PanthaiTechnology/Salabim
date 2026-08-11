"""Cliente do ACRCloud — busca por Humming/Singing (cantarolar, cantar, assobiar,
tocar num instrumento). Este é o equivalente ao "Hum to Search" do Google.

Importante: exige criar um PROJETO DO TIPO "Humming" no console do ACRCloud
(é diferente do projeto de fingerprint de áudio comum) — é a ACCESS_KEY desse
projeto que faz o motor de humming ser usado, não nenhum parâmetro da request
(confirmado com o suporte deles: `data_type` continua sendo "audio", igual ao
endpoint de fingerprint normal).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import time

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings


class ACRCloudResult:
    def __init__(self, title: str, artist: str, album: str | None, isrc: str | None, score: float):
        self.title = title
        self.artist = artist
        self.album = album
        self.isrc = isrc
        self.score = score


def _build_signature(access_key: str, access_secret: str, timestamp: str) -> str:
    # Validado manualmente contra a API real: o path correto é "/v1/identify"
    # (sem o prefixo "/api") — usar "/api/v1/identify" aqui OU na URL da request
    # retorna 404 puro do openresty, sem chegar a autenticar.
    #
    # data_type="audio" (não "humming"!) — confirmado pelo suporte do
    # ACRCloud: o motor de humming é decidido pelo PROJETO (a access_key),
    # não por esse parâmetro. Usar "humming" aqui sempre retornava
    # "No result" mesmo pra músicas óbvias — era esse o bug o tempo todo.
    string_to_sign = "\n".join(
        ["POST", "/v1/identify", access_key, "audio", "1", timestamp]
    )
    signature = base64.b64encode(
        hmac.new(access_secret.encode(), string_to_sign.encode(), hashlib.sha1).digest()
    )
    return signature.decode()


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def identify_humming(audio_bytes: bytes, filename: str = "hum.wav") -> ACRCloudResult | None:
    settings = get_settings()
    if not (settings.acrcloud_access_key and settings.acrcloud_access_secret):
        raise RuntimeError("ACRCLOUD_ACCESS_KEY/SECRET não configurados — veja backend/.env.example")

    timestamp = str(time.time())
    signature = _build_signature(settings.acrcloud_access_key, settings.acrcloud_access_secret, timestamp)

    data = {
        "access_key": settings.acrcloud_access_key,
        "sample_bytes": str(len(audio_bytes)),
        "timestamp": timestamp,
        "signature": signature,
        "data_type": "audio",
        "signature_version": "1",
    }

    url = f"https://{settings.acrcloud_host}/v1/identify"
    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(url, data=data, files={"sample": (filename, audio_bytes)})
        response.raise_for_status()
        payload = response.json()

    status_code = payload.get("status", {}).get("code")
    if status_code != 0:
        return None

    music = (payload.get("metadata") or {}).get("humming", [])
    if not music:
        return None

    best = music[0]
    artists = ", ".join(a["name"] for a in best.get("artists", [])) or "Desconhecido"

    return ACRCloudResult(
        title=best.get("title", "Desconhecido"),
        artist=artists,
        album=(best.get("album") or {}).get("name"),
        isrc=best.get("external_ids", {}).get("isrc"),
        # Validado contra a API real: o score do humming já vem normalizado
        # entre 0.0 e 1.0 (ex: 0.96) — não é uma porcentagem 0-100.
        score=float(best.get("score", 0)),
    )
