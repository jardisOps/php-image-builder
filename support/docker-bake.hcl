# ---------------------------------------------------------------------------
# support/docker-bake.hcl — the single build description for all targets
# ---------------------------------------------------------------------------
# Each build-arg is defined exactly once here; the local and push targets are
# thin wrappers around it (support/makefiles/docker.build.*.mk).
#
# VALUES COME FROM THE ENVIRONMENT ONLY. The Makefile loads ./.env and exports
# everything; a `make ... KEY=value` command-line assignment overrides it
# before the export, a plain shell environment variable does not. Bake reads
# the variables from there — it does not read .env itself.
#
# NO DEFAULTS: no `variable` carries a value. A missing value must abort
# visibly rather than build something else silently:
#   PHP_VERSION empty  -> build aborts ("failed to parse stage name php:-fpm-alpine")
#   an ENV value empty -> startup aborts (lib-phpini.sh, require_image_values,
#                         ${VAR:?} triggers on empty AND on unset)
#
# MATRIX: the version list comes from PHP_VERSIONS (support/makefiles/
# docker.helper.mk, the single definition of the matrix). `make build` sets it
# to the one PHP_VERSION from .env, `make build-all` to the full list.
# ---------------------------------------------------------------------------

# --- Matrix, names, and tags -------------------------------------------------
variable "PHP_VERSIONS" {}
variable "PHP_LATEST" {}
variable "IMAGE_DATE" {}
variable "DOCKER_HUB" {}
variable "IMAGE_NAME_CLI" {}
variable "IMAGE_NAME_FPM" {}

# --- Build-args for the base target -----------------------------------------
# Not all of them are `variable` blocks: PHP_VERSION and IMAGE_VERSION come
# from the matrix rather than from .env.
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

# --- OCI labels --------------------------------------------------------------
# Derived in support/makefiles/docker.helper.mk. IMAGE_VERSION is not among
# them: it differs per matrix entry and is built below from php and
# IMAGE_DATE — the same pair that also forms the immutable tag, so the label
# names exactly the tag the artifact carries.
variable "IMAGE_SOURCE" {}
variable "IMAGE_REVISION" {}
variable "IMAGE_CREATED" {}

# --- Build-args for the cli target -------------------------------------------
variable "PHP_MAX_EXECUTION_TIME_CLI" {}

# --- Build-args for the fpm target -------------------------------------------
variable "PHP_MAX_EXECUTION_TIME_WEB" {}
variable "FPM_PM" {}
variable "FPM_PM_MAX_CHILDREN" {}
variable "FPM_PM_START_SERVERS" {}
variable "FPM_PM_MIN_SPARE_SERVERS" {}
variable "FPM_PM_MAX_SPARE_SERVERS" {}
variable "FPM_PM_MAX_REQUESTS" {}

# ---------------------------------------------------------------------------
# Derivations
# ---------------------------------------------------------------------------
php_list = split(" ", PHP_VERSIONS)

# Bake target names cannot contain a dot: 8.3 becomes 8-3.
function "slug" {
  params = [version]
  result = replace(version, ".", "-")
}

# One version string drives all tags. IMAGE_DATE is fixed for the whole run,
# so phpcli:8.4-20260725 and phpfpm:8.4-20260725 are guaranteed to come from
# the same build, and a project can pin the combination. :latest only goes to
# the highest matrix version (PHP_LATEST).
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
# Groups
# ---------------------------------------------------------------------------
# base is deliberately not in the default group — it is not published, only a
# prerequisite. bake still builds it because cli and fpm pull it in via
# contexts = { base = ... }, without its own tag and without --load.
group "default" {
  targets = ["cli", "fpm"]
}

# ---------------------------------------------------------------------------
# base — not published
# ---------------------------------------------------------------------------
# The build context is the repo root: all targets access src/shared/ (see
# .dockerignore).
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
# cli — published as headgent/phpcli
# ---------------------------------------------------------------------------
# `FROM base` in the Dockerfile is pointed here at the matching matrix target,
# one per PHP version. base itself is not published.
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
# fpm — published as headgent/phpfpm
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
