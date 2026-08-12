# Salabim — Arquitetura Técnica

> Shazam + "Hum to Search" (Google) em um único app: grave a música tocando, cante,
> cantarole, assobie, toque num instrumento, ou descreva/digite um trecho da letra —
> o Salabim identifica a faixa e te leva direto para ela no Spotify, Apple Music,
> Deezer, Tidal e YouTube Music.

## 1. Visão geral do sistema

```
┌──────────────────────┐        HTTPS/REST        ┌───────────────────────────┐
│   App Flutter         │ ────────────────────────▶ │  Backend API (FastAPI)    │
│  iOS + Android         │ ◀──────────────────────── │  Python 3.12              │
└──────────────────────┘        JSON + preview URL   └─────────────┬─────────────┘
                                                                    │
                     ┌──────────────────────────┬──────────────────┼───────────────────────────┐
                     ▼                          ▼                  ▼                            ▼
           ┌──────────────────┐      ┌──────────────────┐   ┌──────────────┐         ┌────────────────────┐
           │ AudD API          │      │ ACRCloud          │   │ Odesli/song.link│      │ Postgres + Redis    │
           │ fingerprint de    │      │ Humming/Singing   │   │ resolve links   │      │ histórico, cache,   │
           │ áudio gravado     │      │ (cantar/assobiar) │   │ cross-platform  │      │ rate-limit, sessão  │
           └──────────────────┘      └──────────────────┘   └──────────────┘         └────────────────────┘
```

O Salabim **não treina um modelo próprio de reconhecimento musical do zero** — isso é
o que o Google levou anos e um catálogo licenciado gigantesco para construir. Em vez
disso, o backend orquestra dois provedores especializados e um serviço agregador de
links, e entrega tudo isso atrás de uma UX única, no estilo Shazam. Esse orquestrador
é o verdadeiro produto e o ativo proprietário do Salabim.

## 2. Os 4 modos de busca (o diferencial do app)

| Modo | Como o usuário interage | Motor usado | Observação |
|---|---|---|---|
| **Ouvir música tocando** | Segura o botão, o app grava ~8–12s do ambiente | AudD (fingerprint acústico) | Igual ao Shazam clássico |
| **Cantarolar / Cantar / Assobiar / Tocar instrumento** | Toggle "Hum" antes de gravar | ACRCloud Humming/Singing (melodia) **+ Whisper local (letra transcrita da voz)** combinados | Equivalente ao Hum to Search do Google — ver §4.1 |
| **Descrever a música** | Campo de texto livre ("aquela música do comercial de carro dos anos 90 com refrão animado") | Backend → busca semântica (embeddings + fallback para API de letras) | Fase 2 — ver §7 |
| **Trecho da letra** | Digita um pedaço da letra | Musixmatch/Genius (busca textual) | Retorna candidatos, sem necessidade de áudio |

O app decide automaticamente qual provedor chamar; o usuário só escolhe **como** vai
interagir (microfone normal vs. modo "cantarolar", ou texto).

## 3. Stack escolhida

- **Mobile:** Flutter (iOS + Android com uma única base de código), Riverpod para
  estado, `record` para captura de áudio, `just_audio` para tocar o preview de 15s,
  `url_launcher` para abrir os apps de streaming.
- **Backend:** Python 3.12 + FastAPI, Uvicorn/Gunicorn, Pydantic v2, SQLAlchemy 2 +
  Alembic, PostgreSQL (histórico/favoritos/usuários), Redis (cache de resultados e
  rate limiting), armazenamento de áudio temporário em S3/MinIO só durante o
  processamento (apagado após alguns minutos).
- **Reconhecimento:**
  - [AudD](https://audd.io) — fingerprint de áudio gravado (modo "Shazam").
  - [ACRCloud](https://www.acrcloud.com) — "Humming/Singing Recognition" (modo "Hum
    to Search").
  - [Odesli / song.link](https://odesli.co) — a partir de um ISRC/URL de uma
    plataforma, devolve os links equivalentes em Spotify, Apple Music, Deezer,
    Tidal, YouTube Music, Amazon Music etc. Essencial para a tela de resultado.
  - Musixmatch (ou Genius) API — busca por trecho de letra.
- **Infra/DevOps:** Docker + docker-compose local; produção em container
  (Cloud Run / ECS Fargate / Fly.io — qualquer um serve, ver §8); GitHub Actions
  para CI (lint, testes, build); Fastlane para automatizar builds/releases iOS e
  Android.

## 4. Fluxo ponta a ponta ("ouvir" ou "cantarolar")

1. App grava áudio local (AAC/WAV), no máximo ~12s.
2. `POST /v1/identify` (multipart: arquivo + `mode=listen|hum`).
3. Backend valida, gera hash do áudio, checa cache no Redis (evita chamar o
   provedor duas vezes para o mesmo trecho).
4. Se `mode=listen` → chama AudD. Se `mode=hum` → ver §4.1 (combina melodia + letra).
5. Provedor retorna metadados (título, artista, álbum, ISRC/UPC quando disponível).
6. Backend chama Odesli com o ISRC (ou o link retornado pelo provedor) e recebe os
   links de todas as plataformas de streaming disponíveis para aquele território.
7. Backend monta um preview de 10–15s (via URL de preview do próprio provedor, ou
   de uma plataforma que ofereça preview público) e devolve tudo em JSON.
8. App mostra a tela de resultado: capa, título, artista, player de preview,
   botões para Spotify/Apple Music/Deezer/Tidal/YouTube Music, e opção de salvar
   no histórico.

### 4.1 Modo "Cantar" — combinando melodia + letra transcrita

O ACRCloud sozinho tem dois problemas conhecidos (validados com testes reais):
(a) às vezes acerta a MÚSICA mas bate numa gravação obscura/cover em vez do
original, e (b) o algoritmo de melodia por si só tem uma taxa de erro real,
maior que a do fingerprint de áudio tradicional. A resposta a isso é combinar
sinais independentes, como um humano faz ao reconhecer uma música cantada:

1. Dispara em paralelo: `acrcloud_client.identify_humming_candidates()` (todos
   os candidatos, não só o melhor) **e** `speech_client.transcribe()` (Whisper,
   modelo "base", roda local — sem chave/custo, exige `ffmpeg` no sistema).
2. Cada candidato do ACRCloud recebe um score combinado: `0.6 × score de
   melodia + 0.4 × sobreposição de palavras entre o título e a transcrição`.
   Se a pessoa canta palavras reais, isso ajuda a desempatar/corrigir a favor
   do candidato certo — se ela só cantarola sem letra, a transcrição fica
   vazia e o ranking cai de volta pro score de melodia puro.
3. O candidato de maior score combinado passa por `_prefer_canonical_version()`:
   busca no iTunes só pelo TÍTULO (sem o artista que o ACRCloud achou) — se o
   artista mais popular pra esse título for diferente, troca pra essa versão
   (é assim que "Every Breath You Take" por uma cover band vira "Every Breath
   You Take" do The Police).

**Limite conhecido e aceito:** isso é uma aproximação por combinação de sinais,
não um modelo de IA treinado como o do Google — não existe garantia de acerto
para músicas muito obscuras ou interpretações muito desafinadas. Musixmatch
configurado (§9) permitiria uma busca por letra mais completa (não só o
título) como sinal adicional no futuro.

### 4.2 Sistema de correção/feedback — memória de erros, não "re-treino" da IA

Estudo de caso feito com o usuário (ago/2026) sobre construir um motor de humming
totalmente próprio (base de fingerprints + modelo de ML treinado do zero): **inviável
a curto prazo** — o obstáculo maior é jurídico (analisar áudio de faixas de terceiros
em escala exige licenciamento direto com gravadoras/distribuidoras, não só ter o
ISRC/UPC), não técnico. Ver decisão registrada nesta seção como referência caso o
tema volte a ser considerado no futuro.

Caminho intermediário adotado: um sistema de correção que aprende com o uso real,
sem depender de licenciar catálogo nenhum.

- **Fase 0 (implementada):** usuário marca um resultado do modo Cantar como
  certo/errado pelo app; se errado, informa o nome real. Isso vira uma correção
  salva (Redis) e é aplicada automaticamente da próxima vez que o **mesmo** erro
  específico acontecer.
- **Fase 1 (implementada):** a busca da correção salva é por **similaridade de
  texto** (`difflib.SequenceMatcher`, limiar 0.82 combinando 70% título + 30%
  artista — ver `feedback_service.py`), não por igualdade exata — assim uma
  correção feita pra "Every Breath You Take (Remastered 2003)" também vale pra
  variações de sufixo/pontuação do mesmo erro, sem precisar corrigir de novo a
  cada pequena diferença de nome.
- **Fase 2 (roadmap — não implementada):** treinar um classificador leve (ex:
  regressão logística/árvore de decisão, dados tabulares — não é um modelo de
  áudio) usando como features os sinais que o orquestrador já calcula por busca
  (score de melodia do ACRCloud, similaridade da transcrição de voz com o preview
  oficial de cada candidato, quantos candidatos convergem pro mesmo título, se
  passou pela troca cover→original). O modelo aprenderia os pesos de decisão
  sozinho a partir de exemplos reais, em vez dos pesos fixos "0.6 melodia / 0.4
  letra" que o código usa hoje. **Só compensa implementar depois que o app tiver
  uso real suficiente pra gerar um dataset de correções minimamente
  representativo** (algumas centenas de exemplos reais, não só testes manuais) —
  a coleta de dados (Fase 0/1) já está rodando em produção, então quando esse
  volume existir, a Fase 2 não exige reconstruir nada, só adicionar um script de
  treino + um passo de inferência no `recognition_service.py`.

## 5. Fluxo de busca por texto (descrição / letra)

1. `POST /v1/search/text` com `{ query, kind: "lyrics" | "description" }`.
2. `kind=lyrics` → Musixmatch (busca textual direta).
3. `kind=description` → o backend usa embeddings (ex. modelo pequeno rodando no
   próprio serviço, ou API de embeddings) para achar candidatos mais prováveis a
   partir de um índice de metadados (título, artista, gênero, década, contexto)
   construído a partir do próprio histórico de buscas + catálogos públicos.
   **Esta é a única parte que é "ML própria"** do Salabim, e nasce simples (busca
   por similaridade de texto) podendo evoluir depois.
4. Resultado sempre passa pelo mesmo pipeline do §4 (passo 6 em diante) para
   anexar links de streaming.

## 6. Contrato da API (resumo — detalhado em `docs/api_contract.md`)

- `POST /v1/identify` — multipart(file, mode) → `Track | 404`
- `POST /v1/search/text` — json(query, kind) → `Track[]` **sem** `platform_links`
  (resolvidos sob demanda, ver abaixo — bug real já corrigido: resolver pra
  cada item de uma lista de busca estourava a cota do Odesli e derrubava os
  links de TODAS as buscas até resetar)
- `GET /v1/tracks/{id}` — detalhe + links (resolve `platform_links` agora, se
  ainda não tiverem sido resolvidos)
- `POST /v1/feedback` — confirma/corrige um resultado do modo Cantar
- `GET /v1/history` — histórico do usuário (autenticado)
- `POST /v1/favorites/{track_id}` — favoritar
- `GET /v1/health` — healthcheck

## 7. Roadmap

**Fase 1 (este scaffold):** app funcional com os 2 modos de áudio (ouvir + cantarolar)
e busca por letra, backend integrado a AudD + ACRCloud + Odesli + Musixmatch,
histórico e favoritos, infra de deploy pronta.

**Fase 2:** busca por "descrição livre" com embeddings próprios; modo offline com
cache local de últimas identificações; compartilhamento social; Apple
Watch/widget de tela de bloqueo (iOS) e widget Android.

**Fase 3:** monetização (assinatura Salabim Pro: buscas ilimitadas, sem anúncios,
identificação em playlists inteiras) via RevenueCat (abstrai StoreKit/Play
Billing).

**Conta de usuário (opcional, avaliar pós-Internal Testing):** login por
e-mail e/ou social (Google primeiro — mais simples, sem revisão externa;
Facebook depois, exige app + revisão no Facebook for Developers; iOS exige
"Sign in with Apple" se oferecer qualquer login social). Decisão explícita
do produto (12/ago/2026): **não obrigatório** — o app continua usável sem
login (mantém a velocidade que é o valor central, igual Shazam/SoundHound,
que não travam a função principal atrás de cadastro); conta serve pra quem
quiser sincronizar histórico entre aparelhos. Arquitetura atual já suporta
isso sem retrabalho: backend é REST sem sessão (só soma `/v1/auth/*`),
histórico local existente migra pra conta no momento do login. Exige
reescrever a política de privacidade e o Data Safety (Play Console) pra
declarar e-mail/identificador de conta quando for implementado.

## 8. Deploy / Infraestrutura (visão geral, detalhado em `devops/`)

- **Backend:** container único (`backend/Dockerfile`), roda atrás de um load
  balancer com HTTPS. Recomendado: **Fly.io** ou **Google Cloud Run** (escala a
  zero, custo baixo para começar) — trocar para AWS ECS Fargate quando o volume
  justificar.
- **Banco:** Postgres gerenciado (Neon, Supabase ou RDS).
- **Cache:** Redis gerenciado (Upstash é o mais barato para começar).
- **Áudio temporário:** bucket S3-compatible (Cloudflare R2 é o mais barato, sem
  taxa de egress).
- **CI/CD:** GitHub Actions — lint + testes a cada PR; build + deploy automático
  do backend ao dar merge em `main`; build de app (Flutter) via Codemagic ou
  Fastlane + GitHub Actions self-hosted (build iOS exige macOS).

## 9. Custos externos que você precisa contratar

Nenhuma dessas contas pode ser criada por mim — são contas comerciais/pagas que só
você pode abrir. O app já está com os "encaixes" prontos; basta colocar as chaves
no `.env`:

| Serviço | Para quê | Onde contratar |
|---|---|---|
| AudD | Fingerprint de áudio | https://audd.io |
| ACRCloud | Humming/Singing search | https://www.acrcloud.com |
| Odesli | Links cross-platform | https://odesli.co (tem tier gratuito p/ baixo volume) |
| Musixmatch | Busca por letra | https://developer.musixmatch.com |
| Apple Developer Program | Publicar na App Store | https://developer.apple.com (US$99/ano) |
| Google Play Console | Publicar na Play Store | https://play.google.com/console (US$25 único) |

## 10. Aviso legal importante

Reconhecer músicas e devolver links para plataformas de streaming é permitido via
esses provedores (é o modelo de negócio deles). Mas **entregar preview de áudio da
própria música** deve usar sempre o preview oficial fornecido pelo provedor/loja
(ex: preview de 30s do iTunes/Apple Music, preview do Spotify via oEmbed) — nunca
recortar e hospedar trechos de faixas com direitos autorais por conta própria. O
scaffold já está desenhado para usar apenas previews oficiais.
