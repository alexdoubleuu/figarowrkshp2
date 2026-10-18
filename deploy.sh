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
