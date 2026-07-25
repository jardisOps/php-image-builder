# ---------------------------------------------------------------------------
# fpm — publiziert als headgent/phpfpm (E2, Name unveraendert)
# ---------------------------------------------------------------------------
# Zweck: php-fpm-only im Sidecar-Muster, vor einem nginx oder Traefik.
#
# Alles Inhaltliche steht in base. Hier steht, was aus dem Request-Betrieb folgt:
# ein Zeitlimit, die Pool-Parameter, das fcgi-Werkzeug fuer den Healthcheck und
# die Pool-Erzeugung als Target-Ergaenzung (A3.2).
#
# Anders als cli korrigiert dieses Target das geerbte STOPSIGNAL NICHT: SIGQUIT
# ist FPMs Signal fuer den graceful shutdown und hier genau richtig.
#
# DL3006: `base` ist ein benannter Build-Context, kein Registry-Image — es gibt
# nichts zu taggen. Gleiche Begruendung wie in src/cli/Dockerfile.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base

# Der einzige der 13 Pflichtwerte, den base nicht setzt (A2.5, begruendetes
# Delta zu D10): im Request-Kontext begrenzt ein Zeitlimit haengende Requests.
# Der Grund ist der Prozesstyp, nicht das Target — derselbe _WEB-Wert gilt ab P7
# auch fuer frankenphp.
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

# cgi-fcgi treibt den Healthcheck weiter unten. Bewusst nur hier und nicht in
# base — cli braucht es nicht.
RUN apk add --no-cache fcgi && rm -rf /var/cache/apk/*

# Die Pool-Erzeugung ist eine Ergaenzung, keine Kopie des Entrypoints (A3.1/A3.2).
# Der Kern sammelt alles aus entrypoint.d ein, ohne dieses Target zu kennen.
COPY src/fpm/fpm-pool.sh /usr/local/lib/entrypoint.d/10-fpm-pool.sh

# Gegenstueck zum Symlink fuer 99-runtime-config.ini in base: die Pool-Config
# wird zur Laufzeit in /home/appuser/php-config erzeugt und haengt von dort in
# php-fpm.d/. Das zz-Praefix sorgt dafuer, dass sie als letzte gelesen wird und
# damit www.conf und zz-docker.conf des offiziellen Images ueberschreibt.
RUN set -eux; \
    : > "/home/${APP_USER}/php-config/zz-fpm-runtime.conf"; \
    chown "${APP_USER}:${APP_USER}" "/home/${APP_USER}/php-config/zz-fpm-runtime.conf"; \
    ln -sf "/home/${APP_USER}/php-config/zz-fpm-runtime.conf" \
           /usr/local/etc/php-fpm.d/zz-fpm-runtime.conf

# Prueft den FastCGI-Dienst selbst, nicht nur den Interpreter: ohne antwortenden
# Pool ist das Image nutzlos. ping.path/ping.response setzt fpm-pool.sh.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD sh -c "SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q pong"

# EXPOSE 9000 und STOPSIGNAL SIGQUIT kommen aus dem offiziellen fpm-Image und
# sind hier beide richtig — sie werden deshalb nicht wiederholt und nicht
# geaendert (im Gegensatz zu cli, das STOPSIGNAL auf SIGTERM korrigiert).
CMD ["php-fpm"]
