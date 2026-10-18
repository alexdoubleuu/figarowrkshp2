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
