# agents_srvr

Docker Compose stack for a conversational automation environment. Runs **n8n** (workflow automation) with a **PostgreSQL** database and **Redis** queue, alongside **WAHA** and **Evolution API** as WhatsApp bridges. All configuration is driven by a single `.env` file.

> **Architecture note:** This stack is designed for **ARM64 (e.g. Raspberry Pi 4)** by default. The WAHA image is `devlikeapro/waha:arm`. If running on amd64, change `WAHA_IMAGE` to `devlikeapro/waha:latest`.

---

## Services

| Service | Description | Default host port |
|---|---|---|
| `postgres` | PostgreSQL 17 database | `54322` |
| `redis` | Redis 7 (queue + cache) | `6379` |
| `n8n` | Workflow automation (main) | `5678` |
| `n8n-worker` | n8n queue worker | — |
| `n8n-runner` | Task runner sidecar (JS/Python Code node) | — |
| `waha` | WhatsApp bridge (WAHA) | `3510` |
| `evolution` | WhatsApp bridge (Evolution API) | `8480` |

All services communicate on the Docker network `HoloNet` (external, must be created before starting).

---

## Prerequisites

- Docker Engine + Docker Compose v2
- External Docker network created (see step 1)
- Persistent data directories created on the host (see step 3)
- PostgreSQL init script copied to the host (see step 4)

---

## Setup — complete step by step

### 1. Create the Docker network

```bash
docker network create HoloNet
```

### 2. Copy and fill in the environment file

```bash
cp .env.example .env
```

Edit `.env` and set all values. Key variables:

| Variable | Description |
|---|---|
| `HOST_BASE` | Base path on the host for all persistent data (e.g. `/home/user/docker`) |
| `N8N_HOST` | IP or domain of the server — used for webhooks and WAHA callback |
| `N8N_ENCRYPTION_KEY` | Long random string to encrypt n8n credentials |
| `N8N_RUNNERS_AUTH_TOKEN` | Shared secret between n8n/worker and the runner container |
| `POSTGRES_PASSWORD` | Root PostgreSQL password |
| `POSTGRES_NON_ROOT_PASSWORD` | Password for the app user (`n8n_user`) |
| `REDIS_PASSWORD` | Redis password |
| `WAHA_API_KEY` | API key for WAHA |
| `AUTHENTICATION_API_KEY` | API key for Evolution API |

### 3. Create host directories

```bash
export HOST_BASE=/home/user/docker   # same value as in .env

mkdir -p \
  ${HOST_BASE}/postgres/data \
  ${HOST_BASE}/postgres \
  ${HOST_BASE}/n8n \
  ${HOST_BASE}/redis \
  ${HOST_BASE}/waha/sessions \
  ${HOST_BASE}/waha/media \
  ${HOST_BASE}/evolution/instances
```

### 4. Copy the PostgreSQL init script

The init script runs **once on first boot** of the Postgres container (only when the data volume is empty). It creates the `n8n_user` and the dedicated `evolution` database.

```bash
cp init/init-data.sh ${HOST_BASE}/postgres/init-data.sh
chmod +x ${HOST_BASE}/postgres/init-data.sh
```

> **If the file was cloned or edited on Windows**, strip CRLF line endings or the script will fail with a `syntax error: unexpected end of file`:
> ```bash
> sed -i 's/\r//' ${HOST_BASE}/postgres/init-data.sh
> ```

> **Important:** If the Postgres data volume already exists (i.e. you already ran the stack once), the init script will NOT run again. In that case, skip to [Manual database setup](#manual-database-setup-existing-volume).

### 5. Deploy the stack

**Option A — Docker Compose (direct, from repo root):**
```bash
docker compose up -d
```

**Option B — Portainer Stack:**

> Portainer stacks have no working directory context, so relative paths (`./init/...`) do not work. All bind-mount paths in `.env` must be **absolute paths that already exist on the host**.

1. Complete steps 1–4 above on the host server.
2. In Portainer → Stacks → Add stack:
   - Choose **Repository** (point to this repo) or **Web editor** (paste `docker-compose.yml`).
   - Under **Environment variables**, load your `.env` or enter variables manually.
3. Deploy the stack.

### 6. Verify all services are healthy

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

All containers should show `healthy` or `Up` after their respective start periods.

---

## Manual database setup (existing volume)

If the Postgres data volume already exists, the init script is skipped. Run these commands manually after Postgres is running:

```bash
# Create the n8n app user
docker exec -it postgres psql -U postgres -c "
  CREATE USER n8n_user WITH PASSWORD 'your_POSTGRES_NON_ROOT_PASSWORD';
  GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;
"
docker exec -it postgres psql -U postgres -d n8n -c "
  GRANT CREATE ON SCHEMA public TO n8n_user;
"

# Create the dedicated Evolution database
docker exec -it postgres psql -U postgres -c "
  CREATE DATABASE evolution OWNER n8n_user;
  GRANT ALL PRIVILEGES ON DATABASE evolution TO n8n_user;
"
docker exec -it postgres psql -U postgres -d evolution -c "
  GRANT ALL PRIVILEGES ON SCHEMA public TO n8n_user;
"
```

Then restart Evolution so Prisma can apply its migrations to the empty database:

```bash
docker restart evolution
```

---

## Webhooks / external access

`N8N_HOST` controls the URLs used for n8n webhooks and the WAHA callback. Set it to the server's IP or domain:

```dotenv
N8N_HOST=192.168.1.100   # or: n8n.mydomain.com
```

If using HTTPS:
```dotenv
N8N_PROTOCOL=https
N8N_SECURE_COOKIE=true
```

---

## Task runner (n8n-runner)

The `n8n-runner` sidecar executes JavaScript and Python code from the Code node in external mode (isolated, recommended for production).

The task broker runs inside the **main `n8n` container** (not `n8n-worker`). The runner connects to it via `N8N_RUNNERS_TASK_BROKER_URI`, which defaults to `http://n8n:5679`.

The runner image version must match the n8n image version. If you pin a specific version, update both:

```dotenv
N8N_IMAGE=docker.n8n.io/n8nio/n8n:1.85.0
N8N_RUNNERS_IMAGE=n8nio/runners:1.85.0
```

---

## Architecture notes

- **WAHA on ARM64 (Raspberry Pi):** uses `devlikeapro/waha:arm`. For amd64, change to `devlikeapro/waha:latest`.
- **Evolution database:** Evolution API uses a **dedicated `evolution` database** (controlled by `EVOLUTION_DB`), separate from the `n8n` database. This avoids Prisma migration conflicts (`P3005: database schema is not empty`).
- **`n8n_user`** has access to both `n8n` and `evolution` databases.
- **Connection URIs built automatically:** `DATABASE_CONNECTION_URI` (Evolution → Postgres) and `CACHE_REDIS_URI` (Evolution → Redis) are constructed in `docker-compose.yml` from existing variables (`POSTGRES_NON_ROOT_USER`, `POSTGRES_NON_ROOT_PASSWORD`, `REDIS_PASSWORD`). Changing a password in `.env` automatically updates the URI — no manual sync needed.

---

## Healthchecks

Every service has a healthcheck. All intervals and timeouts are configurable via `HC_*` variables in `.env`. Per-service overrides (e.g. `HC_INTERVAL_POSTGRES`) take precedence over global defaults.
