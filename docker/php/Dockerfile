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
