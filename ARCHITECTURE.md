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

### 4.3 Modo "Ouvir" — causa raiz do "precisa chegar perto" vs. Shazam (14/ago/2026, RESOLVIDO)

Usuário relatou, comparando lado a lado com o Shazam no mesmo lugar/volume: o
Ouvir demora mais, às vezes erra a música, e só reconhece com o celular bem
perto da caixa de som — o Shazam reconhece de mais longe, mais rápido.
Registrando aqui a investigação completa, a causa raiz confirmada e a
correção aplicada.

**Causa raiz confirmada por teste controlado:** o usuário gravou (com o
gravador nativo do celular, fora do Salabim) um trecho de 21s exatamente no
lugar/distância onde o Salabim falhava sempre e o Shazam acertava. Testamos
esse MESMO arquivo direto na API da AudD, recortado em durações crescentes
a partir do início:

| Duração testada | Resultado |
|---|---|
| 4-8s (qualquer recorte) | Nada encontrado |
| **10-14s** | **Encontra — mas ERRADO** (3 músicas diferentes testadas, nenhuma correta) |
| 16-21s | Encontra certo, de forma consistente |

Ou seja: a AudD **não fica em silêncio** quando recebe áudio insuficiente —
a partir de ~10s ela já arrisca um palpite, e só fica confiável de verdade
com ~16s+. O Ouvir mandava só 4s por tentativa. Isso explica os dois
sintomas relatados ao mesmo tempo (não encontra E às vezes erra) com uma
única causa, e descarta de vez as hipóteses de compressão/captura/pipeline
(o arquivo de teste tinha o MESMO perfil de codificação — AAC-LC 44.1kHz
mono — que o app já usa).

**Correção aplicada (parte 1):** `ListenController._segmentDurationFor` (mobile)
agora usa durações crescentes por tentativa em vez de um número fixo
repetido — 6s na 1ª tentativa (rápido pros casos fáceis; nesse patamar o
teste mostrou "nada" em vez de "errado", seguro tentar curto primeiro), 18s
na 2ª, pulando de propósito a faixa perigosa de 10-14s. Continua parando
cedo se achar rápido (o pipeline já aceita o primeiro resultado não vazio
de qualquer tentativa).

**Segunda causa encontrada — a normalização de ganho piorava justamente as
durações maiores:** depois de ativar a correção acima, a métrica real
(`GET /v1/debug/identify-stats`) mostrou taxa de acerto AINDA pior (6,2% em
145 tentativas) — a correção de duração sozinha não bastou. Reaplicamos o
mesmo teste controlado, dessa vez comparando os recortes de 12-18s **com**
e **sem** `audio_utils.normalize_gain`:

| Duração | Sem normalizar | Com normalizar |
|---|---|---|
| 16s | **Certo** (DeadWhite) | Errado (DJ big shot) |
| 18s | **Certo** (DeadWhite) | Errado (Abbey8K) |

A normalização (sobe o PICO até ~0dBFS) transformou dois resultados certos
em errados. Hipótese confirmada: em gravações mais longas, normalizar por
pico (em vez de RMS/loudness) tem mais chance de um ruído isolado dominar o
cálculo e distorcer a proporção do áudio real — o oposto do que a
normalização queria resolver. **Normalização desligada** (código mantido em
`audio_utils.normalize_gain`, só não é mais chamada) — o Ouvir volta a
mandar o áudio original pra AudD, só com as durações maiores.

**Tentativa de stream contínuo — implementada e REVERTIDA (14/ago/2026):**
pra checar em mais pontos (4s, 8s, 18s) sem sofrer o problema de "colar
gravações separadas" (ver teste abaixo), reescrevemos a captura do Ouvir
pra usar `AudioRecorder.startStream` (PCM bruto contínuo, nunca
para/reinicia o microfone) com um WAV montado na hora a cada checkpoint —
commit `2d77608`. O teste QUE VALIDOU a ideia foi feito só com ffmpeg/pydub
no computador (simulando blocos colados vs. contínuos a partir de um
arquivo já gravado) — nunca testamos a implementação real do
`AudioRecorder.startStream` do pacote `record` num aparelho de verdade
antes de shippar. Resultado em uso real: ficava muito tempo preso em
"ouvindo" e "processando" demorava muito mais que antes — pior experiência
geral, mesmo a AudD respondendo rápido (~700ms, confirmado na métrica, ou
seja o atraso NÃO era do backend). Causa exata não diagnosticada (não tinha
instrumentação client-side pra isso) — **revertido** (`git revert 2d77608`,
commit `6a5ca5c`) de volta pra duas gravações separadas (4s, depois 18s do
zero se a primeira falhar), que é o estado validado que funciona.

**Lição pra próxima vez que mexer nisso:** validar mudança de CAPTURA
(diferente de mudança de configuração/parâmetro) sempre no aparelho real
antes de considerar "provado" — um teste offline com ffmpeg/pydub valida a
IDEIA (ex: "colar blocos separados degrada"), mas não garante que a
IMPLEMENTAÇÃO real no pacote `record`/Android se comporta como esperado.

**Mudança de estratégia — de "duração segura" pra "confirmação por
concordância" (14/ago/2026):** depois de reverter o stream contínuo,
confirmamos com um SEGUNDO teste real (vídeo com tela+microfone gravando
"Psycho Pt. 2" do Russ) que o app retornou **"Fácil" de Zeke** — errado —
com ~18s de gravação. A primeira música testada (DeadWhite) tinha dado
CERTO com 16-18s. Duas músicas reais, mesma duração, resultados opostos:
**confirma que não existe duração "segura" universal** — o ponto de corte
varia por música, ruído ambiente e distância da fonte, então qualquer
número fixo (curto ou longo) vai estar certo pra uma situação e errado pra
outra.

Mudança de critério de aceitação (pedido direto do usuário — "não pode ser
universal... a única coisa que tem que acontecer é: reconhecer a música
certa, e assim que reconhecer, enviar"): em vez de aceitar a PRIMEIRA
resposta não-vazia de qualquer tentativa, o Ouvir agora exige que **duas
tentativas independentes concordem** no mesmo resultado (mesmo
`track.id`) antes de aceitar. Um acerto de verdade tende a se repetir
conforme mais contexto é dado ao motor; um palpite errado isolado
raramente se repete de forma idêntica numa tentativa seguinte
independente. Isso se autoajusta por música/ambiente sem precisar
adivinhar limiar nenhum:

- Caso fácil (perto, alto, música "fácil" de reconhecer): as 2 primeiras
  tentativas (4s, 8s) já tendem a concordar — confirma rápido.
- Caso difícil: leva mais tentativas até 2 baterem — mais lento, mas não
  aceita um palpite errado isolado no caminho.

`_listenSegmentDurations` ampliado pra 5 tentativas crescentes (4s, 8s,
12s, 16s, 20s — mais chances de encontrar 2 que concordem);
`_listenCandidates` guarda os resultados não-vazios já vistos na sessão;
`_recordAndSearchSegment` só aceita quando o resultado da tentativa atual
já apareceu antes na lista. Cantar não foi tocado (continua aceitando a
1ª resposta — o motor dele já combina melodia+letra no backend, não
precisa dessa confirmação extra).

**Diagnóstico de arquitetura (por que a diferença existe, estruturalmente):**
o Shazam calcula o fingerprint **no próprio aparelho** e manda pro servidor
só uma consulta compacta (poucos KB) — não o áudio gravado. O Salabim (como
a maioria dos apps que consomem AudD/ACRCloud via API REST) grava, comprime
e faz **upload do áudio inteiro**, e só então o provedor calcula o
fingerprint do lado dele. Essa etapa a mais (upload de dezenas de KB +
decodificação do lado do provedor) é tempo que o Shazam não gasta. Sample
rate maior **não é o gargalo** — 44.1kHz já é mais que suficiente (algoritmos
de fingerprint costumam reamostrar pra 8-16kHz internamente); bitrate do AAC
(128kbps, padrão do pacote `record`) também não é.

**O que já foi testado (todas reversíveis via git, ver mensagens de commit
das datas citadas):**

| Mudança | Resultado | Situação |
|---|---|---|
| Normalizar o pico do áudio antes de enviar pro fingerprint (`audio_utils.normalize_gain`, sobe o volume captado até ~0dBFS) | Usuário reportou melhora inicial, mas teste controlado depois mostrou que piorava justamente as durações maiores (16-18s) — ver detalhe abaixo | **Desligado** (código mantido, não chamado) |
| Trocar o provedor do Ouvir de AudD pra ACRCloud fingerprint (`Settings.listen_recognition_provider`, infraestrutura pronta pra reativar) | Pior em distância, precisão E velocidade — mas teste "sujo": a conta trial só permite 1 projeto, então rodou no mesmo projeto/chave do Cantar com o motor **combinado** (Audio Fingerprinting + Cover Song), que processa os dois motores em toda chamada | Revertido (voltou pra `audd`). Não foi um teste justo — ver "próximos passos" abaixo |
| `AndroidAudioSource.camcorder` no lugar da fonte padrão do microfone (evita AGC/cancelamento de ruído pensado pra chamada de voz, que trata música de fundo como "ruído" a suprimir) | Piorou no teste em aparelho real | Revertido (voltou pra `AndroidAudioSource.defaultSource`) |
| Segmento de gravação de 4s → 7s (mais contexto por tentativa, menos tentativas) | Taxa de acerto caiu pra 11% (medido, não "achismo" — ver métrica abaixo) | Revertido (voltou pra 4s / 5 tentativas) |

**Nota tardia (14/ago/2026) sobre a linha do ACRCloud fingerprint acima:**
na época, achávamos que o teste era "sujo" só por causa do motor combinado.
Descoberta mais tarde (ver §4.5): o projeto do ACRCloud estava configurado
com o "Audio Engine" em **só** Cover Song/Humming — ou seja, esse teste
antigo rodou com Fingerprinting **desligado por completo**, não só
"misturado" com Humming. O resultado ruim registrado ali pode ter sido
100% causado por isso, não pela distância/precisão do motor de
fingerprint em si (nunca chegou a rodar). Não foi re-testado via REST
depois da correção — o motor combinado agora está ligado, então se
`listen_recognition_provider` for reativado no futuro, vale re-medir do
zero antes de tirar qualquer conclusão nova.

**Infraestrutura de medição criada nesse processo** (pra parar de comparar
mudança "por sensação" de teste manual): `backend/app/services/recognition_metrics.py`
cronometra cada tentativa de identify (Ouvir e Cantar) e grava evento
estruturado (modo, provedor, latência, achou ou não, confiança) no log e
numa lista no Redis. `GET /v1/debug/identify-stats?mode=listen&provider=audd`
agrega isso em contagem/taxa de acerto/latência média/p50/p95 — sem
autenticação (só agregado, nada sensível). Qualquer teste futuro deve passar
por essa métrica antes de decidir manter ou reverter.

**Opção investigada e não implementada — SDK on-device do ACRCloud:**
confirmado (docs oficiais + repositório `acrcloud/ACRCloudUniversalSDK`) que
o SDK mobile deles calcula o fingerprint no aparelho e manda só o buffer
compacto pro servidor — a mesma arquitetura do Shazam de verdade. Duas
ressalvas que adiaram a decisão de implementar:
1. **Não existe SDK oficial pra Flutter** — só Android/iOS nativo, Unity e
   SDKs de backend. Precisaria de uma ponte nativa (Kotlin + `MethodChannel`),
   investimento de tempo real, não uma troca de configuração.
2. **Resolve velocidade, não necessariamente precisão** — o SDK muda só
   *como* a pergunta chega no servidor; quem responde continua sendo o mesmo
   motor/catálogo do ACRCloud, que no teste "sujo" acima teve precisão pior
   que a AudD. Investir na ponte nativa antes de saber se o motor do
   ACRCloud é preciso o suficiente isoladamente seria otimizar a coisa errada.

**Status:** correção das durações crescentes aplicada e em produção
(14/ago/2026). Diagnóstico temporário (`Settings.debug_save_failed_listen_audio`,
salvava áudio de tentativas sem resultado pra comparação) já desligado —
cumpriu o papel.

**Se o tema voltar (sintoma persistir mesmo com durações crescentes, ou
quiser ir além):**
1. Checar a métrica real (`GET /v1/debug/identify-stats?mode=listen`) depois
   de alguns dias de uso — confirmar com número se 6s/18s resolveu de
   verdade, não só nesse teste pontual.
2. ~~Se quiser testar o ACRCloud de forma justa: precisa de um projeto
   separado...~~ **CORRIGIDO (14/ago/2026):** não precisava de projeto
   novo nem plano pago — o projeto único da conta trial tem um campo
   "Audio Engine" no painel do ACRCloud com 3 opções (Audio
   Fingerprinting / Fingerprinting + Humming combinado / só Humming) e
   estava configurado em **"só Cover Song (Humming) Identification"**,
   sem Fingerprinting nenhum ligado. Trocado pra "Audio Fingerprinting &
   Cover Song (Humming) Identification" (o combinado) no painel deles —
   resolveu na hora, ver §4.5.
3. Só depois de confirmar que o motor do ACRCloud é preciso o suficiente
   isoladamente, vale considerar o investimento na ponte nativa do SDK
   on-device (item anterior) pra também ganhar velocidade — nesse ponto já
   resolveria precisão (durações maiores) e velocidade (fingerprint local)
   juntos.

### 4.4 Investigação (pausada) — foco de áudio / prioridade do microfone

Usuário notou algo real e reprodutível (14/ago/2026): tentar gravar a tela
com o Gravador de Tela nativo (opção "Mídia e microfone") enquanto o Shazam
ou o Gravador de Voz nativo estavam com o microfone aberto disparava o
aviso do Android "Microfone em uso. Altere a configuração de som ou pare de
usar o microfone." — o mesmo teste com o Salabim gravando **não disparou
esse aviso**. Hipótese levantada: o Salabim estaria usando o microfone de
um jeito que o Android trata com prioridade/exclusividade menor que Shazam
e o gravador nativo.

**Investigado, causa técnica provável encontrada, correção NÃO
implementada (decisão explícita — ver "Status" abaixo):**

- Não dá pra confirmar o que o Shazam usa por dentro (código fechado).
- Pesquisa na documentação oficial do Android indica que `AudioSource.DEFAULT`
  (o que o Salabim usa hoje, via `AndroidRecordConfig()` padrão) e
  `AudioSource.MIC` são **praticamente equivalentes** — trocar de um pro
  outro não deveria mudar o comportamento observado.
- A causa mais provável, olhando o código-fonte do pacote `record`
  (`AudioSessionManager.kt`): ele pede foco de áudio ao Android (via
  `AudioFocusRequest`), mas com `setAcceptsDelayedFocusGain(true)` — um
  pedido "educado", que aceita esperar a vez, ao contrário de um pedido de
  foco exclusivo. É bem plausível que seja essa a diferença de
  comportamento que o gravador de tela detectou.
- **Esse comportamento está fixo dentro do código nativo (Kotlin) do
  próprio pacote `record`** — não é algo configurável pela API que o
  Flutter/Dart expõe. Corrigir de verdade exigiria fazer fork/remendar o
  plugin Android (mexer em Kotlin nativo) ou escrever uma implementação
  nativa própria só pra essa parte — investimento de engenharia parecido
  em escala com a ponte nativa do SDK do ACRCloud (§4.3), não um ajuste de
  configuração.

**Isso afeta o SINAL captado?** Só quando existe disputa de verdade por
outro app usando o microfone ao mesmo tempo. Segundo a documentação do
Android, quando duas capturas concorrem, o sistema não bloqueia a de
prioridade menor — ele **silencia** o áudio que chega pra ela (silêncio de
verdade, não só mais baixo). Sem outro app disputando o microfone ao mesmo
tempo (o caso normal de uso/teste do Salabim sozinho), não tem disputa pra
resolver — o sinal captado deveria ser o mesmo independente da prioridade
de foco. Ou seja: **provavelmente não é a causa principal do "precisa
chegar perto"** nos testes normais, mas é um risco real e separado pra
guardar — se um dia outro processo de áudio rodar em paralelo (assistente
de voz sempre ouvindo em segundo plano, por exemplo), isso pode causar
falhas "silenciosas" de verdade (áudio zerado, não só de baixa qualidade).

**Status:** pausado a pedido do usuário — não implementado agora.
Retomar só se: (a) suspeitar de conflito real de microfone em produção
(ex: usuário relata falha consistente com algum assistente de voz ou app
de gravação ativo em paralelo), ou (b) o investimento na ponte nativa do
SDK do ACRCloud (§4.3) for adiante — nesse caso, a mesma ponte nativa
poderia resolver os dois problemas juntos (fingerprint local + foco de
áudio mais assertivo).

### 4.5 Ponte nativa Android pro SDK on-device do ACRCloud (14/ago/2026, EM TESTE)

Branch `feature/acrcloud-native-sdk` (não mergeada no `main`, não publicada
na Play Store — build debug local + `flutter install`/sideload pra
iteração rápida). Objetivo: resolver §4.3 (velocidade — fingerprint
calculado no aparelho, sem upload) e §4.4 (foco de microfone) de uma vez,
usando o `ACRCloudUniversalSDK` (jar + `.so` por ABI, `app/libs/` e
`app/src/main/jniLibs/`) via `MethodChannel`/`EventChannel` custom
(`AcrCloudBridge.kt` + `MainActivity.kt`) em vez do pacote `record`.

**Confirmado funcionando:**
- Fingerprint on-device + consulta ao ACRCloud, ponta a ponta, com capa/
  preview/links completando via `POST /v1/identify/enrich` (novo endpoint,
  reaproveita `_enrich_with_itunes`/`_resolve_platform_links`).
- O aviso "Microfone em uso" do Android **passou a aparecer** com esse
  caminho (não aparecia com o pacote `record`, ver §4.4) — confirma que o
  pedido de foco de áudio nativo é mais parecido com o do Shazam.
- Amostra pequena (9 tentativas, várias músicas, 14/ago/2026): ~6-7 de 9
  corretas. Não é 100%, mas nenhuma duração é "segura" mesmo — consistente
  com a lição do §4.3.

**Bugs reais encontrados e corrigidos nesse teste (não são do SDK em si,
são do nosso código de ponte):**
1. `_recordAndSearchListenNative` pulava `AudioRecorderService.hasPermission()`
   — numa instalação nova, o SDK falhava calado (`AudioRecord` status -1,
   sem nunca pedir a permissão pro usuário). Corrigido: pede a permissão
   antes, igual ao caminho REST.
2. `parseResult()` só olhava `metadata.music[]` — esse projeto (motor
   combinado, mesmo do Cantar) às vezes devolve o match em
   `metadata.humming[]` mesmo pra áudio tocado (não cantarolado).
   Corrigido: checa os dois.

**Testado e revertido (não usar de novo sem dado novo que justifique):**
- `recorderConfig.recordOnceMaxTimeMS` reduzido de 12000 (padrão do SDK,
  não documentado — achado inspecionando o `.jar`) pra 6000: piorou,
  voltou a acertar errado com confiança. Esse caminho não tem o mecanismo
  de concordância entre tentativas que o REST tem (§4.3), então fica mais
  exposto a esse risco já mapeado.
- **Streaming progressivo** ("fotos" a cada 2s via `acrcloudRecordDataListener`
  + `ACRCloudClient.recognize()` manual num client separado, aceitando só
  se concordar com alguma tentativa anterior da sessão — mesma regra do
  `_listenCandidates` do REST): implementado e testado, **piorou muito**
  (de ~2/3 pra ~1/6 de acerto no resultado final). A checagem manual
  nunca achou nada sozinha (sempre `found=false`, até com 11s
  acumulados), e o resultado "oficial" dos 12s também piorou — hipótese:
  rodar um segundo `ACRCloudClient` + o gancho de cópia de áudio em
  paralelo disputa recurso com a captura/fingerprint principal e degrada
  a qualidade do sinal. Revertido pro commit `5aeade6`. Mesma categoria
  de risco que a tentativa de streaming contínuo do lado REST (§4.3) —
  **captura de áudio + processamento em paralelo, nesse projeto, parece
  degradar a qualidade de forma difícil de prever sem testar no aparelho
  real toda vez.**

**Causa raiz encontrada pra taxa de acerto ruim em condições difíceis
(14/ago/2026):** teste comparativo direto contra o Shazam, mesmas
condições (volume baixo, janela aberta, ventilador ligado) — Shazam
acertava tudo, a ponte nativa errava quase tudo, sempre via
`metadata.humming[]`. Causa: o projeto do ACRCloud (painel deles, campo
"Audio Engine") estava configurado em **só "Cover Song (Humming)
Identification"** — o Fingerprinting (algoritmo tipo Shazam, robusto a
ruído) nunca chegou a rodar pra áudio tocado, só o motor de melodia
(sensível a ruído por natureza). Trocado no painel pra **"Audio
Fingerprinting & Cover Song (Humming) Identification"** (existe no mesmo
projeto, sem precisar de conta nova nem plano pago — não era limitação
da conta trial como se pensava antes, ver correção em §4.3). Resultado
imediato: resultado passou a vir de `metadata.music[]` (fingerprinting de
verdade) e acertou no mesmo teste difícil que antes errava sistematicamente.

**Status:** correção do motor aplicada e confirmada num primeiro teste
real; validando com mais rodadas antes de decidir merge pro `main`. Sem plano
de reduzir os 12s de novo ou tentar streaming de novo sem uma ideia
estruturalmente diferente (não só "cópia em paralelo").

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
