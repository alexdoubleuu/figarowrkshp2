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
