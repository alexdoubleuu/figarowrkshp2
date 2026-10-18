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
- Tests run against the figaro_test database (forced in phpunit.xml). Feature tests may use RefreshDatabase.
- Small commits, one feature per task.

## Docs
- Product spec: docs/figaro-ordering-handoff.md
- Environment: docs/figaro-environment-setup.md
