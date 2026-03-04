# agents_srvr

Docker Compose stack for a conversational automation environment. Runs **n8n** (workflow automation) with a **PostgreSQL** database and **Redis** queue, alongside **WAHA** and **Evolution API** as WhatsApp bridges. All configuration is driven by a single `.env` file.

---

## Services

| Service | Description | Default host port |
|---|---|---|
| `postgres` | PostgreSQL 17 database | `54322` |
| `redis` | Redis 7 (queue + cache) | `6379` |
| `n8n` | Workflow automation (main) | `5678` |
| `n8n-worker` | n8n queue worker | — |
| `waha` | WhatsApp bridge (WAHA) | `3510` |
| `evolution` | WhatsApp bridge (Evolution API) | `8480` |

All services communicate on the Docker network `HoloNet` (external, must be created before starting).

---

## Prerequisites

- Docker Engine + Docker Compose v2
- The external Docker network must exist:
  ```bash
  docker network create HoloNet
  ```
- Persistent data directories created on the host (see [Host directories](#host-directories))
- The PostgreSQL init script copied to the host (see [Database initialization](#database-initialization))

---

## Setup

### 1. Copy and fill in the environment file

```bash
cp .env.example .env
```

Edit `.env` and replace every `REPLACE_WITH_*` value with strong passwords/keys. Key variables:

| Variable | Description |
|---|---|
| `HOST_BASE` | Base path on the host for all persistent data (e.g. `/home/user/docker`) |
| `N8N_HOST` | IP or domain of the server — used for webhooks. Set to the **external/public** address in production. |
| `N8N_ENCRYPTION_KEY` | Long random string used to encrypt n8n credentials |
| `POSTGRES_PASSWORD` | Root PostgreSQL password |
| `POSTGRES_NON_ROOT_PASSWORD` | Password for the application user (`n8n_user`) |
| `REDIS_PASSWORD` | Redis password |

### 2. Create host directories

```bash
export HOST_BASE=/home/user/docker   # same value as in .env

mkdir -p \
  ${HOST_BASE}/postgres/data \
  ${HOST_BASE}/n8n \
  ${HOST_BASE}/redis \
  ${HOST_BASE}/waha/sessions \
  ${HOST_BASE}/waha/media \
  ${HOST_BASE}/evolution/instances
```

### 3. Database initialization

The PostgreSQL container runs `init-data.sh` on **first boot** to create the non-root application user (`n8n_user`). This script must be present on the host **before** starting the stack.

Copy it to the path defined by `HOST_INIT_DB_SCRIPT` (default: `${HOST_BASE}/postgres/init-data.sh`):

```bash
cp init/init-data.sh ${HOST_BASE}/postgres/init-data.sh
chmod +x ${HOST_BASE}/postgres/init-data.sh
```

> **Important:** this script only runs on the very first container start, when the data volume is empty. If the volume already exists, it is skipped automatically by PostgreSQL.

#### Alternative — run the SQL manually

If you prefer not to use the init script (e.g. the volume already exists), you can create the user manually after the database is running:

```bash
docker exec -it postgres psql -U postgres -d n8n -c "
  CREATE USER n8n_user WITH PASSWORD 'your_password';
  GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;
  GRANT CREATE ON SCHEMA public TO n8n_user;
"
```

---

## Deployment

### Option A — Docker Compose (direct)

```bash
docker compose up -d
```

### Option B — Portainer Stack

> **Note:** Portainer stacks do not have a working directory context, so **relative paths like `./init/init-data.sh` will not work**. All bind-mount paths in `.env` must be **absolute** paths that already exist on the host.

1. Complete steps 1–3 above on the host server.
2. In Portainer → Stacks → Add stack:
   - Choose **Repository** (point to this repo) or **Web editor** (paste the `docker-compose.yml` content).
   - Under **Environment variables**, load your `.env` file or enter the variables manually.
3. Deploy the stack.

---

## Network

The stack uses an **external** Docker network named `HoloNet` (configurable via `NETWORK_NAME`). It must be created before deploying:

```bash
docker network create HoloNet
```

If you change `NETWORK_NAME` in `.env`, update the `networks` section in `docker-compose.yml` accordingly (Compose does not interpolate network names there).

---

## Webhooks / external access

`N8N_HOST` controls the URLs used for n8n webhooks and the WAHA callback. In production, set it to the server's public IP or domain:

```dotenv
N8N_HOST=192.168.1.100   # or: n8n.mydomain.com
```

If using HTTPS, also set:
```dotenv
N8N_PROTOCOL=https
N8N_SECURE_COOKIE=true
```

---

## Healthchecks

Every service has a healthcheck. Intervals and timeouts are fully configurable via `HC_*` variables in `.env`. Per-service overrides (e.g. `HC_INTERVAL_POSTGRES`) take precedence over the global defaults.
