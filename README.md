# Salabim 🎵

Shazam + "Hum to Search" (Google) em um único app: grave a música tocando,
cante, cantarole, assobie, toque num instrumento, ou busque por um trecho da
letra — o Salabim identifica a faixa e mostra um preview com links diretos
para Spotify, Apple Music, Deezer, Tidal e YouTube Music.

Leia primeiro: [ARCHITECTURE.md](ARCHITECTURE.md) (como tudo se conecta) e
[STORE_PUBLISHING.md](STORE_PUBLISHING.md) (checklist para publicar nas lojas).

## Estrutura do repositório

```
salabim/
  mobile/     Flutter (iOS + Android) — ver mobile/README.md
  backend/    FastAPI (Python) — orquestra AudD, ACRCloud, Odesli, Musixmatch
  devops/     Fastlane (release automation)
  docs/       Contrato da API
  .github/    CI (GitHub Actions) para backend e mobile
```

## Rodando tudo localmente

### 1. Backend

Pré-requisito extra: **ffmpeg** instalado no sistema (não é um pacote pip) —
usado pela transcrição de voz (Whisper) do modo Cantar. No Windows:
`winget install Gyan.FFmpeg`. Sem ele, o modo Cantar ainda funciona (a
transcrição falha silenciosamente e cai de volta pro score de melodia puro).

```bash
cd backend
cp .env.example .env    # depois preencha com suas chaves reais (ver ARCHITECTURE.md §9)
python -m venv .venv
.venv\Scripts\activate  # Windows (PowerShell: .venv\Scripts\Activate.ps1)
pip install -r requirements.txt
docker compose up -d db cache   # sobe Postgres + Redis
alembic upgrade head            # aplica o schema no banco (após a 1ª migration)
uvicorn app.main:app --reload
```

API disponível em `http://localhost:8000/docs`. Sem as chaves da AudD/ACRCloud
no `.env`, o endpoint `/v1/identify` responde com erro claro dizendo qual
variável falta — o app builda e roda normalmente, só a identificação real
depende das chaves.

Rodar os testes: `pytest` (dentro de `backend/`, com o venv ativo).

### 2. Mobile

Veja o passo a passo completo em [mobile/README.md](mobile/README.md) — resumo:

```bash
cd mobile
flutter create . --project-name salabim --org com.salabim --platforms android,ios
flutter pub get
flutter run
```

### 3. Docker Compose (backend + Postgres + Redis de uma vez)

```bash
cd backend
docker compose up --build
```

## Status deste scaffold

✅ Arquitetura completa e documentada
✅ Backend com os 4 modos de busca implementados (ouvir, cantarolar, letra,
   descrição) integrados a AudD + ACRCloud + Odesli + Musixmatch
✅ App Flutter com as 4 telas principais e captura de áudio real
✅ CI (GitHub Actions), Docker, Fastlane
✅ Checklist de publicação nas lojas

⏳ Pendente de você (não pode ser feito por mim, ver seções específicas):
contratar AudD/ACRCloud/Odesli/Musixmatch, gerar `android/`/`ios/` com o
Flutter SDK instalado, registrar contas Apple/Google, identidade visual
final (ícone/splash), política de privacidade publicada, autenticação de
usuário completa (login está com placeholder no histórico).

## Próximos passos sugeridos

1. Instalar Flutter SDK e Python localmente, seguir os `README.md` de cada pasta
2. Criar conta AudD (grátis para testar) e colocar o token no `.env` — dá pra
   validar o modo "ouvir" ponta a ponta em minutos
3. Criar projeto tipo "Humming" no ACRCloud para o modo "cantarolar"
4. Implementar autenticação real (hoje o histórico/favoritos exigem um
   Bearer token que o app ainda não gera — falta a tela de login/signup)
