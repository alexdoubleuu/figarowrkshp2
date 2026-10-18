FROM serversideup/php:8.4-fpm-nginx AS base
USER root
# Filament needs intl; gd for image thumbnails of logo uploads; bcmath for money math
RUN install-php-extensions intl gd bcmath
USER www-data

FROM base AS development
# code is bind-mounted in dev

FROM base AS production
COPY --chown=www-data:www-data backend/ /var/www/html
RUN composer install --no-dev --optimize-autoloader --no-interaction
