# ---------------------------------------------------------------------------
# docker-bake.hcl — die eine Build-Beschreibung fuer alle Targets
# ---------------------------------------------------------------------------
# Loest die duplizierte buildx-Schleifenlogik der beiden Bestands-Repos ab
# (Plan-Optimierung 1). Dort standen dieselben ~35 --build-arg-Zeilen viermal
# nebeneinander: je einmal in phpfpm-build, phpfpm-build-all, phpfpm-push und
# phpfpm-push-all. Hier steht jedes Build-Arg genau einmal; local- und
# push-Targets sind duenne Wrapper (support/makefiles/docker.build.*.mk).
#
# HERKUNFT DER WERTE (A2.1): ausschliesslich die Umgebung. Das Makefile laedt
# ./.env, gibt der aufrufenden Umgebung Vorrang (Befund B1) und exportiert alles;
# bake liest die Variablen von dort. Belegt am 2026-07-25: bake liest die .env
# NICHT selbst ein — ohne das Makefile bleiben alle Werte leer.
#
# KEIN DEFAULT (A2.4): kein `variable` traegt einen Wert. Das ist dieselbe Regel
# wie in den Dockerfiles und aus demselben Grund — ein Default hier waere D16 an
# neuer Stelle. Faellt ein Wert aus, bricht es sichtbar ab:
#   PHP_VERSION leer  -> Build-Abbruch ("failed to parse stage name php:-fpm-alpine")
#   ein ENV-Wert leer -> Start-Abbruch  (lib-phpini.sh, require_image_values,
#                        ${VAR:?} greift bei leer UND bei ungesetzt)
#
# MATRIX: die Versionsreihe kommt aus PHP_VERSIONS (support/makefiles/
# docker.helper.mk, die einzige Definition der Matrix). `make build` setzt sie
# auf die eine PHP_VERSION aus der .env, `make build-all` auf die volle Reihe —
# derselbe Weg, nur eine andere Liste.
# ---------------------------------------------------------------------------

# --- Matrix, Namen und Tags -------------------------------------------------
variable "PHP_VERSIONS" {}
variable "PHP_LATEST" {}
variable "IMAGE_DATE" {}
variable "DOCKER_HUB" {}
variable "IMAGE_NAME_CLI" {}
variable "IMAGE_NAME_FPM" {}

# --- Build-Args des base-Targets --------------------------------------------
# 31 Stueck (27 + die vier OCI-Label-Args aus P11). Nicht alle stehen als
# `variable`: PHP_VERSION und IMAGE_VERSION kommen aus der Matrix bzw. werden
# daraus gebildet, nicht aus der .env. Die Zahl ist per `bake --print`
# gegengeprueft und keine Anforderung — sie stand hier schon einmal falsch
# (Befund B14).
variable "ALPINE_VERSION" {}
variable "COMPOSER_VERSION" {}
variable "APCU_VERSION" {}
variable "REDIS_VERSION" {}
variable "XDEBUG_VERSION" {}
variable "PCOV_VERSION" {}
variable "AMQP_VERSION" {}
variable "RDKAFKA_VERSION" {}
variable "MAINTAINER_EMAIL" {}
variable "INSTALL_DB_CLIENTS" {}
variable "PUID" {}
variable "PGID" {}
variable "APP_ENV" {}
variable "APP_ROOT" {}
variable "PHP_MEMORY_LIMIT" {}
variable "PHP_TIMEZONE" {}
variable "PHP_LOG_ERRORS" {}
variable "APCU_SHM_SIZE" {}
variable "OPCACHE_MEMORY_CONSUMPTION" {}
variable "OPCACHE_MAX_ACCELERATED_FILES" {}
variable "OPCACHE_JIT_BUFFER_SIZE" {}
variable "XDEBUG_START_WITH_REQUEST" {}
variable "XDEBUG_CLIENT_HOST" {}
variable "XDEBUG_CLIENT_PORT" {}
variable "XDEBUG_LOG_LEVEL" {}
variable "XDEBUG_IDEKEY" {}

# --- OCI-Labels (A7.4/H4) ---------------------------------------------------
# Abgeleitet in support/makefiles/docker.helper.mk. IMAGE_VERSION steht nicht
# dabei: es ist je Matrix-Eintrag verschieden und entsteht unten aus php und
# IMAGE_DATE — demselben Paar, das nach A1.3 auch den unveraenderlichen Tag
# bildet. Damit sagt das Label genau, welchen Tag das Artefakt trägt.
variable "IMAGE_SOURCE" {}
variable "IMAGE_REVISION" {}
variable "IMAGE_CREATED" {}

# --- Build-Args des cli-Targets ---------------------------------------------
variable "PHP_MAX_EXECUTION_TIME_CLI" {}

# --- Build-Args des fpm-Targets ---------------------------------------------
variable "PHP_MAX_EXECUTION_TIME_WEB" {}
variable "FPM_PM" {}
variable "FPM_PM_MAX_CHILDREN" {}
variable "FPM_PM_START_SERVERS" {}
variable "FPM_PM_MIN_SPARE_SERVERS" {}
variable "FPM_PM_MAX_SPARE_SERVERS" {}
variable "FPM_PM_MAX_REQUESTS" {}

# ---------------------------------------------------------------------------
# Ableitungen
# ---------------------------------------------------------------------------
php_list = split(" ", PHP_VERSIONS)

# Bake-Zielnamen duerfen keinen Punkt enthalten: aus 8.3 wird 8-3.
function "slug" {
  params = [version]
  result = replace(version, ".", "-")
}

# A1.3 — EIN Versionsstring treibt alle Tags. IMAGE_DATE gilt fuer den ganzen
# Lauf, sodass phpcli:8.4-20260725 und phpfpm:8.4-20260725 garantiert aus
# demselben Stand stammen und ein Projekt die Kombination pinnen kann.
# :latest bekommt nur die hoechste Version der Matrix (PHP_LATEST).
function "image_tags" {
  params = [name, version]
  result = concat(
    [
      "${DOCKER_HUB}/${name}:${version}",
      "${DOCKER_HUB}/${name}:${version}-${IMAGE_DATE}",
    ],
    version == PHP_LATEST ? ["${DOCKER_HUB}/${name}:latest"] : []
  )
}

# ---------------------------------------------------------------------------
# Gruppen
# ---------------------------------------------------------------------------
# base steht bewusst NICHT in der Default-Gruppe — es wird nicht publiziert und
# ist nur Vorstufe. bake baut es trotzdem, weil cli und fpm es ueber
# contexts = { base = ... } anziehen; ohne eigenen Tag und ohne --load.
group "default" {
  targets = ["cli", "fpm"]
}

# ---------------------------------------------------------------------------
# base — nicht publiziert
# ---------------------------------------------------------------------------
# Build-Kontext ist das Repo-Root: alle Targets greifen auf src/shared/ zu
# (siehe .dockerignore).
target "base" {
  name       = "base-${slug(php)}"
  matrix     = { php = php_list }
  context    = "."
  dockerfile = "src/base/Dockerfile"
  args = {
    PHP_VERSION                   = php
    ALPINE_VERSION                = ALPINE_VERSION
    COMPOSER_VERSION              = COMPOSER_VERSION
    APCU_VERSION                  = APCU_VERSION
    REDIS_VERSION                 = REDIS_VERSION
    XDEBUG_VERSION                = XDEBUG_VERSION
    PCOV_VERSION                  = PCOV_VERSION
    AMQP_VERSION                  = AMQP_VERSION
    RDKAFKA_VERSION               = RDKAFKA_VERSION
    MAINTAINER_EMAIL              = MAINTAINER_EMAIL
    INSTALL_DB_CLIENTS            = INSTALL_DB_CLIENTS
    PUID                          = PUID
    PGID                          = PGID
    APP_ENV                       = APP_ENV
    APP_ROOT                      = APP_ROOT
    PHP_MEMORY_LIMIT              = PHP_MEMORY_LIMIT
    PHP_TIMEZONE                  = PHP_TIMEZONE
    PHP_LOG_ERRORS                = PHP_LOG_ERRORS
    APCU_SHM_SIZE                 = APCU_SHM_SIZE
    OPCACHE_MEMORY_CONSUMPTION    = OPCACHE_MEMORY_CONSUMPTION
    OPCACHE_MAX_ACCELERATED_FILES = OPCACHE_MAX_ACCELERATED_FILES
    OPCACHE_JIT_BUFFER_SIZE       = OPCACHE_JIT_BUFFER_SIZE
    XDEBUG_START_WITH_REQUEST     = XDEBUG_START_WITH_REQUEST
    XDEBUG_CLIENT_HOST            = XDEBUG_CLIENT_HOST
    XDEBUG_CLIENT_PORT            = XDEBUG_CLIENT_PORT
    XDEBUG_LOG_LEVEL              = XDEBUG_LOG_LEVEL
    XDEBUG_IDEKEY                 = XDEBUG_IDEKEY

    IMAGE_SOURCE                  = IMAGE_SOURCE
    IMAGE_VERSION                 = "${php}-${IMAGE_DATE}"
    IMAGE_REVISION                = IMAGE_REVISION
    IMAGE_CREATED                 = IMAGE_CREATED
  }
}

# ---------------------------------------------------------------------------
# cli — publiziert als headgent/phpcli
# ---------------------------------------------------------------------------
# A1.2: `FROM base` im Dockerfile wird hier auf das gleichnamige Matrix-Ziel
# gezogen — je PHP-Version das passende. base wird dabei nicht publiziert.
target "cli" {
  name       = "cli-${slug(php)}"
  matrix     = { php = php_list }
  context    = "."
  dockerfile = "src/cli/Dockerfile"
  contexts   = { base = "target:base-${slug(php)}" }
  tags       = image_tags(IMAGE_NAME_CLI, php)
  args = {
    PHP_MAX_EXECUTION_TIME_CLI = PHP_MAX_EXECUTION_TIME_CLI
  }
}

# ---------------------------------------------------------------------------
# fpm — publiziert als headgent/phpfpm
# ---------------------------------------------------------------------------
target "fpm" {
  name       = "fpm-${slug(php)}"
  matrix     = { php = php_list }
  context    = "."
  dockerfile = "src/fpm/Dockerfile"
  contexts   = { base = "target:base-${slug(php)}" }
  tags       = image_tags(IMAGE_NAME_FPM, php)
  args = {
    PHP_MAX_EXECUTION_TIME_WEB = PHP_MAX_EXECUTION_TIME_WEB
    FPM_PM                     = FPM_PM
    FPM_PM_MAX_CHILDREN        = FPM_PM_MAX_CHILDREN
    FPM_PM_START_SERVERS       = FPM_PM_START_SERVERS
    FPM_PM_MIN_SPARE_SERVERS   = FPM_PM_MIN_SPARE_SERVERS
    FPM_PM_MAX_SPARE_SERVERS   = FPM_PM_MAX_SPARE_SERVERS
    FPM_PM_MAX_REQUESTS        = FPM_PM_MAX_REQUESTS
  }
}
