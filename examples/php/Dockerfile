# myapp as a container: nginx and PHP-FPM. Stage "dev" is the devcontainer, the last stage "app"
# the image that runs the app (the default target).
FROM composer:2.11.1 AS composer

# Alpine with PHP 8.5 and the extensions the app needs
FROM alpine:3.24 AS base
RUN apk add --no-cache php85 php85-ctype php85-mbstring php85-openssl

# The app with its runtime dependencies from Composer (vendor/), without dev dependencies
FROM base AS build
RUN apk add --no-cache php85-phar php85-iconv
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --optimize-autoloader
COPY VERSION ./
COPY public ./public
COPY src ./src

# Devcontainer: user dev (UID 1000) with Composer, what PHPStan and PHP-CS-Fixer need, and Xdebug.
# Alpine installs Xdebug without loading it, so the checks stay fast; the debug configuration
# (.vscode/launch.json) loads it. Claude Code, git, just and dev-kit come from the dev-kit feature
# (.devcontainer/devcontainer.json).
FROM base AS dev
RUN apk add --no-cache php85-dom php85-iconv php85-phar php85-tokenizer php85-xml php85-xmlwriter php85-pecl-xdebug \
    && adduser -D -u 1000 -s /bin/sh dev
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
USER dev

# The app: nginx and PHP-FPM as user myapp (UID 1000), state in /data. VERSION labels the image
# when a build sets it (CI); the app reports the version from the file VERSION at /healthz.
FROM base AS app
ARG VERSION=dev
LABEL org.opencontainers.image.title=myapp \
    org.opencontainers.image.source=https://github.com/example/myapp \
    org.opencontainers.image.version=$VERSION
RUN apk add --no-cache nginx php85-fpm \
    && adduser -D -H -u 1000 -s /sbin/nologin myapp \
    && mkdir /data \
    && chown myapp:myapp /data
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/php-fpm.conf /etc/php85/php-fpm.conf
COPY docker/entrypoint.sh /entrypoint.sh
COPY --from=build /app /app
ENV MYAPP_DATA_DIR=/data
USER myapp
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/entrypoint.sh"]
