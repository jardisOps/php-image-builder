# ---------------------------------------------------------------------------
# base — shared foundation for cli and fpm
# ---------------------------------------------------------------------------
# Not published. Its purpose is that PHP version, extensions, Composer,
# runtime libraries, the appuser user, and the entrypoint core are described
# exactly once. cli and fpm build `FROM base` and add only what follows from
# their specific purpose.
#
# Base image: php:<ver>-fpm-alpine<alpine>, used for the CLI target too.
# Measured for 8.3/alpine3.23:
#   fpm-alpine   79.4 MB   contains /usr/local/bin/php (CLI) AND php-fpm
#   cli-alpine   96.1 MB   also carries php-cgi and phpdbg (~16 MB each)
# The fpm image is therefore the smaller one and carries a byte-identical PHP
# CLI. The cli target loses php-cgi and phpdbg, neither needed for workers,
# queue consumers, cron, Composer, or CI.
#
# Inherited from the official fpm image and deliberately left in place:
#   CMD ["php-fpm"]      cli and fpm set their own CMD
#   EXPOSE 9000          a no-op metadata line in the cli image; Docker has
#                        no "unexpose"
#   STOPSIGNAL SIGQUIT   correct for FPM, wrong for a worker — the cli
#                        target corrects this to SIGTERM
#   conf.d/docker-fpm.ini (fastcgi.logging=Off) and /usr/local/etc/php-fpm.d/*
#                        only relevant to the FastCGI SAPI, otherwise unused
#
# Build context is the repo root (see .dockerignore), because all targets
# access src/shared/.
#
# No ARG has a default. All values come from .env; a missing one must abort
# the build visibly rather than silently building something different from
# what .env defines.
# ---------------------------------------------------------------------------

# Global — declared before any FROM, so the FROM lines can see them.
ARG PHP_VERSION
ARG ALPINE_VERSION
ARG COMPOSER_VERSION

# ---------------------------------------------------------------------------
# Composer — pinned via .env, not pulled through an installer
# ---------------------------------------------------------------------------
FROM composer:${COMPOSER_VERSION} AS composer

# ---------------------------------------------------------------------------
# Build stage — compile extensions
# ---------------------------------------------------------------------------
# The entire toolchain stays in this stage and never reaches the final image.
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS build

ARG APCU_VERSION
ARG REDIS_VERSION
ARG XDEBUG_VERSION
ARG PCOV_VERSION
ARG AMQP_VERSION
ARG RDKAFKA_VERSION

COPY src/shared/php-extensions.env /tmp/php-extensions.env

# apk upgrade also happens here: building only in the runtime stage would
# compile extensions against unpatched headers.
#
# PECL_NAMES is derived from PHP_EXT_PECL rather than maintained separately:
# `pecl install` wants `name-version`, `docker-php-ext-enable` wants `name`.
#
# `opcache` is deliberately not in the enable list: it is already active in
# the official image — via the bundled docker-php-ext-opcache.ini up to 8.4,
# statically compiled from 8.5 on. On 8.5 the enable call would even fail
# ("error: 'opcache' does not exist"), since there is no opcache.so there.
# Verified for 8.3, 8.4, and 8.5.
#
# The headers for mbstring and curl are deliberately absent: both extensions
# are already compiled into the official image. `curl-dev` is nevertheless
# present in this stage, because `librdkafka-dev` pulls it in via
# `pc:libcurl`.
#
# SC2086 is intentional here, not an oversight: the extension lists must be
# word-split. Quoted, docker-php-ext-install would receive the whole list as
# one argument and look for an extension literally named "bcmath curl exif
# ...". The values come from a versioned file in the repo, not from user
# input.
# hadolint ignore=SC2086
RUN set -eu; \
    . /tmp/php-extensions.env; \
    apk upgrade --no-cache; \
    apk add --no-cache \
      autoconf make g++ gcc libc-dev linux-headers libzip-dev libxml2-dev icu-dev \
      libjpeg-turbo-dev libpng-dev freetype-dev pcre2-dev re2c pkgconf flex bison libxslt-dev python3 perl gperf \
      gawk sed grep findutils coreutils postgresql-dev \
      rabbitmq-c-dev librdkafka-dev; \
    export LC_ALL=C; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" ${PHP_EXT_CORE}; \
    pecl channel-update pecl.php.net; \
    pecl config-set preferred_state stable; \
    yes '' | pecl install -o -f ${PHP_EXT_PECL}; \
    PECL_NAMES=''; \
    for ext in ${PHP_EXT_PECL}; do PECL_NAMES="${PECL_NAMES} ${ext%-*}"; done; \
    docker-php-ext-enable ${PECL_NAMES}

# ---------------------------------------------------------------------------
# Runtime stage
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION}

ARG MAINTAINER_EMAIL
LABEL maintainer="${MAINTAINER_EMAIL}"

ARG INSTALL_DB_CLIENTS
ARG PUID
ARG PGID

# Runtime values the image must supply: the entrypoint deliberately has no
# fallback for them and aborts if one is missing (lib-phpini.sh,
# require_image_values). PHP_MAX_EXECUTION_TIME is intentionally absent
# here — it is the one target-dependent value, set by cli (=0) and fpm (=30).
ARG APP_ENV
ARG APP_ROOT
ARG PHP_MEMORY_LIMIT
ARG PHP_TIMEZONE
ARG PHP_LOG_ERRORS
ARG APCU_SHM_SIZE
ARG OPCACHE_MEMORY_CONSUMPTION
ARG OPCACHE_MAX_ACCELERATED_FILES
ARG OPCACHE_JIT_BUFFER_SIZE
ARG XDEBUG_START_WITH_REQUEST
ARG XDEBUG_CLIENT_HOST
ARG XDEBUG_CLIENT_PORT
ARG XDEBUG_LOG_LEVEL
ARG XDEBUG_IDEKEY

# The profile-driven variables (XDEBUG_MODE, PCOV_ENABLED, OPCACHE_ENABLE,
# OPCACHE_VALIDATE_TIMESTAMPS, OPCACHE_REVALIDATE_FREQ, OPCACHE_JIT,
# PHP_DISPLAY_ERRORS, PHP_ERROR_REPORTING) are deliberately absent here. An
# empty `ENV XDEBUG_MODE=` would be indistinguishable from "unset" for
# Xdebug 3, and `${VAR:=value}` in the entrypoint could no longer tell
# "empty" from "deliberately set" — the APP_ENV profile would have no
# effect. The entrypoint resolves and exports them explicitly at runtime.
#
# APP_USER is "appuser" in every target — both user and group.
ENV APP_USER=appuser \
    APP_ENV=${APP_ENV} \
    APP_ROOT=${APP_ROOT} \
    PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT} \
    PHP_TIMEZONE=${PHP_TIMEZONE} \
    PHP_LOG_ERRORS=${PHP_LOG_ERRORS} \
    APCU_SHM_SIZE=${APCU_SHM_SIZE} \
    OPCACHE_MEMORY_CONSUMPTION=${OPCACHE_MEMORY_CONSUMPTION} \
    OPCACHE_MAX_ACCELERATED_FILES=${OPCACHE_MAX_ACCELERATED_FILES} \
    OPCACHE_JIT_BUFFER_SIZE=${OPCACHE_JIT_BUFFER_SIZE} \
    XDEBUG_START_WITH_REQUEST=${XDEBUG_START_WITH_REQUEST} \
    XDEBUG_CLIENT_HOST=${XDEBUG_CLIENT_HOST} \
    XDEBUG_CLIENT_PORT=${XDEBUG_CLIENT_PORT} \
    XDEBUG_LOG_LEVEL=${XDEBUG_LOG_LEVEL} \
    XDEBUG_IDEKEY=${XDEBUG_IDEKEY}

# Runtime libraries plus the two tools the entrypoint needs:
#   su-exec  hands off privileges to appuser
#   shadow   provides usermod/groupmod for UID/GID alignment (lib-user.sh)
# bash stays in the image because `make shell` and appuser's login shell
# require it; the entrypoint itself no longer needs it (POSIX sh).
# INSTALL_DB_CLIENTS applies to all targets from here on.
#
# SC2086 as above: $PKGS is a package list and must be word-split.
# hadolint ignore=SC2086
RUN set -eux; \
    apk upgrade --no-cache; \
    PKGS="bash git icu-libs libzip libxml2 oniguruma libjpeg-turbo libpng freetype postgresql-libs rabbitmq-c librdkafka su-exec shadow"; \
    case ",${INSTALL_DB_CLIENTS}," in *,mysql,*) PKGS="$PKGS mysql-client";; esac; \
    case ",${INSTALL_DB_CLIENTS}," in *,postgres,*) PKGS="$PKGS postgresql-client";; esac; \
    case ",${INSTALL_DB_CLIENTS}," in *,sqlite,*) PKGS="$PKGS sqlite";; esac; \
    apk add --no-cache $PKGS; \
    rm -rf /var/cache/apk/* /tmp/*; \
    cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

COPY --from=build /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=build /usr/local/etc/php/conf.d/     /usr/local/etc/php/conf.d/

# OPcache must load as a zend_extension before Xdebug. conf.d is read
# alphabetically, so the file gets a 00 prefix.
#
# From PHP 8.5 this file no longer exists: OPcache is statically compiled in
# and therefore already active before any dynamically loaded zend_extension,
# so the load order is correct by itself. The else branch verifies this
# instead of silently assuming it: if the INI is missing and OPcache is not
# loaded, the build aborts.
RUN set -eux; \
    if [ -f /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini ]; then \
        mv /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini \
           /usr/local/etc/php/conf.d/00-opcache.ini; \
    else \
        php -r 'exit(extension_loaded("Zend OPcache") ? 0 : 1);'; \
    fi

COPY src/shared/php-ini/50-xdebug-defaults.ini /usr/local/etc/php/conf.d/50-xdebug-defaults.ini

# The entrypoint core exists exactly once. The libraries are sourced, not
# executed, so they need no execute permission. A target adds its own
# scripts under /usr/local/lib/entrypoint.d/; the directory is not created
# here because the core tolerates its absence.
COPY src/shared/entrypoint/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY src/shared/entrypoint/lib-user.sh   /usr/local/lib/entrypoint/lib-user.sh
COPY src/shared/entrypoint/lib-phpini.sh /usr/local/lib/entrypoint/lib-phpini.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# The container starts as root, aligns appuser with the owner of APP_ROOT,
# and hands off privileges via su-exec. PUID/PGID are only the starting
# values.
#
# 99-runtime-config.ini is created here already and linked into conf.d, so
# the entrypoint can write it later as appuser without conf.d itself being
# writable. The 99 prefix ensures the runtime values take effect after all
# image INIs.
RUN set -eux; \
    addgroup -g "${PGID}" "${APP_USER}"; \
    adduser -G "${APP_USER}" -u "${PUID}" -D -s /bin/bash "${APP_USER}"; \
    mkdir -p "${APP_ROOT}" "/home/${APP_USER}/php-config"; \
    : > "/home/${APP_USER}/php-config/99-runtime-config.ini"; \
    chown -R "${APP_USER}:${APP_USER}" "${APP_ROOT}" "/home/${APP_USER}"; \
    ln -sf "/home/${APP_USER}/php-config/99-runtime-config.ini" \
           /usr/local/etc/php/conf.d/99-runtime-config.ini

WORKDIR ${APP_ROOT}

# CMD, EXPOSE, STOPSIGNAL, and HEALTHCHECK are set by cli and fpm — they
# follow the specific purpose, not the shared base.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# ---------------------------------------------------------------------------
# OCI labels
# ---------------------------------------------------------------------------
# They appear only here, not again in cli/fpm: labels are inherited via
# `FROM base`, so both published images carry them. Repeating them would be
# duplicate maintenance, the same reason cli and fpm don't repeat WORKDIR or
# LABEL maintainer either.
#
# Placed at the very end of the stage because `revision` and `created`
# change on every build: an ARG invalidates the cache from its line on, and
# nothing here needs to be rebuilt afterward.
#
# No ARG has a default. Values come from support/makefiles/docker.helper.mk
# via docker-bake.hcl; `revision` explicitly reports `unknown` when built
# outside a git working tree — a visible placeholder instead of a silent
# empty string.
ARG IMAGE_SOURCE
ARG IMAGE_VERSION
ARG IMAGE_REVISION
ARG IMAGE_CREATED
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}"
