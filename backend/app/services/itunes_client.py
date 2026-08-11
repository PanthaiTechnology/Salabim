"""Cliente do iTunes Search API — usado como enriquecimento pra preencher
capa e preview de 30s em resultados que não vêm com isso (ACRCloud/Musixmatch
não retornam artwork nem áudio de preview, diferente da AudD).

Sem chave, gratuito. Não suporta busca por ISRC de forma confiável (testado:
`isrc=` sempre retorna vazio, mesmo pra faixas que sabemos estar lá) — por
isso a busca é por texto (título + artista).
"""
from __future__ import annotations

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

SEARCH_ENDPOINT = "https://itunes.apple.com/search"


class ItunesResult:
    def __init__(self, artwork_url: str | None, preview_url: str | None, album: str | None):
        self.artwork_url = artwork_url
        self.preview_url = preview_url
        self.album = album


@retry(stop=stop_after_attempt(2), wait=wait_exponential(min=1, max=4))
async def search_by_title_artist(title: str, artist: str) -> ItunesResult | None:
    params = {"term": f"{title} {artist}", "entity": "song", "limit": "1"}
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(SEARCH_ENDPOINT, params=params)
        if response.status_code != 200:
            return None
        payload = response.json()

    results = payload.get("results", [])
    if not results:
        return None

    hit = results[0]
    # artworkUrl100 vem em 100x100 — o mesmo padrão de URL aceita outras
    # resoluções trocando esse trecho, então pegamos uma capa maior de graça.
    artwork = hit.get("artworkUrl100")
    if artwork:
        artwork = artwork.replace("100x100bb", "600x600bb")

    return ItunesResult(
        artwork_url=artwork,
        preview_url=hit.get("previewUrl"),
        album=hit.get("collectionName"),
    )
