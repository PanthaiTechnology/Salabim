"""Ponto de entrada da API do Salabim."""
from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api import routes_health, routes_history, routes_identify, routes_search
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

# Só ativa se APK_DOWNLOADS_DIR estiver setado no .env — usado pra distribuir
# o APK de debug pra testers via um túnel, sem precisar de um segundo servidor.
if settings.apk_downloads_dir and Path(settings.apk_downloads_dir).is_dir():
    app.mount("/downloads", StaticFiles(directory=settings.apk_downloads_dir), name="downloads")


@app.get("/")
async def root() -> dict:
    return {"app": "Salabim", "status": "online", "docs": "/docs"}
