# Contrato da API — Salabim Backend

Base URL (dev): `http://localhost:8000` · Documentação interativa automática: `/docs` (Swagger) e `/redoc`.

## POST /v1/identify

Identifica uma música a partir de um trecho de áudio gravado.

**Request:** `multipart/form-data`
| Campo | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `file` | arquivo de áudio | sim | 3–12s, m4a/wav/mp3 |
| `mode` | `listen` \| `hum` | sim | `listen` = música tocando (AudD) · `hum` = cantarolar/assobiar/cantar/instrumento (ACRCloud) |

**Response 200:**
```json
{
  "found": true,
  "track": {
    "id": "a1b2c3d4e5f6a7b8",
    "title": "Song Name",
    "artist": "Artist Name",
    "album": "Album Name",
    "artwork_url": "https://...",
    "isrc": "USRC17607839",
    "preview_url": "https://...",
    "matched_provider": "audd",
    "match_confidence": 1.0,
    "platform_links": [
      { "platform": "spotify", "url": "https://open.spotify.com/track/..." },
      { "platform": "apple_music", "url": "https://music.apple.com/..." },
      { "platform": "deezer", "url": "https://deezer.com/..." },
      { "platform": "tidal", "url": "https://tidal.com/..." },
      { "platform": "youtube_music", "url": "https://music.youtube.com/..." }
    ]
  }
}
```

**Response 200 (não encontrado):** `{ "found": false, "message": "..." }`
**Response 429:** limite de requisições excedido (30 req/min por IP, ajustável em `app/core/cache.py`).

## POST /v1/search/text

**Request (JSON):**
```json
{ "query": "trecho da letra ou descrição", "kind": "lyrics" }
```
`kind`: `lyrics` (busca textual via Musixmatch) ou `description` (busca semântica — fase 2, hoje cai no fallback de letra).

**Response 200:** `{ "results": [ <Track>, ... ] }` (mesmo formato de `Track` acima).

## GET /v1/history *(autenticado — Bearer token)*

Retorna as últimas 100 buscas do usuário, mais recentes primeiro.

## POST /v1/favorites/{track_id} *(autenticado)*

Marca uma faixa (já vista em algum resultado) como favorita.

## GET /v1/health

```json
{ "status": "ok", "providers": { "audd": true, "acrcloud": false, "odesli": true, "musixmatch": true } }
```
`providers` indica quais integrações têm chave de API configurada no `.env` — útil pra tela de diagnóstico e pro CI.
