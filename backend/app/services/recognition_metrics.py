"""Métricas de reconhecimento — quanto tempo cada tentativa leva e se achou,
por modo/provedor.

Motivação (14/ago/2026): depois de trocar configuração várias vezes (ganho,
provedor, fonte de áudio) só comparando "parece que melhorou/piorou" de
teste manual no celular, ficou claro que precisamos de número de verdade
pra continuar. Cada tentativa de identify grava um evento estruturado — no
log (inspecionável na hora via `docker logs`) e numa lista no Redis
(inspecionável depois, pra tirar média de latência/taxa de acerto por
provedor sem precisar garimpar log).

De propósito simples (sem tabela no Postgres, sem dashboard): o volume aqui
é de teste manual, não de produção em escala — Redis + log já dá o
suficiente pra comparar duas configurações lado a lado.
"""
from __future__ import annotations

import json
import logging
import time
from collections import Counter
from contextlib import asynccontextmanager

from app.core.cache import get_redis

logger = logging.getLogger("salabim.recognition")

_METRICS_KEY = "salabim:metrics:identify"
_METRICS_MAX_LEN = 2000  # generoso pro volume de teste manual, sem crescer sem limite
_METRICS_TTL_SECONDS = 60 * 60 * 24 * 30  # 30 dias — não precisa sobreviver pra sempre

# Sessão do Ouvir de ponta a ponta (client-side) — ver
# record_listen_session abaixo pro motivo de existir separado do resto
# desse arquivo.
_SESSION_METRICS_KEY = "salabim:metrics:listen_session"


async def record_identify_attempt(
    *, mode: str, provider: str, elapsed_ms: int, found: bool, match_confidence: float | None = None,
) -> None:
    event = {
        "ts": time.time(),
        "mode": mode,
        "provider": provider,
        "elapsed_ms": elapsed_ms,
        "found": found,
        "match_confidence": match_confidence,
    }
    # Log estruturado: dá pra ver na hora com `docker logs salabim | grep identify_attempt`.
    logger.info("identify_attempt %s", json.dumps(event))
    try:
        r = get_redis()
        await r.lpush(_METRICS_KEY, json.dumps(event))
        await r.ltrim(_METRICS_KEY, 0, _METRICS_MAX_LEN - 1)
        await r.expire(_METRICS_KEY, _METRICS_TTL_SECONDS)
    except Exception:
        # Métrica é só observabilidade — nunca deve derrubar uma busca real
        # por causa de um problema no Redis.
        logger.warning("Falha ao gravar métrica de identify no Redis.", exc_info=True)


@asynccontextmanager
async def timed_attempt(*, mode: str, provider: str):
    """Cronometra o bloco e grava a métrica ao sair dele. Quem usa escreve
    em `result["found"]` (e opcionalmente `result["match_confidence"]`)
    dentro do bloco, antes de terminar — ver identify_from_audio."""
    start = time.perf_counter()
    result: dict = {"found": False, "match_confidence": None}
    try:
        yield result
    finally:
        elapsed_ms = int((time.perf_counter() - start) * 1000)
        await record_identify_attempt(
            mode=mode,
            provider=provider,
            elapsed_ms=elapsed_ms,
            found=bool(result.get("found", False)),
            match_confidence=result.get("match_confidence"),
        )


async def recent_stats(*, mode: str | None = None, provider: str | None = None, limit: int = 500) -> dict:
    """Resumo rápido (contagem, taxa de acerto, latência média/p50/p95) dos
    últimos eventos gravados, com filtro opcional por modo/provedor — usado
    pelo endpoint de debug (ver app/api/routes_health.py) pra comparar
    configurações sem precisar abrir o Redis na mão."""
    r = get_redis()
    raw_events = await r.lrange(_METRICS_KEY, 0, limit - 1)
    events = [json.loads(e) for e in raw_events]
    if mode:
        events = [e for e in events if e.get("mode") == mode]
    if provider:
        events = [e for e in events if e.get("provider") == provider]

    if not events:
        return {"count": 0}

    latencies = sorted(e["elapsed_ms"] for e in events)
    found_count = sum(1 for e in events if e.get("found"))

    def _percentile(p: float) -> int:
        idx = min(len(latencies) - 1, int(len(latencies) * p))
        return latencies[idx]

    return {
        "count": len(events),
        "found_rate": round(found_count / len(events), 3),
        "latency_ms": {
            "avg": round(sum(latencies) / len(latencies)),
            "p50": _percentile(0.50),
            "p95": _percentile(0.95),
            "min": latencies[0],
            "max": latencies[-1],
        },
    }


async def record_listen_session(*, outcome: str, attempts: int, total_ms: int) -> None:
    """Sessão do Ouvir de ponta a ponta, medida no CLIENTE (mobile) — desde
    o toque no botão até o resultado final (achou/não achou/erro/
    cancelado). Complementa `record_identify_attempt` acima: aquele só
    mede a chamada à AudD (tipicamente <1s); o tempo que o usuário
    realmente sente é dominado pelo tempo de GRAVAÇÃO entre tentativas até
    duas concordarem (ver ARCHITECTURE.md §4.3), que é inteiramente
    client-side e nunca aparecia em nenhuma métrica antes. Existe pra
    decidir com dado real (quantas tentativas cada busca real precisa até
    confirmar, distribuição de tempo total) onde apertar o cronograma de
    `_listenSegmentDurations` no app, em vez de ajustar às cegas de novo."""
    event = {"ts": time.time(), "outcome": outcome, "attempts": attempts, "total_ms": total_ms}
    logger.info("listen_session %s", json.dumps(event))
    try:
        r = get_redis()
        await r.lpush(_SESSION_METRICS_KEY, json.dumps(event))
        await r.ltrim(_SESSION_METRICS_KEY, 0, _METRICS_MAX_LEN - 1)
        await r.expire(_SESSION_METRICS_KEY, _METRICS_TTL_SECONDS)
    except Exception:
        logger.warning("Falha ao gravar métrica de sessão do Ouvir no Redis.", exc_info=True)


async def recent_listen_session_stats(*, outcome: str | None = None, limit: int = 500) -> dict:
    """Agrega as sessões do Ouvir recentes: contagem por desfecho,
    histograma de quantas tentativas cada uma levou, e tempo total
    médio/p50/p95 — usado pelo endpoint de debug pra decidir onde apertar
    o cronograma de tentativas sem precisar reconstruir teste manual toda
    vez."""
    r = get_redis()
    raw_events = await r.lrange(_SESSION_METRICS_KEY, 0, limit - 1)
    events = [json.loads(e) for e in raw_events]
    if outcome:
        events = [e for e in events if e.get("outcome") == outcome]

    if not events:
        return {"count": 0}

    total_ms_list = sorted(e["total_ms"] for e in events)

    def _percentile(p: float) -> int:
        idx = min(len(total_ms_list) - 1, int(len(total_ms_list) * p))
        return total_ms_list[idx]

    return {
        "count": len(events),
        "by_outcome": dict(Counter(e.get("outcome") for e in events)),
        "attempts_histogram": dict(sorted(Counter(e.get("attempts") for e in events).items())),
        "total_ms": {
            "avg": round(sum(total_ms_list) / len(total_ms_list)),
            "p50": _percentile(0.50),
            "p95": _percentile(0.95),
            "min": total_ms_list[0],
            "max": total_ms_list[-1],
        },
    }
