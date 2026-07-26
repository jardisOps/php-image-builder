# ---------------------------------------------------------------------------
# fpm — published as headgent/phpfpm
# ---------------------------------------------------------------------------
# Purpose: php-fpm-only in a sidecar pattern, behind an nginx or Traefik.
#
# Everything substantive lives in base. Here is what follows from request
# operation: a time limit, the pool parameters, the fcgi tool for the
# healthcheck, and the pool generation as a target addition.
#
# Unlike cli, this target does not correct the inherited STOPSIGNAL: SIGQUIT
# is FPM's signal for a graceful shutdown and is correct here.
#
# DL3006: `base` is a named build context, not a registry image — there is
# nothing to tag. Same reasoning as in src/cli/Dockerfile.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base

# The one required value base does not set: in a request context, a time
# limit bounds hanging requests. The reason is the process type, not the
# target; the key is therefore named _WEB, not _FPM.
ARG PHP_MAX_EXECUTION_TIME_WEB
ENV PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME_WEB}

ARG FPM_PM
ARG FPM_PM_MAX_CHILDREN
ARG FPM_PM_START_SERVERS
ARG FPM_PM_MIN_SPARE_SERVERS
ARG FPM_PM_MAX_SPARE_SERVERS
ARG FPM_PM_MAX_REQUESTS

ENV FPM_PM=${FPM_PM} \
    FPM_PM_MAX_CHILDREN=${FPM_PM_MAX_CHILDREN} \
    FPM_PM_START_SERVERS=${FPM_PM_START_SERVERS} \
    FPM_PM_MIN_SPARE_SERVERS=${FPM_PM_MIN_SPARE_SERVERS} \
    FPM_PM_MAX_SPARE_SERVERS=${FPM_PM_MAX_SPARE_SERVERS} \
    FPM_PM_MAX_REQUESTS=${FPM_PM_MAX_REQUESTS}

# cgi-fcgi drives the healthcheck below. Deliberately only here, not in base —
# cli does not need it.
RUN apk add --no-cache fcgi && rm -rf /var/cache/apk/*

# Pool generation is an addition, not a copy of the entrypoint. The core
# collects everything from entrypoint.d without knowing this target.
COPY src/fpm/fpm-pool.sh /usr/local/lib/entrypoint.d/10-fpm-pool.sh

# Counterpart to the symlink for 99-runtime-config.ini in base: the pool
# config is generated at runtime under /home/appuser/php-config and linked
# from there into php-fpm.d/. The zz prefix ensures it is read last, so it
# overrides www.conf and zz-docker.conf from the official image.
RUN set -eux; \
    : > "/home/${APP_USER}/php-config/zz-fpm-runtime.conf"; \
    chown "${APP_USER}:${APP_USER}" "/home/${APP_USER}/php-config/zz-fpm-runtime.conf"; \
    ln -sf "/home/${APP_USER}/php-config/zz-fpm-runtime.conf" \
           /usr/local/etc/php-fpm.d/zz-fpm-runtime.conf

# Checks the FastCGI service itself, not just the interpreter: without a
# responding pool the image is useless. ping.path/ping.response are set by
# fpm-pool.sh.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD sh -c "SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q pong"

# EXPOSE 9000 and STOPSIGNAL SIGQUIT come from the official fpm image and are
# both correct here — they are neither repeated nor changed (unlike cli,
# which corrects STOPSIGNAL to SIGTERM).
CMD ["php-fpm"]
