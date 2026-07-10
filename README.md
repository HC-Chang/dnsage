# DNSage

> ML-powered Pi-hole ad blocking system that gets smarter over time.

A Docker Compose-based network-wide ad blocker combining **Pi-hole (DNS sinkhole)** with **Donut-Hole (ML classification)**. Uses a local Ollama LLM to automatically analyze DNS queries, build blocklists, and improve with every classification.

## Description

DNSage automates DNS-based ad blocking by feeding Pi-hole's query log into a local LLM pipeline. Each unclassified domain is analyzed by `llama3.2` (ad/tracker/legit), embedded into a vector database via `all-minilm`, and presented in a Web UI for review. Approved domains are exported as a Pi-hole blocklist — no cloud dependency, no manual rule writing.

## Architecture

```
User Devices → DNS Query → Pi-hole (DNS sinkhole)
                                │
                    Match blocklist → hit → 0.0.0.0 (blocked)
                                │ miss
                                └→ Upstream DNS → Real IP
                                │
                    (every 5 min) Donut-Hole
                        ├─ Fetch new domains from Pi-hole API
                        ├─ llama3.2 classification (ad/tracker/legit)
                        ├─ all-minilm embedding + similarity matching
                        └─ Web UI review → export blocklist → Pi-hole
```

## Services

| Container | Role | Port |
|-----------|------|------|
| `pihole` | DNS sinkhole + ad blocking | `:53` (DNS), `:80` (Web) |
| `donut-hole-postgres` | PostgreSQL + pgvector | `127.0.0.1:5432` |
| `donut-hole-backend` | FastAPI classification engine | internal `:8343` |
| `donut-hole-frontend` | SvelteKit review UI | `:5174` |
| `ollama` (existing) | LLM (llama3.2 + all-minilm) | `:11434` |

## Prerequisites

- Docker + Docker Compose
- A running Ollama instance with these models pulled:
  - `llama3.2` — domain classification
  - `all-minilm:33m` — vector embeddings

## Directory Layout

```
dnsage/
├── docker-compose.yml    # Main Compose definition
├── .env.example          # Sanitized env template
├── .gitignore
├── Makefile              # Commands: setup / pi-hole / clean
├── LICENSE               # MIT
├── README.md
├── .gitmodules           # Git submodule definition
└── donut-hole/           # Donut-Hole source (git submodule)
    ├── backend/          # FastAPI backend
    ├── frontend/         # SvelteKit frontend
    └── postgres/         # DB init scripts
```

## Quick Start

### One-command setup

```bash
make setup
```

`make setup` will:
1. Check Docker + Docker Compose
2. Generate `.env` from `.env.example` (with random secrets)
3. Create the Ollama external network if missing
4. Initialize the `donut-hole` submodule
5. Start all services

### Manual steps

```bash
# 1. Verify Ollama models are ready
docker exec ollama ollama list | grep -E "llama3.2|all-minilm"

# 2. Start all services
docker compose up -d

# 3. Check health
docker compose ps

# 4. Point your router's DHCP DNS to this host (e.g. 192.168.1.198)
```

On first boot, Pi-hole automatically downloads the StevenBlack blocklist (~84k domains) and runs gravity update.

## Login Info

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| Pi-hole Admin | `http://<host-ip>:80/admin/` | — | See `PIHOLE_PASSWORD` in `.env` |
| Donut-Hole UI | `http://<host-ip>:5174/` | `admin` | See `ADMIN_PASSWORD` in `.env` |

## ML Pipeline

### Automation cycle

```
[Pi-hole accumulates DNS queries]
        ↓ (every 5 min)
[Donut-Hole fetches query log]
        ↓
[llama3.2 classifies unprocessed domains]
        ↓ (classification result)
[all-minilm generates vector embeddings]
        ↓
[Stored in PostgreSQL + pgvector]
        ↓
[Web UI pending review]
        ↓ (user Approve / Reject)
[Export hosts-format blocklist]
        ↓ (Pi-hole runs Update Gravity)
[Rules active, new domains blocked automatically]
```

### Learning curve

- **Early**: every new domain hits the LLM (~1-2 s/domain)
- **Mid**: vector similarity finds pre-classified domains → instant suggestion, no LLM needed
- **Mature**: 95%+ domains matched instantly; only occasional review of truly new domains

### Management commands

```bash
# Live logs
docker compose logs -f

# Specific service logs
docker compose logs backend -f

# Restart a single service
docker compose restart backend

# Restart everything
docker compose restart

# Stop and clean up
docker compose down

# Rebuild and start (after code changes)
docker compose build && docker compose up -d
```

## Configuration

### docker-compose.yml

- **pihole**: upstream DNS set to Quad9 + Cloudflare (`9.9.9.9;1.1.1.1`)
- **backend**: connects to Ollama via external network (`ollama_ollama-docker`)
- **frontend**: reverse-proxies to backend, exposed on `:5174`
- **pgadmin**: debug profile only (`--profile debug`)

Internal network: `dnsage-network` (bridge)

### .env

Copy `.env.example` to `.env` and edit. `make setup` does this automatically with random secrets.

| Variable | Purpose |
|----------|---------|
| `PIHOLE_PASSWORD` | Pi-hole web password |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `JWT_SECRET` | Donut-Hole JWT signing key |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Donut-Hole login |
| `CORS_ORIGINS` | Allowed frontend origins |
| `LLM_PROVIDER_CHAIN` | LLM provider order (`ollama`) |
| `LLM_MODELS` | Per-provider models (`{"ollama":"llama3.2"}`) |
| `EMBEDDING_PROVIDER` / `EMBEDDING_MODEL` | Embedding model (`ollama` / `all-minilm:33m`) |

## FAQ

### DNS lookup to `<host-ip>` times out?

The host machine cannot reach its own Docker-mapped DNS port via the external IP (hairpin NAT). Other devices on the same LAN work fine. For local testing use `dig @127.0.0.1`.

### Donut-Hole backend can't reach Pi-hole?

Make sure `PIHOLE_URL` is set to `http://pihole:80` (Docker internal network name), not an IP.

### Ollama connection failed?

Verify the `ollama_ollama-docker` external network exists:

```bash
docker network ls | grep ollama
```

If Ollama wasn't started via Docker Compose, update `OLLAMA_BASE_URL` in `docker-compose.yml` to the actual IP.

### How to reset Pi-hole password?

```bash
docker exec pihole pihole setpassword <new-password>
```

Then update `PIHOLE_PASSWORD` in `.env`.

## License

- **dnsage** (this project): MIT
- **Pi-hole**: AGPL-3.0
- **Donut-Hole**: MIT
