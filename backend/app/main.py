"""Ponto de entrada da API do Salabim."""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from app.api import routes_feedback, routes_health, routes_history, routes_identify, routes_search
from app.config import get_settings

settings = get_settings()

app = FastAPI(
    title="Salabim API",
    description="Backend de reconhecimento musical: fingerprint (Shazam-style) + humming/singing (Hum to Search).",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(routes_health.router)
app.include_router(routes_identify.router)
app.include_router(routes_search.router)
app.include_router(routes_history.router)
app.include_router(routes_feedback.router)

# Só ativa se APK_DOWNLOADS_DIR estiver setado no .env — usado pra distribuir
# o APK de debug pra testers via um túnel, sem precisar de um segundo servidor.
#
# Rota dedicada em vez de StaticFiles: o registro de tipos MIME do Windows
# não tem ".apk" cadastrado, então o guess automático do StaticFiles mandava
# "Content-Type: text/plain" pra um binário de 180MB — o navegador não
# reconhecia como app pra instalar e tentava tratar como texto/arquivo
# genérico. Aqui o media_type é sempre explícito e correto.
@app.get("/downloads/{filename}")
async def download_apk(filename: str) -> FileResponse:
    if not settings.apk_downloads_dir:
        raise HTTPException(404)
    file_path = Path(settings.apk_downloads_dir) / filename
    if not file_path.is_file() or file_path.parent != Path(settings.apk_downloads_dir):
        raise HTTPException(404)
    media_type = "application/vnd.android.package-archive" if filename.endswith(".apk") else "application/octet-stream"
    return FileResponse(file_path, media_type=media_type, filename=filename)


@app.get("/")
async def root() -> dict:
    return {"app": "Salabim", "status": "online", "docs": "/docs"}
