"""Ponto de entrada da API do Salabim."""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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


@app.get("/")
async def root() -> dict:
    return {"app": "Salabim", "status": "online", "docs": "/docs"}
