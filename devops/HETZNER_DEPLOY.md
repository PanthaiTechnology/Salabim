# Deploy em produção — Hetzner Cloud

Migrado do Render (tier gratuito, 512MB RAM) porque o modo Cantar
(Whisper + PyTorch) estourava memória em produção — ver commits de
"timeout modo Cantar" no histórico do git pra contexto completo.

## Infraestrutura

- **Servidor**: Hetzner Cloud, CX23 (2 vCPU, 4GB RAM, 40GB SSD) — Nuremberg
- **IP**: `46.224.213.188`
- **Domínio**: `46-224-213-188.nip.io` (serviço DNS gratuito que resolve
  pro próprio IP — evita precisar comprar um domínio só pra ter HTTPS
  válido; trocar por domínio próprio quando/se tiver um)
- **Custo**: ~$7,09/mês ($6,49 servidor + $0,60 IPv4)
- **Redis**: continua no Upstash (gratuito) — não precisou migrar, só o
  compute (API + Whisper) foi pro Hetzner
- **SSH**: chave dedicada em `~/.ssh/salabim_hetzner` (só nessa máquina
  de desenvolvimento — nunca comitada)

## Containers Docker

```
salabim-net (rede docker interna)
├── salabim   — API (build da própria pasta backend/, porta 8000 interna)
└── caddy     — reverse proxy com HTTPS automático (Let's Encrypt), portas 80/443
```

Caddyfile em `/srv/caddy/Caddyfile` no servidor:
```
46-224-213-188.nip.io {
    reverse_proxy salabim:8000
}
```

`.env` do backend em `/srv/salabim/backend/.env` no servidor (mesmas
chaves do `.env` local, `REDIS_URL` apontando pro Upstash,
`ENABLE_HUM_TRANSCRIPTION=true` — nessa hospedagem tem RAM de sobra,
diferente do Render).

## Deploy de atualizações

Sem CI/CD automático configurado ainda (era o "auto-deploy on commit"
que o Render tinha de graça). Pra atualizar depois de um `git push`:

```bash
ssh -i ~/.ssh/salabim_hetzner root@46.224.213.188
cd /srv/salabim && git pull
cd backend && docker build -t salabim-backend .
docker stop salabim && docker rm salabim
docker run -d --name salabim --restart unless-stopped --network salabim-net \
  --env-file .env salabim-backend
```

(Rodar `docker compose` num arquivo próprio é o próximo passo natural
pra simplificar isso — não feito ainda por tempo.)

## Render (mantido como estava, não desligado)

O serviço no Render (`https://salabim.onrender.com`) continua existindo
e funcionando — não foi desativado, só parou de ser o backend "oficial"
que o app aponta. Serve como fallback manual se o Hetzner cair; não
custa nada mantê-lo parado no plano gratuito.
