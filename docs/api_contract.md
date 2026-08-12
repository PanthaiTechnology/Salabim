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

`platform_links` sempre vem com **Spotify primeiro quando disponível** (é a
plataforma mais usada — pedido explícito do produto), seguido pelas outras
na ordem que o Odesli retornar. Ver `odesli_client.py` +
`recognition_service._resolve_platform_links` (usa a API oficial do Spotify
como reforço quando o Odesli não traz o link — caso real confirmado com
"Karma" de Summer Walker, onde o Odesli não tinha o Spotify mapeado pra
aquela faixa mesmo ela estando lançada lá).

**Response 200 (não encontrado):** `{ "found": false, "message": "..." }`
**Response 429:** limite de requisições excedido (30 req/min por IP, ajustável em `app/core/cache.py`).

## POST /v1/search/text

**Request (JSON):**
```json
{ "query": "trecho da letra, título, ou nome do artista", "kind": "lyrics" }
```
`kind`: `lyrics` ou `description` — hoje os dois caem no mesmo motor (busca via
iTunes Search, com correção ortográfica e fallback por remoção de palavra pra
tolerar erro de digitação/palavra trocada — ver ARCHITECTURE.md §5). Musixmatch
não é mais usado (sem plano gratuito disponível pra Lyrics API).

**Response 200:** `{ "results": [ <Track>, ... ] }` (mesmo formato de `Track`
acima, **exceto** que `platform_links` vem **vazio** — ver `GET /v1/tracks/{id}`
abaixo pra resolver isso sob demanda).

## GET /v1/tracks/{id}

Detalhe completo de uma faixa, resolvendo `platform_links` agora se ainda não
tiverem sido resolvidos (é assim que a busca por texto evita gastar a cota do
Odesli pra cada item de uma lista inteira de uma vez — ver `odesli_client.py`).
Chame isso quando o usuário abrir um resultado específico da busca.

**Response 200:** um `Track` completo, com `platform_links` preenchido.
**Response 404:** faixa não encontrada ou cache expirado (6h) — busque de novo.

## POST /v1/feedback

Usuário confirma ou corrige um resultado do modo Cantar.

```json
{
  "matched_title": "Every Breath You Take (Remastered 2003)",
  "matched_artist": "Overdriver Duo",
  "mode": "acrcloud",
  "was_correct": false,
  "corrected_title": "Every Breath You Take",
  "corrected_artist": "The Police"
}
```
Quando `was_correct=false` e `mode="acrcloud"`, vira uma correção salva e
aplicada automaticamente da próxima vez que o mesmo erro (por similaridade de
texto, não igualdade exata) acontecer — ver `feedback_service.py`.

**Response 201:** `{ "ok": true }`

## GET /v1/history *(autenticado — Bearer token)*

Retorna as últimas 100 buscas do usuário, mais recentes primeiro.

## POST /v1/favorites/{track_id} *(autenticado)*

Marca uma faixa (já vista em algum resultado) como favorita.

## GET /v1/health

```json
{ "status": "ok", "providers": { "audd": true, "acrcloud": false, "odesli": true, "musixmatch": true, "spotify": true } }
```
`providers` indica quais integrações têm chave de API configurada no `.env` — útil pra tela de diagnóstico e pro CI.
`spotify` usa fluxo Client Credentials (busca no catálogo público, sem login
de usuário) — **requer que a conta Spotify dona do app no Dashboard tenha
assinatura Premium ativa**, restrição da própria Spotify pra apps nesse
modo (confirmado em produção: contas gratuitas recebem 403 "Active premium
subscription required for the owner of the app" mesmo com credenciais
corretas).
