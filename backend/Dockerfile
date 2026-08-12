FROM python:3.12-slim

WORKDIR /srv

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ffmpeg: binário exigido pelo Whisper (transcrição do modo Cantar) — não é
# um pacote pip, precisa estar instalado no sistema. Sem isso o container
# sobe normalmente mas a transcrição falha silenciosamente em produção
# (só não dava problema local porque o ffmpeg tava instalado direto no
# Windows do ambiente de dev).
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic.ini ./alembic.ini
COPY migrations ./migrations

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/v1/health').raise_for_status()"

# 1 worker só: cada worker é um processo separado que carrega os modelos do
# Whisper na própria memória — com 2+ workers isso dobra o uso de RAM (torch
# + modelo "tiny"/"base" já pesam bastante sozinhos), o que estoura o limite
# do tier gratuito do Render (512MB). Reavaliar quando escalar pra um plano
# com mais RAM.
#
# Forma shell (não array) de propósito: o Render injeta a porta certa via
# variável de ambiente PORT e exige que a gente escute nela — $PORT só é
# expandido em forma shell. Localhost/docker-compose sem essa variável
# cai no padrão 8000.
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1
