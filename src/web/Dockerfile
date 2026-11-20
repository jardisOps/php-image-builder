# ---------------------------------------------------------------------------
# web — published as headgent/phpweb
# ---------------------------------------------------------------------------
# Purpose: the self-contained web runtime — php-fpm AND nginx in one image,
# supervised by s6. This is the base for baked deploy images (project code
# copied on top), where one artifact per version beats keeping two images'
# tags in sync. For the sidecar pattern, fpm remains the target of choice.
#
# Consumer: the deploy image of jardis-app-template-derived projects
# (K3s undertaking; decision Rolf 2026-08-23).
#
# s6 comes from Alpine's package tree, not the s6-overlay tarball: the
# overlay insists on being PID 1 (/init) and would displace the shared
# entrypoint core. Plain s6-svscan runs fine as the payload below it.
#
# DL3006: `fpm` is a named build context, not a registry image — there is
# nothing to tag. Same reasoning as in src/cli/Dockerfile.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM fpm

# nginx and s6 follow ALPINE_VERSION, deliberately unpinned (hadolint DL3018
# is ignored repo-wide for exactly this). gettext-envsubst renders the shared
# vhost template at start — the same mechanism the official nginx image uses.
RUN apk add --no-cache nginx s6 gettext-envsubst && rm -rf /var/cache/apk/*

# The shared vhost template and its defaults — the same versioned asset a
# sidecar setup mounts into the official nginx image. Single source: the web
# image renders it at start instead of carrying a second config dialect.
COPY src/shared/nginx/templates/default.conf.template /etc/nginx/templates/default.conf.template
COPY src/shared/nginx/nginx-defaults.env /etc/nginx/nginx-defaults.env

# Internal health server on 127.0.0.1:8081 — static config, no variables.
# It proxies to FPM's /ping, so the healthcheck below proves the whole
# nginx -> fpm chain without depending on any application code.
COPY src/web/nginx-health.conf /etc/nginx/http.d/health.conf

# Renders the vhost template after 10-fpm-pool.sh (lexical order). The core
# collects everything from entrypoint.d without knowing this target.
COPY src/web/20-nginx-config.sh /usr/local/lib/entrypoint.d/20-nginx-config.sh

# s6 service definitions: one per process, plus the svscan control dir.
# A finish script tells s6-svscan to take the container down when either
# process dies — no half-alive state where nginx answers 502 forever.
# They are the read-only originals; s6 runs on the scan directory that
# 15-web-runtime.sh assembles from them under WEB_RUNTIME_DIR.
COPY src/web/s6 /etc/s6.d

# Everything this target writes at start or while running lives under this
# one directory: the rendered vhost, nginx pid/logs/temp files and the s6
# scan directory. The fixed paths nginx and s6 expect become symlinks into
# it, so the image runs without root and on a read-only root filesystem with
# a single writable mount here. Not a tunable: the symlinks are baked.
ENV WEB_RUNTIME_DIR=/run/web

# /var/lib/nginx is 0750 nginx:nginx in the package; o+x lets a non-root
# identity reach the tmp and logs links below it without owning anything.
RUN set -eux; \
    mkdir -p "${WEB_RUNTIME_DIR}"; \
    chown "${APP_USER}:${APP_USER}" "${WEB_RUNTIME_DIR}"; \
    rm -rf /run/nginx /var/log/nginx /var/lib/nginx/tmp /etc/nginx/http.d/default.conf; \
    ln -s "${WEB_RUNTIME_DIR}/nginx/run" /run/nginx; \
    ln -s "${WEB_RUNTIME_DIR}/nginx/log" /var/log/nginx; \
    ln -s "${WEB_RUNTIME_DIR}/nginx/tmp" /var/lib/nginx/tmp; \
    ln -s "${WEB_RUNTIME_DIR}/nginx/default.conf" /etc/nginx/http.d/default.conf; \
    ln -s "${WEB_RUNTIME_DIR}/s6" /etc/s6; \
    chmod o+x /var/lib/nginx

# Prepares WEB_RUNTIME_DIR before the pool and the vhost are generated
# (lexical order: 10-fpm-pool, 15-web-runtime, 20-nginx-config).
COPY src/web/15-web-runtime.sh /usr/local/lib/entrypoint.d/15-web-runtime.sh

# Where nginx writes its access and error log: "file" keeps them under
# /var/log/nginx, "stdio" sends them to the container's stdout/stderr — the
# choice for orchestrators that collect logs from there.
ENV NGINX_LOG_OUTPUT=file

# In one image the upstream is always local; overrides the asset default
# ("app") the sidecar pattern uses. An explicit ENV wins over the defaults
# file in 20-nginx-config.sh.
ENV NGINX_FASTCGI_UPSTREAM=127.0.0.1

# The counterpart for the pool: FastCGI has no authentication, so in one image
# FPM listens on loopback only instead of on every pod/container interface.
ENV FPM_LISTEN=127.0.0.1:9000

# One image: nginx's root follows the baked APP_ROOT, same precedence as the
# upstream override above — a reference, not a second value (build rule 1).
ENV NGINX_APP_ROOT=${APP_ROOT}

# s6-svscan is the payload and handles SIGTERM as "bring everything down";
# the inherited SIGQUIT (correct for bare FPM) is not its shutdown signal.
STOPSIGNAL SIGTERM

# Through nginx to FPM's ping endpoint — a healthy web image means the full
# request chain answers, not just the interpreter.
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD ["sh", "-c", "wget -q -O- http://127.0.0.1:8081/ping | grep -q pong"]

EXPOSE 80

CMD ["s6-svscan", "/etc/s6"]
