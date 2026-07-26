# ---------------------------------------------------------------------------
# base — gemeinsame Grundlage von cli und fpm
# ---------------------------------------------------------------------------
# Wird NICHT publiziert. Sein Zweck ist, dass PHP-Version, Extensions, Composer,
# Laufzeit-Bibliotheken, der Benutzer appuser und der Entrypoint-Kern genau
# einmal beschrieben sind (E1, A3.1). cli und fpm bauen `FROM base` und tragen
# nur noch bei, was aus ihrem Einsatzzweck folgt.
#
# BASIS-IMAGE: php:<ver>-fpm-alpine<alpine> — und zwar auch fuer das CLI-Target.
# Entschieden am 2026-07-25 (N1, Variante a). Belegt durch Messung derselben
# Ausgabe fuer 8.3/alpine3.23:
#   fpm-alpine   79,4 MB   enthaelt /usr/local/bin/php (CLI) UND php-fpm
#   cli-alpine   96,1 MB   enthaelt zusaetzlich php-cgi und phpdbg (je ~16 MB)
# Das fpm-Image ist damit das KLEINERE und traegt einen byte-gleichen PHP-CLI.
# Das cli-Target verliert dadurch php-cgi und phpdbg — beide werden fuer Worker,
# Queue-Consumer, Cron, Composer und CI nicht gebraucht.
#
# Geerbt vom offiziellen fpm-Image und hier bewusst nicht zurueckgenommen:
#   CMD ["php-fpm"]      cli und fpm setzen ihr eigenes CMD
#   EXPOSE 9000          im cli-Image eine folgenlose Metadatenzeile; Docker
#                        kennt kein "unexpose"
#   STOPSIGNAL SIGQUIT   fuer FPM richtig, fuer einen Worker nicht — das
#                        cli-Target korrigiert das auf SIGTERM (P4)
#   conf.d/docker-fpm.ini (fastcgi.logging=Off) und /usr/local/etc/php-fpm.d/*
#                        wirken nur im FastCGI-SAPI und sind sonst unbenutzt
#
# BUILD-KONTEXT ist das Repo-Root (siehe .dockerignore), weil alle Targets auf
# src/shared/ zugreifen.
#
# A2.4: kein einziges ARG hat einen Default. Alle Werte kommen aus der .env.
# Fehlt einer, bricht der Build sichtbar ab, statt still etwas anderes zu bauen
# als die .env pflegt (das war D16).
# ---------------------------------------------------------------------------

# Global — vor jedem FROM, damit die FROM-Zeilen sie sehen.
ARG PHP_VERSION
ARG ALPINE_VERSION
ARG COMPOSER_VERSION

# ---------------------------------------------------------------------------
# Composer — gepinnt aus der .env, nicht per Installer gezogen
# ---------------------------------------------------------------------------
FROM composer:${COMPOSER_VERSION} AS composer

# ---------------------------------------------------------------------------
# Build-Stage — Extensions uebersetzen
# ---------------------------------------------------------------------------
# Der gesamte Toolchain bleibt in dieser Stage und landet nie im Ergebnis.
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS build

ARG APCU_VERSION
ARG REDIS_VERSION
ARG XDEBUG_VERSION
ARG PCOV_VERSION
ARG AMQP_VERSION
ARG RDKAFKA_VERSION

COPY src/shared/php-extensions.env /tmp/php-extensions.env

# apk upgrade auch hier (A7.7/H10, hebt D8 auf): phpfpm hatte es nur in der
# Runtime-Stage, wodurch gegen ungepatchte Header uebersetzt wurde.
#
# PECL_NAMES wird aus PHP_EXT_PECL abgeleitet statt zweitgepflegt (A2.1):
# `pecl install` will `name-version`, `docker-php-ext-enable` will `name`.
#
# `opcache` steht bewusst NICHT in der enable-Liste (anders als im Bestand): es
# ist im offiziellen Image bereits aktiv — bis 8.4 ueber die mitgelieferte
# docker-php-ext-opcache.ini, ab 8.5 statisch einkompiliert. Bei 8.5 bricht der
# Aufruf sogar ab ("error: 'opcache' does not exist"), weil es dort keine
# opcache.so mehr gibt. Geprueft am 2026-07-25 fuer 8.3, 8.4 und 8.5.
#
# `oniguruma-dev` und `curl-dev` standen bis P12 in der Paketliste. Sie sind die
# Header von mbstring bzw. curl — und beide Extensions bauen wir seit B12 nicht
# mehr, weil sie im offiziellen Image einkompiliert sind. Die Zeile behauptete
# also einen Bedarf, den es nicht gibt (gemessen fuer 8.3 und 8.5: Extensions
# 21/21, mb_ereg* und curl_version() funktionieren unveraendert).
#
# Der Rueckbau bringt allerdings NICHTS ausser Ehrlichkeit, und das ist wichtig
# zu wissen: die Image-Groesse ist byte-identisch (die Build-Stage wird ohnehin
# verworfen), die Bauzeit-Differenz liegt im Rauschen — und `curl-dev` wird
# weiterhin installiert, weil `librdkafka-dev` es ueber `pc:libcurl` hart
# nachzieht. Vom apk-Satz entfaellt genau EIN Paket: oniguruma-dev (0,8 MiB).
# Wer diese Zeile liest, soll nicht glauben, das Build-Image sei jetzt frei von
# libcurl-Headern.
#
# SC2086 ist hier kein Versehen, sondern der Zweck: die Extension-Listen
# MUESSEN wortweise aufgespalten werden. Gequotet bekaeme docker-php-ext-install
# die ganze Liste als EIN Argument und suchte nach einer Extension namens
# "bcmath curl exif ...". Die Werte stammen aus einer versionierten Datei im
# Repo, nicht aus Nutzereingaben.
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
# Runtime-Stage
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION}

ARG MAINTAINER_EMAIL
LABEL maintainer="${MAINTAINER_EMAIL}"

ARG INSTALL_DB_CLIENTS
ARG PUID
ARG PGID

# Laufzeitwerte, die das Image mitbringen MUSS (N2, zweite Haelfte): der
# Entrypoint hat fuer sie bewusst keinen Notwert und bricht ab, wenn einer fehlt
# (lib-phpini.sh, require_image_values). PHP_MAX_EXECUTION_TIME fehlt hier
# absichtlich — es ist der eine target-abhaengige Wert und wird von cli (=0) und
# fpm (=30) gesetzt (A2.5, begruendetes Delta zu D10).
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

# N2, erste Haelfte: die profilgesteuerten Variablen (XDEBUG_MODE, PCOV_ENABLED,
# OPCACHE_ENABLE, OPCACHE_VALIDATE_TIMESTAMPS, OPCACHE_REVALIDATE_FREQ,
# OPCACHE_JIT, PHP_DISPLAY_ERRORS, PHP_ERROR_REPORTING) stehen hier bewusst
# NICHT. Eine leere `ENV XDEBUG_MODE=` waere fuer Xdebug 3 nicht von "nicht
# gesetzt" zu unterscheiden, und `${VAR:=wert}` im Entrypoint koennte "leer"
# nicht mehr von "bewusst gesetzt" trennen — das APP_ENV-Profil bliebe
# wirkungslos (A10.2). Der Entrypoint loest sie zur Laufzeit auf und exportiert
# sie ausdruecklich (A10.5).
#
# APP_USER ist in allen Targets "appuser" — Benutzer UND Gruppe (A3.3, hebt D7
# auf; phpcli nannte die Gruppe bisher "appgroup").
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

# Laufzeit-Bibliotheken und die beiden Werkzeuge, die der Entrypoint braucht:
#   su-exec  Rechteabgabe an appuser (handover)
#   shadow   liefert usermod/groupmod fuer die UID/GID-Angleichung (lib-user.sh)
# bash bleibt erhalten: `make shell` und die Login-Shell von appuser setzen sie
# voraus. Der Entrypoint selbst braucht sie nicht mehr (POSIX-sh seit P2).
# INSTALL_DB_CLIENTS gilt ab hier fuer ALLE Targets (hebt D5 auf).
#
# SC2086 wie oben: $PKGS ist eine Paketliste und muss aufgespalten werden.
# Uebernommen aus phpcli/src/Dockerfile:93-99, wo es nie auffiel, weil phpcli
# als einziges Bestands-Repo keine hadolint-Konfiguration hatte (D15).
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

# OPcache muss als zend_extension VOR Xdebug laden. conf.d wird alphabetisch
# gelesen, deshalb bekommt die Datei ein 00-Praefix.
#
# Ab PHP 8.5 gibt es diese Datei nicht mehr: OPcache ist dort statisch
# einkompiliert und damit ohnehin vor jeder dynamisch geladenen zend_extension
# aktiv — die Ladereihenfolge ist dann von selbst richtig. Der else-Zweig laesst
# das nicht stillschweigend durchgehen, sondern belegt es: fehlt die INI UND ist
# OPcache nicht geladen, bricht der Build ab. Das ist der Unterschied zum
# `if [ -f ... ]` des Bestands, das beide Faelle wortlos verschluckte.
RUN set -eux; \
    if [ -f /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini ]; then \
        mv /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini \
           /usr/local/etc/php/conf.d/00-opcache.ini; \
    else \
        php -r 'exit(extension_loaded("Zend OPcache") ? 0 : 1);'; \
    fi

COPY src/shared/php-ini/50-xdebug-defaults.ini /usr/local/etc/php/conf.d/50-xdebug-defaults.ini

# Der Entrypoint-Kern existiert genau einmal (A3.1). Die Bibliotheken werden
# gesourct, nicht ausgefuehrt — daher kein Ausfuehrungsrecht. Ein Target legt
# seine Ergaenzungen in /usr/local/lib/entrypoint.d/ ab (A3.2); das Verzeichnis
# wird hier nicht angelegt, weil der Kern sein Fehlen vertraegt.
COPY src/shared/entrypoint/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY src/shared/entrypoint/lib-user.sh   /usr/local/lib/entrypoint/lib-user.sh
COPY src/shared/entrypoint/lib-phpini.sh /usr/local/lib/entrypoint/lib-phpini.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Der Container startet als root, gleicht appuser an den Eigentuemer von
# APP_ROOT an und gibt die Rechte per su-exec ab (A4). PUID/PGID sind nur die
# Ausgangswerte.
#
# 99-runtime-config.ini wird schon hier angelegt und haengt per Symlink in
# conf.d: so schreibt der Entrypoint spaeter als appuser, ohne dass conf.d
# beschreibbar sein muss (tragfaehiger Kern des Bestands, E10). Die Nummer 99
# sorgt dafuer, dass die Laufzeitwerte nach allen Image-INIs greifen.
RUN set -eux; \
    addgroup -g "${PGID}" "${APP_USER}"; \
    adduser -G "${APP_USER}" -u "${PUID}" -D -s /bin/bash "${APP_USER}"; \
    mkdir -p "${APP_ROOT}" "/home/${APP_USER}/php-config"; \
    : > "/home/${APP_USER}/php-config/99-runtime-config.ini"; \
    chown -R "${APP_USER}:${APP_USER}" "${APP_ROOT}" "/home/${APP_USER}"; \
    ln -sf "/home/${APP_USER}/php-config/99-runtime-config.ini" \
           /usr/local/etc/php/conf.d/99-runtime-config.ini

WORKDIR ${APP_ROOT}

# CMD, EXPOSE, STOPSIGNAL und HEALTHCHECK setzen cli (P4) und fpm (P5) — sie
# folgen dem Einsatzzweck, nicht der gemeinsamen Grundlage.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# ---------------------------------------------------------------------------
# OCI-Labels (A7.4/H4)
# ---------------------------------------------------------------------------
# Sie stehen NUR hier und nicht zusaetzlich in cli/fpm: Labels werden ueber
# `FROM base` vererbt, beide publizierten Images tragen sie also. Sie zu
# wiederholen waere Doppelpflege (A2.1) — dieselbe Linie, aus der cli und fpm
# auch WORKDIR und LABEL maintainer nicht wiederholen.
#
# Ganz am Ende der Stage, weil `revision` und `created` sich bei jedem Build
# aendern: ein ARG invalidiert den Cache ab seiner Zeile. Hier steht nichts mehr
# dahinter, was neu gebaut werden muesste.
#
# Kein ARG traegt einen Default (A2.4). Die Werte kommen aus
# support/makefiles/docker.helper.mk ueber docker-bake.hcl; `revision` meldet
# ausdruecklich `unknown`, wenn ausserhalb eines Git-Arbeitsbaums gebaut wird —
# ein sichtbarer Platzhalter statt eines stillen Leerstrings.
ARG IMAGE_SOURCE
ARG IMAGE_VERSION
ARG IMAGE_REVISION
ARG IMAGE_CREATED
LABEL org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}"
