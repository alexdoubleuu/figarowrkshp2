# Figaro Workshop

Monorepo for the Figaro Workshop ordering system: a Laravel 13 + Filament 5 API/admin backend, a Vue 3 + Vite storefront, and a Docker Compose environment used both locally (full Docker) and in production (aaPanel as the front door, Docker Compose running everything the app needs).

## Prerequisites

- WSL 2 with Ubuntu 24.04 (keep the repo inside WSL, e.g. `~/code/figaro` — not under `C:\Users\...`)
- Docker Desktop with WSL integration enabled for Ubuntu 24.04
- `make`
- `git`

## Quick start

```bash
cp .env.example .env
make up
```

The API is then on http://localhost:8000, the Mailpit web UI on http://localhost:8025, and (once `frontend/` exists) the storefront on http://localhost:5173.

## Make commands

| Command | What it does |
|---|---|
| `make` | Print the list of available targets |
| `make up` | Build and start the dev stack (`docker compose up -d --build`) |
| `make down` | Stop the stack |
| `make ps` | Show container status |
| `make logs` | Follow logs (`--tail=100`) |
| `make artisan c="<args>"` | Run `php artisan` in the app container |
| `make composer c="<args>"` | Run `composer` in the app container |
| `make test` | Run the test suite |
| `make pint` | Run Pint |
| `make migrate` | Run migrations |
| `make fresh` | Drop and re-migrate with seed (never run unless asked) |
| `make npm c="<args>"` | Run npm in the frontend container |
| `make psql` | Open a psql shell in the postgres container |

## Docs

- [Environment setup](docs/figaro-environment-setup.md) — source of truth for the environment
- [Ordering handoff / product spec](docs/figaro-ordering-handoff.md)
