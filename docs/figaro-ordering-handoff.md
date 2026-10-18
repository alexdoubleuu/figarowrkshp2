# Figaro Workshop – TRAE Prompts: Repo Prep & Skeleton

Run these **in order**, one prompt per TRAE Work **desktop, local-folder Code mode** task.
After each prompt: review the diff, then commit (prompts tell TRAE to commit, but check first).

---

## Step 0 – Do this yourself first

**Windows prerequisites (one-time):**
1. PowerShell (admin): `wsl --install -d Ubuntu-24.04`, reboot, create your Linux user.
2. Install Docker Desktop → Settings → General: "Use WSL 2 based engine" → Resources → WSL integration: enable Ubuntu-24.04.
3. In the Ubuntu terminal:
   ```bash
   sudo apt update && sudo apt install -y make git
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   docker compose version   # must be >= 2.24
   ```

**Create the repo inside WSL (not under C:\Users):**
```bash
mkdir -p ~/code/figaro && cd ~/code/figaro
git init -b main
mkdir docs
# copy the two downloaded docs in and RENAME them exactly:
#   docs/figaro-ordering-handoff.md
#   docs/figaro-environment-setup.md
# (Windows Downloads is at /mnt/c/Users/<you>/Downloads)
```

Open TRAE → Remote Explorer → WSL target → Ubuntu-24.04 → open `~/code/figaro`. Use Code mode, local task.

---

## Prompt 1 – Repo foundation (no app code yet)

```
You are setting up a new monorepo for the Figaro Workshop ordering system.

Read docs/figaro-environment-setup.md fully before doing anything. It is the source of truth for the environment. docs/figaro-ordering-handoff.md is the product spec (read it for context only; do NOT build features yet).

Create ONLY these repo-level files, exactly as specified in the setup doc:
- AGENTS.md (from section 3b)
- Makefile (from section 3b)
- docker/php/Dockerfile
- compose.yml (production)
- compose.dev.yml (local, full Docker, including the `frontend` node service from section 3b)
- .dockerignore
- .env.example (root, used by compose; values from the doc, placeholders for secrets)
- deploy.sh and backup.sh (chmod +x)
- .gitignore covering: .env, backend/vendor, backend/node_modules, frontend/node_modules, frontend/dist, backend/storage/*.key, .DS_Store, IDE folders
- .editorconfig (2 spaces for yaml/js/ts/vue/json, 4 spaces for php)
- README.md: one-paragraph project description, prerequisites (Docker Desktop, Git, make), quick start (`cp .env.example .env`, `make up`), list of make commands, link to docs/

Rules:
- Do not create backend/ or frontend/ yet.
- Do not invent extra services or change versions (Laravel 13, PHP 8.4, Filament 5, Postgres 17, Redis 7, Node 24).
- If anything in the doc is ambiguous or looks wrong, list it at the end instead of guessing.

When done: show me the file tree, then `git add -A && git commit -m "chore: repo foundation, docker and agent rules"`.
```

---

## Prompt 1b – Fix-up (only if you already ran Prompt 1 on the old doc)

```
Follow AGENTS.md. docs/figaro-environment-setup.md has been UPDATED and is the source of truth. docs/figaro-ordering-handoff.md now exists (context only).

1. Delete the old root copy of the setup doc if it's still there ("Figaro Workshop – Environment Setup.md").
2. Re-sync these files with the updated doc, exactly as written: compose.dev.yml (dev env overrides, 127.0.0.1 ports, mailpit 1025+8025, frontend service with profile), Makefile (.PHONY, help, need-c guard, profiles, psql using env vars), .env.example (MAIL_* lines added), and the Requirements in AGENTS.md if they differ.
3. Make sure README links to docs/figaro-environment-setup.md and docs/figaro-ordering-handoff.md.
4. Validate: `docker compose -f compose.yml -f compose.dev.yml config --quiet` (with .env copied from .env.example) must succeed. `make` with no args prints the target list. `make artisan` without c= must fail with the usage message.
5. List anything still ambiguous at the end.

Commit: "chore: sync dev environment with updated setup doc".
```

---

## Prompt 2 – Create the Laravel backend (inside Docker)

```
Follow AGENTS.md. PHP is NOT installed on the host; everything runs in Docker.

Create the Laravel 13 app in backend/ using a throwaway container (no host PHP):
docker run --rm -v "$PWD":/var/www/html -w /var/www/html serversideup/php:8.4-cli composer create-project laravel/laravel backend "^13.0"

Then:
1. Configure backend for PostgreSQL + Redis using the variables in root .env.example (DB_HOST=postgres, REDIS_HOST=redis, QUEUE_CONNECTION=redis, CACHE_STORE=redis, SESSION_DRIVER=redis). Laravel should read config from environment variables provided by compose; keep backend/.env.example in sync.
2. Set locale zh_HK, fallback zh_HK, timezone Asia/Hong_Kong.
3. In bootstrap/app.php add trustProxies(at: '*').
4. Publish CORS config and set allowed_origins to [env('FRONTEND_URL')].
5. Add GET /api/health returning {"status":"ok","db":true|false,"redis":true|false} (actually check both connections). Install API routes with `make artisan c="install:api"` if needed.
6. Add a feature test for /api/health.
7. Build and start: `make up`, then `make artisan c="key:generate --show"` and put the key in root .env (create .env from .env.example if missing; never commit it).
8. Run `make migrate` and `make test`. Both must pass.
9. Confirm http://localhost:8000/api/health returns ok.

If the container image fails to build or a PHP extension is missing, fix it in docker/php/Dockerfile and tell me what you changed.

When done: `git add -A && git commit -m "feat(backend): laravel 13 skeleton with postgres, redis, health check"`.
```

---

## Prompt 3 – Filament panels + roles

```
Follow AGENTS.md.

1. Install Filament 5 via `make composer c="require filament/filament:^5.0"`.
2. Create two panels:
   - "admin" at /admin (label 管理員), primary color neutral/dark.
   - "dealer" at /dealer (label 經銷商).
3. Install spatie/laravel-permission, publish + migrate. Roles: admin, dealer.
4. User model implements FilamentUser::canAccessPanel(): admin panel → role admin only; dealer panel → role dealer only.
5. Set Filament UI locale to zh_HK (Traditional Chinese). If Filament has no zh_HK translation, use zh_TW and tell me.
6. Add a seeder: one admin user (admin@figaro.test / password) and one dealer (dealer@figaro.test / password). Local only; guard with app()->environment('local').
7. Feature tests: admin can open /admin but not /dealer; dealer can open /dealer but not /admin; guest is redirected to login.
8. Run `make migrate`, `make artisan c="db:seed"`, `make test`. All must pass.
9. Run `make artisan c="filament:optimize-clear"` if assets look stale.

Do NOT create any business resources (products, parts, orders) yet.

When done: `git add -A && git commit -m "feat(backend): filament admin and dealer panels with roles"`.
```

---

## Prompt 4 – Vue storefront skeleton

```
Follow AGENTS.md. Node is NOT installed on the host.

1. Create the Vue app in frontend/ using a throwaway container:
   docker run --rm -v "$PWD":/app -w /app node:24 npm create vue@latest frontend -- --ts --router --pinia --eslint --prettier
   If the flags aren't supported, scaffold Vue 3 + Vite + TypeScript + Vue Router + Pinia manually.
2. Add VITE_API_URL to frontend/.env.example (local: http://localhost:8000).
3. Create a tiny api client (src/lib/api.ts) using fetch with VITE_API_URL as base.
4. Home page (zh-HK text): title "Figaro Workshop", and a status box that calls /api/health and shows 已連接 / 未連接.
5. Routes (empty placeholder pages, HK Chinese titles): / 首頁, /products 產品, /products/:sku 產品配置, /checkout 結帳, /order-lookup 訂單查詢.
6. Set <html lang="zh-HK">.
7. Start with `make up`, open http://localhost:5173 and confirm the status shows 已連接 (CORS must work with FRONTEND_URL=http://localhost:5173 in root .env).
8. `make npm c="run build"` must succeed.

No styling framework decisions yet; keep it plain.

When done: `git add -A && git commit -m "feat(frontend): vue 3 storefront skeleton with health check"`.
```

---

## Prompt 5 – Verify everything + production dry run

```
Follow AGENTS.md. This is a verification task; only fix what's broken.

1. `make down`, then `make up` from clean. Check `make ps`: app, queue, scheduler, postgres, redis, frontend all healthy/running.
2. Confirm the queue works: create a dummy job that logs "queue ok", dispatch it via a temporary artisan command, check `make logs` shows it, then delete the dummy job and command.
3. Confirm the scheduler runs (schedule:list shows nothing broken).
4. Production image dry run: `docker compose -f compose.yml build app` must succeed WITHOUT dev overrides. Then run it once with `docker compose -f compose.yml up -d` using a temporary .env, hit http://127.0.0.1:8080/api/health, then tear it down. Don't leave production containers running.
5. Run `make test` and `make pint`.
6. Update README.md with anything you learned (gotchas, exact commands).
7. Write docs/STATUS.md: what exists, what's verified, known issues, next steps.

When done: `git add -A && git commit -m "chore: verify dev and prod setup"`.
```

---

## Prompt 6 – Push to GitHub (do after you create an empty PRIVATE repo)

```
Add the remote and push:
git remote add origin git@github.com:<you>/figaro.git
git push -u origin main

Then add a GitHub Actions workflow .github/workflows/ci.yml that, on push and PR to main:
- builds the docker image with compose.yml + compose.dev.yml
- starts postgres and redis
- runs `php artisan test` inside the app container
- runs `npm ci && npm run build` in frontend
Keep it simple. Do NOT add deployment to the server yet.

Commit: "ci: run tests and frontend build on push".
```

---

## Tips

- If TRAE goes off-script, reply: **"Stop. Re-read AGENTS.md and docs/figaro-environment-setup.md, then continue."**
- If a step fails twice, ask TRAE to **explain the error and propose a fix before changing files.**
- Don't let it "fix" by downgrading versions — ask it to report conflicts instead.
- After Prompt 5 you have a working skeleton. Next phase is the database schema (products, parts, BOM rules, orders) — bring docs/STATUS.md back here and we'll design it.
