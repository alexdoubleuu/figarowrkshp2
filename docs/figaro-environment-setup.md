# Figaro Workshop – Environment Setup (Docker on Hetzner + aaPanel)

Server: Hetzner Cloud, 4 vCPU / 8 GB RAM, aaPanel installed.
Approach: **aaPanel = front door (domains, SSL, Nginx). Docker Compose = everything the app needs.**

---

## 1. Architecture

```
Internet
   │  443 (SSL by aaPanel / Let's Encrypt)
   ▼
aaPanel Nginx (host)
   ├── shopapi.<domain>  → reverse proxy → 127.0.0.1:8080  (Docker: app)
   │                                         ├── Laravel 13 API (for Vue storefront)
   │                                         ├── Filament 5 /admin  (管理員)
   │                                         └── Filament 5 /dealer (經銷商)
   └── wrkshp.<domain>   → static files /www/wwwroot/figaro-wrkshp (Vue 3 build, SPA)

Docker network (private, nothing exposed publicly):
   app (PHP 8.4 + Nginx) · queue · scheduler · postgres 17 · redis
   later: whatsapp (Node 24 + Baileys)
```

Key choices:
- **Customers never log in**, so the Vue site only calls public API endpoints. No Sanctum SPA auth needed; just CORS for `wrkshp.<domain>`.
- **Admin + 經銷商 live in Filament** on `shopapi.<domain>` (session login, separate panels). You can move admin to its own subdomain later.
- **Logo files stored on Laravel's private `local` disk** (not public), downloaded via Filament.
- **Container ports bound to 127.0.0.1 only.** Docker bypasses UFW, so never publish Postgres/Redis ports to 0.0.0.0.

### Versions

| Component | Version |
|---|---|
| Laravel | 13 |
| Filament | 5 (needs Livewire 4, Tailwind 4) |
| PHP | 8.4 (`serversideup/php:8.4-fpm-nginx`) |
| PostgreSQL | 17 (`postgres:17`) |
| Redis | 7 (`redis:7-alpine`) |
| Node | 24 LTS (Vue build, later Baileys) |
| Vue | 3 + Vite |

### Memory budget (8 GB)

| Service | Approx. |
|---|---|
| OS + aaPanel + host Nginx | ~0.8 GB |
| Postgres (shared_buffers 1 GB) | ~1.5 GB |
| app (php-fpm + nginx) | ~0.5–1 GB |
| queue + scheduler | ~0.3 GB |
| Redis | ~0.1 GB |
| Baileys (later) | ~0.3 GB |
| **Headroom** | **~4 GB** |

Plenty of room. If aaPanel's own MySQL/Redis/PHP aren't used by other sites, stop them to free RAM.

---

## 2. Repo layout (one monorepo)

```
figaro/
├── backend/              # Laravel 13 + Filament 5
├── frontend/             # Vue 3 + Vite storefront
├── docker/
│   └── php/Dockerfile
├── compose.yml           # production
├── compose.dev.yml       # local overrides (option B, full Docker)
├── .env.example          # copy to .env (never commit .env)
├── deploy.sh
└── backup.sh
```

---

## 3. Files

### docker/php/Dockerfile

```dockerfile
FROM serversideup/php:8.4-fpm-nginx AS base
USER root
# Filament needs intl; gd for image thumbnails of logo uploads; bcmath for money math
RUN install-php-extensions intl gd bcmath
USER www-data

FROM base AS development
# code is bind-mounted in dev; match www-data to your WSL user so
# files created by artisan/composer are owned by you, and storage/ is writable
USER root
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN docker-php-serversideup-set-id www-data $USER_ID:$GROUP_ID && \
    docker-php-serversideup-set-file-permissions --owner $USER_ID:$GROUP_ID
USER www-data

FROM base AS production
COPY --chown=www-data:www-data backend/ /var/www/html
RUN composer install --no-dev --optimize-autoloader --no-interaction
```

`.dockerignore` (repo root):

```
**/.env
backend/vendor
backend/node_modules
backend/storage/logs/*
frontend
.git
```

### compose.yml (production)

```yaml
name: figaro

x-app: &app
  image: figaro-api:latest
  env_file: .env
  environment:
    PHP_OPCACHE_ENABLE: "1"
    PHP_UPLOAD_MAX_FILE_SIZE: "50M"
    PHP_POST_MAX_SIZE: "55M"
    NGINX_CLIENT_MAX_BODY_SIZE: "55M"
  volumes:
    - storage:/var/www/html/storage
  depends_on:
    postgres: { condition: service_healthy }
    redis:    { condition: service_started }
  restart: unless-stopped

services:
  app:
    <<: *app
    build:
      context: .
      dockerfile: docker/php/Dockerfile
      target: production
    ports:
      - "127.0.0.1:8080:8080"   # serversideup fpm-nginx listens on 8080 by default

  queue:
    <<: *app
    command: ["php", "/var/www/html/artisan", "queue:work", "--tries=3"]
    stop_signal: SIGTERM
    healthcheck:
      test: ["CMD", "healthcheck-queue"]
      start_period: 10s

  scheduler:
    <<: *app
    command: ["php", "/var/www/html/artisan", "schedule:work"]
    stop_signal: SIGTERM
    healthcheck:
      test: ["CMD", "healthcheck-schedule"]
      start_period: 10s

  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: ${DB_DATABASE}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    command: >
      postgres -c shared_buffers=1GB -c effective_cache_size=3GB
               -c work_mem=16MB -c maintenance_work_mem=256MB
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME} -d ${DB_DATABASE}"]
      interval: 5s
      retries: 10
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redisdata:/data
    restart: unless-stopped

volumes:
  storage:
  pgdata:
  redisdata:
```

### Local alternative (not used): Laravel Herd + Docker for services only

Herd (free) runs PHP 8.4, Nginx, `.test` domains and Node natively. Postgres/Redis/Mailpit run in a small compose file so they match production versions. (Or buy Herd Pro and use its built-in PostgreSQL/Redis services instead.)

`compose.services.yml`:

```yaml
name: figaro-local
services:
  postgres:
    image: postgres:17          # same major version as production
    environment:
      POSTGRES_DB: figaro
      POSTGRES_USER: figaro
      POSTGRES_PASSWORD: secret
    ports: ["127.0.0.1:5432:5432"]
    volumes: [pgdata:/var/lib/postgresql/data]
  redis:
    image: redis:7-alpine
    ports: ["127.0.0.1:6379:6379"]
  mailpit:
    image: axllent/mailpit
    ports: ["127.0.0.1:1025:1025", "127.0.0.1:8025:8025"]
volumes:
  pgdata:
```

Steps:
1. Herd → set PHP **8.4** for the site (`herd isolate 8.4` in `backend/`).
2. `herd link figaro-api` in `backend/` → `https://figaro-api.test` (`herd secure figaro-api` for HTTPS).
3. `docker compose -f compose.services.yml up -d`
4. Local `backend/.env` differences vs production:
   ```dotenv
   APP_ENV=local
   APP_DEBUG=true
   APP_URL=https://figaro-api.test
   FRONTEND_URL=http://localhost:5173
   DB_HOST=127.0.0.1
   DB_PASSWORD=secret
   REDIS_HOST=127.0.0.1
   MAIL_HOST=127.0.0.1
   MAIL_PORT=1025
   LOG_CHANNEL=stack
   ```
5. Queue + scheduler: run `composer run dev` (Laravel's dev script runs queue, logs and Vite together) or separately `php artisan queue:work` / `php artisan schedule:work`.
6. Vue: `cd frontend && npm run dev` with `VITE_API_URL=https://figaro-api.test`.

Parity notes:
- Keep PHP (8.4) and Postgres (17) versions the same as production.
- If something works locally but fails on the server, it's usually a missing PHP extension: Herd bundles many, the production Dockerfile only adds `intl gd bcmath` on top of the image defaults. Add any extra extension you rely on to the Dockerfile.
- Before a big deploy, you can still run the full production image locally once: `docker compose up --build`.

### Local dev (chosen): full Docker – compose.dev.yml

One root `.env` is used for both local and production. `compose.dev.yml` overrides the production-shaped values for local use, so `cp .env.example .env` + `make up` works on a laptop. All ports bind to 127.0.0.1 only.

```yaml
x-dev-env: &dev-env
  APP_ENV: local
  APP_DEBUG: "true"
  APP_URL: http://localhost:8000
  FRONTEND_URL: http://localhost:5173
  SESSION_SECURE_COOKIE: "false"
  LOG_CHANNEL: stack
  MAIL_MAILER: smtp
  MAIL_HOST: mailpit
  MAIL_PORT: "1025"
  PHP_OPCACHE_ENABLE: "0"

services:
  app:
    build:
      target: development
      args:
        USER_ID: ${UID:-1000}
        GROUP_ID: ${GID:-1000}
    image: figaro-api:dev
    volumes: !override          # dev: no named storage volume, use backend/storage directly
      - ./backend:/var/www/html
    environment: *dev-env
    ports: !override            # needs Docker Compose >= 2.24
      - "127.0.0.1:8000:8080"
  queue:
    image: figaro-api:dev
    volumes: !override [ "./backend:/var/www/html" ]
    environment: *dev-env
  scheduler:
    image: figaro-api:dev
    volumes: !override [ "./backend:/var/www/html" ]
    environment: *dev-env
  postgres:
    ports: [ "127.0.0.1:5432:5432" ]   # for TablePlus/DBeaver
  mailpit:
    image: axllent/mailpit
    ports: [ "127.0.0.1:1025:1025", "127.0.0.1:8025:8025" ]   # SMTP + web UI
  frontend:
    image: node:24
    working_dir: /app
    volumes: [ "./frontend:/app" ]
    environment:
      VITE_API_URL: http://localhost:8000
    command: sh -c "npm install && npm run dev -- --host 0.0.0.0"
    ports: [ "127.0.0.1:5173:5173" ]
    profiles: [ "frontend" ]   # enabled by `make up` once frontend/ exists
```

Notes:
- Compose merges the `environment` maps, so dev values override `.env` and the production values from `compose.yml`; DB/Redis credentials still come from `.env`.
- Mailpit web UI: http://localhost:8025
- The `frontend` service uses a profile so `make up` works before `frontend/` exists (see Makefile).
- In dev, `volumes: !override` drops the production `storage` named volume, so Laravel uses the bind-mounted `backend/storage` (visible on your machine). The named volume is production-only.
- `www-data` in the dev image is remapped to your WSL user (UID/GID 1000 by default) so bind-mounted files have the right owner.

### .env.example (key lines)

```dotenv
APP_NAME="Figaro Workshop"
APP_ENV=production
APP_KEY=                       # php artisan key:generate --show
APP_DEBUG=false
APP_URL=https://shopapi.<domain>
APP_LOCALE=zh_HK
APP_FALLBACK_LOCALE=zh_HK
APP_TIMEZONE=Asia/Hong_Kong

FRONTEND_URL=https://wrkshp.<domain>   # used in config/cors.php allowed_origins

DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=figaro
DB_USERNAME=figaro
DB_PASSWORD=<long-random>

REDIS_HOST=redis
QUEUE_CONNECTION=redis
CACHE_STORE=redis
SESSION_DRIVER=redis
SESSION_SECURE_COOKIE=true

FILESYSTEM_DISK=local
LOG_CHANNEL=stderr             # view with: docker compose logs -f app

MAIL_MAILER=smtp               # production SMTP; dev overrides to mailpit
MAIL_HOST=<smtp-host>
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_FROM_ADDRESS=orders@<domain>
MAIL_FROM_NAME="Figaro Workshop"
```

### Laravel tweaks behind the proxy

`bootstrap/app.php`:

```php
->withMiddleware(function (Middleware $middleware) {
    $middleware->trustProxies(at: '*'); // safe: app only reachable via 127.0.0.1
})
```

CORS: `php artisan config:publish cors`, then set
`'allowed_origins' => [env('FRONTEND_URL')]`.

### deploy.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/figaro
git pull --ff-only

# Backend
docker compose build app
docker compose up -d
docker compose exec -T app php artisan migrate --force
docker compose exec -T app php artisan optimize
docker compose exec -T app php artisan filament:optimize
docker compose exec -T app php artisan queue:restart

# Frontend
docker run --rm -v "$PWD/frontend:/app" -w /app node:24 \
  sh -c "npm ci && npm run build"
rsync -a --delete frontend/dist/ /www/wwwroot/figaro-wrkshp/

echo "Deployed $(git rev-parse --short HEAD)"
```

### backup.sh (cron daily, e.g. 04:00 HKT)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/figaro
D=$(date +%F)
mkdir -p /opt/backups
docker compose exec -T postgres pg_dump -U figaro -Fc figaro > /opt/backups/db-$D.dump
docker run --rm -v figaro_storage:/data:ro -v /opt/backups:/backup alpine \
  tar czf /backup/storage-$D.tgz -C /data app
find /opt/backups -mtime +14 -delete
# Off-server copy (Hetzner Storage Box via rsync/rclone):
# rsync -a /opt/backups/ uXXXX@uXXXX.your-storagebox.de:figaro/
```

Also turn on Hetzner Cloud server backups/snapshots as a second safety net. **Test a restore once** before going live.

---

## 3b. Agentic coding with full Docker (TRAE Work desktop)

How it works: the code lives on your laptop and is **bind-mounted** into the containers (`./backend:/var/www/html`). The agent edits files on the host as normal; changes appear instantly in the container. The only rule: **every PHP/Composer/Node command runs inside a container**, via the `Makefile` below.

Requirements:
- Use **TRAE desktop with a local folder or WSL connection** (Code mode, local task). Cloud tasks run on TRAE's servers and can't reach your Docker.
- **Windows laptop:** install WSL 2 + Ubuntu 24.04, and Docker Desktop with the WSL 2 backend (Settings → Resources → WSL integration → enable Ubuntu). Keep the repo **inside WSL** (e.g. `~/code/figaro`, not `C:\Users\...`) — much faster file access for bind mounts, and you get `make`, `bash` and `chmod` natively (`sudo apt install make git`). Connect TRAE to WSL via the Remote Explorer → WSL target, then open the folder.
- Fallback if TRAE's agent can't use WSL: keep the repo in a Windows folder, use Git Bash as the terminal and install `make` for Windows. It works, just slower.
- Turn on Settings → Rules → "Include AGENTS.md in context" (desktop only).
- Optional but useful: don't install PHP on the laptop at all, so if the agent forgets the rules, the command fails immediately instead of silently using the wrong PHP.

The Vue dev server runs as the `frontend` service in `compose.dev.yml` (above).

### Makefile (repo root)

```makefile
DC = docker compose -f compose.yml -f compose.dev.yml
# enable the frontend container only once frontend/ exists
PROFILES = $(if $(wildcard frontend/package.json),--profile frontend,)

.PHONY: up down logs ps artisan composer test pint migrate fresh npm psql
.DEFAULT_GOAL := help

need-c = $(if $(c),,$(error Usage: make $@ c="<args>"))

help:      ; @grep -E '^[a-z]+:' Makefile | cut -d: -f1 | tr '\n' ' '; echo
up:        ; $(DC) $(PROFILES) up -d --build
down:      ; $(DC) --profile frontend down
logs:      ; $(DC) $(PROFILES) logs -f --tail=100
ps:        ; $(DC) $(PROFILES) ps
artisan:   ; $(need-c) $(DC) exec app php artisan $(c)
composer:  ; $(need-c) $(DC) exec app composer $(c)
test:      ; $(DC) exec app php artisan test $(c)
pint:      ; $(DC) exec app ./vendor/bin/pint
migrate:   ; $(DC) exec app php artisan migrate
fresh:     ; $(DC) exec app php artisan migrate:fresh --seed
npm:       ; $(need-c) $(DC) --profile frontend exec frontend npm $(c)
psql:      ; $(DC) exec postgres sh -c 'psql -U "$$POSTGRES_USER" "$$POSTGRES_DB"'
```

Usage: `make artisan c="make:model Part -m"`, `make composer c="require spatie/laravel-permission"`, `make test`.

### AGENTS.md (repo root)

```markdown
# Figaro Workshop – Agent Rules

## Environment (IMPORTANT)
- Everything runs in Docker. Do NOT run php, composer, artisan, npm or psql directly on the host.
- Use the Makefile:
  - Start: `make up` · Status: `make ps` · Logs: `make logs`
  - Artisan: `make artisan c="..."`
  - Composer: `make composer c="..."`
  - Tests: `make test` · Format: `make pint`
  - Frontend npm: `make npm c="..."`
  - DB shell: `make psql`
- Never run `make fresh` or `migrate:fresh` unless I ask.
- Never edit compose.yml, Dockerfile, deploy.sh or .env without asking.

## Stack
- backend/: Laravel 13, PHP 8.4, Filament 5 (panels: /admin 管理員, /dealer 經銷商), PostgreSQL 17, Redis queue.
- frontend/: Vue 3 + Vite + TypeScript, calls backend public API only (customers are guests, no login).

## Conventions
- All UI text in HK Traditional Chinese. Use the glossary: 零件, 3D打印零件, 非打印零件, BOM, 選項, 配置項目, 加購, 替換零件, 可更換內膽, 經銷商, 顧客, 訂單, 打印, Logo.
- Code, table and column names in English.
- Money stored as integer cents (HKD).
- Every feature needs a Pest/PHPUnit feature test; run `make test` before saying a task is done.
- Small commits, one feature per task.

## Docs
- Product spec: docs/figaro-ordering-handoff.md
- Environment: docs/figaro-environment-setup.md
```

Put the handoff and this setup doc in `docs/` so the agent can read them.

### Tips
- Ask the agent to run `make test` after each change — that's what makes agentic coding reliable.
- Commit before each agent task so you can roll back easily.
- On Mac, if file sync feels slow, enable Docker Desktop's "VirtioFS" file sharing (default on recent versions).

## 4. Server setup steps (one-time)

1. **Hetzner Cloud Firewall**: allow 22, 80, 443. aaPanel port: allow only your own IP.
2. **Install Docker Engine + Compose plugin** (official Docker apt repo, or aaPanel's Docker manager if already installed). Check: `docker compose version`.
3. **DNS**: A records `shopapi` and `wrkshp` → server IP.
4. **aaPanel → Website → Add site `shopapi.<domain>`** (static, no PHP, no DB)
   - SSL → Let's Encrypt → Force HTTPS
   - Reverse proxy → target `http://127.0.0.1:8080`, send host `$host`
   - In site config add:
     ```nginx
     client_max_body_size 55m;
     proxy_set_header X-Forwarded-Proto $scheme;
     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
     proxy_set_header X-Real-IP $remote_addr;
     ```
5. **aaPanel → Add site `wrkshp.<domain>`** (static), root `/www/wwwroot/figaro-wrkshp`
   - SSL → Let's Encrypt → Force HTTPS
   - URL rewrite / config: `location / { try_files $uri $uri/ /index.html; }`
6. **Clone repo** to `/opt/figaro`, create `.env` from `.env.example`, fill secrets.
7. First run:
   ```bash
   docker compose up -d --build
   docker compose exec app php artisan key:generate --show   # paste into .env, then:
   docker compose up -d
   docker compose exec app php artisan migrate --force
   docker compose exec app php artisan make:filament-user
   ```
8. Add `backup.sh` to cron (aaPanel → Cron, or `crontab -e`).

No aaPanel PHP, Supervisor, or PostgreSQL plugin needed — Docker covers all of that.

---

## 5. Later: WhatsApp (Baileys)

Add a `whatsapp` service (Node 24) to `compose.yml` that reads jobs from Redis and posts results back to the API. Persist its auth session in a volume. Use a **separate WhatsApp number** — Baileys is unofficial and the number can be banned. Keep notifications behind a Laravel interface so you can switch to the official WhatsApp Cloud API later.

---

## 6. Prompt for TRAE Code mode

```
Set up a monorepo for "Figaro Workshop" ordering system using EXACTLY this environment spec:
[paste sections 1–3 of this document]

Tasks:
1. Create backend/ as a fresh Laravel 13 app (PHP 8.4) with PostgreSQL and Redis configured per .env.example.
2. Install Filament 5 with two panels: "admin" at /admin (管理員) and "dealer" at /dealer (經銷商). Default locale zh_HK.
3. Install spatie/laravel-permission with roles: admin, dealer.
4. Configure trustProxies and CORS (FRONTEND_URL) as specified.
5. Create frontend/ as Vue 3 + Vite + TypeScript + Vue Router, with VITE_API_URL env var.
6. Add docker/php/Dockerfile, compose.yml, compose.dev.yml, .dockerignore, deploy.sh, backup.sh exactly as specified.
7. Add a GET /api/health endpoint and confirm `docker compose -f compose.yml -f compose.dev.yml up` works locally.
Do NOT build any business features (products, orders, BOM) yet. Only the skeleton.
Use the latest stable package versions compatible with Laravel 13 / Filament 5. Report any version conflicts instead of downgrading silently.
```
