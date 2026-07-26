# ---------------------------------------------------------------------------
# php-image-builder — entry point
# ---------------------------------------------------------------------------
# Builds the PHP runtime images headgent/phpcli and headgent/phpfpm from a
# shared base. All values come from ./.env (single source of truth); this
# Makefile keeps no defaults of its own.
# ---------------------------------------------------------------------------
MAKEFLAGS      += --warn-undefined-variables
.SHELLFLAGS    := -eu -o pipefail -c
SHELL          := bash
.DEFAULT_GOAL  := help

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
# The profile-driven override slots are derived from the marked section of
# .env, not maintained a second time here — .env stays the single place that
# decides which variables an APP_ENV profile may override.
# awk has to see a plain '#'. Written directly, Make would read the rest of
# the line as its own comment; written as '\#' the backslash reaches awk,
# where it is not a known regex escape and gawk warns on every single call.
# Going through a variable gets a bare '#' past both.
HASH := \#
OVERRIDE_SLOTS := $(shell awk \
	'/^$(HASH) --- Override Slots/ { inblock = 1; next } \
	 inblock && /^$(HASH) ---/     { inblock = 0 } \
	 inblock && /^[A-Z_]+=/        { sub(/=.*/, ""); print }' ./.env)

include ./.env
export

# Overriding a single value goes on the command line: `make build
# PHP_VERSION=8.5`. Make gives a command-line assignment precedence over
# every assignment in an included file, so this needs no mechanism of its
# own. The leading-variable form (`PHP_VERSION=8.5 make build`) does NOT
# work — for a plain environment variable the file wins.

# ---------------------------------------------------------------------------
# Include modules
# ---------------------------------------------------------------------------
include ./support/makefiles/docker.helper.mk
include ./support/makefiles/docker.build.local.mk
include ./support/makefiles/docker.build.push.mk
include ./support/makefiles/test.mk
include ./support/makefiles/demo.mk
include ./support/makefiles/clean.mk
# Unrelated to building the images; kept here for compatibility with existing
# usage.
include ./support/makefiles/ssh.mk

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
##@ Setup
init: ## Set git remote to GITHUB_ORG/GITHUB_REPO from .env
	@echo "Setting git remote origin to https://github.com/$(GITHUB_ORG)/$(GITHUB_REPO).git"
	@git remote set-url origin "https://github.com/$(GITHUB_ORG)/$(GITHUB_REPO).git" \
		|| git remote add origin "https://github.com/$(GITHUB_ORG)/$(GITHUB_REPO).git"
	@echo "Done. Current remote:"
	@git remote -v
.PHONY: init

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------
##@ Info
info: ## Show build configuration
	@printf "\033[1mHeadgent PHP Image Builder\033[0m\n"
	@printf "\033[1m══════════════════════════\033[0m\n"
	@echo ""
	@printf "\033[1mRepository:\033[0m\n"
	@printf "  %-30s %s\n" "GitHub:"     "$(GITHUB_ORG)/$(GITHUB_REPO)"
	@printf "  %-30s %s\n" "Docker Hub:" "$(DOCKER_HUB)"
	@printf "  %-30s %s\n" "Maintainer:" "$(MAINTAINER_EMAIL)"
	@echo ""
	@printf "\033[1mTargets:\033[0m\n"
	@printf "  %-30s %s\n" "base (not published):" "php:<ver>-*-alpine$(ALPINE_VERSION)"
	@printf "  %-30s %s\n" "cli:"                     "$(CLI_IMAGE)"
	@printf "  %-30s %s\n" "fpm:"                     "$(FPM_IMAGE)"
	@echo ""
	@printf "\033[1mVersions:\033[0m\n"
	@printf "  %-30s %s\n" "Alpine:"          "$(ALPINE_VERSION)"
	@printf "  %-30s %s\n" "PHP (matrix):"    "$(PHP_VERSIONS)"
	@printf "  %-30s %s\n" "PHP (latest):"    "$(PHP_LATEST)"
	@printf "  %-30s %s\n" "PHP (default):"   "$(PHP_VERSION)"
	@printf "  %-30s %s\n" "Composer:"        "$(COMPOSER_VERSION)"
	@printf "  %-30s %s\n" "nginx (demo):"    "$(NGINX_VERSION)"
	@printf "  %-30s %s\n" "mariadb (demo):"  "$(MARIADB_VERSION)"
	@printf "  %-30s %s\n" "Date tag:"        "$(IMAGE_DATE)"
	@echo ""
	@printf "\033[1mPECL extensions:\033[0m\n"
	@printf "  %-30s %s\n" "apcu:"    "$(APCU_VERSION)"
	@printf "  %-30s %s\n" "redis:"   "$(REDIS_VERSION)"
	@printf "  %-30s %s\n" "xdebug:"  "$(XDEBUG_VERSION)"
	@printf "  %-30s %s\n" "pcov:"    "$(PCOV_VERSION)"
	@printf "  %-30s %s\n" "amqp:"    "$(AMQP_VERSION)"
	@printf "  %-30s %s\n" "rdkafka:" "$(RDKAFKA_VERSION)"
	@echo ""
	@printf "\033[1mBuild:\033[0m\n"
	@printf "  %-30s %s\n" "Platforms:"       "$(PLATFORMS)"
	@printf "  %-30s %s\n" "Cache backend:"     "$(CACHE_BACKEND)"
	@printf "  %-30s %s\n" "INSTALL_DB_CLIENTS:"  "$(if $(strip $(INSTALL_DB_CLIENTS)),$(INSTALL_DB_CLIENTS),<none>)"
	@printf "  %-30s %s\n" "appuser (PUID:PGID):" "$(PUID):$(PGID)"
	@printf "  %-30s %s\n" "APP_ROOT:"            "$(APP_ROOT)"
	@echo ""
	@printf "\033[1mRuntime — APP_ENV=%s\033[0m\n" "$(APP_ENV)"
	@printf "  Profile values come from src/shared/entrypoint/lib-phpini.sh.\n"
	@printf "  Filled override slots beat the profile:\n"
	@$(foreach slot,$(OVERRIDE_SLOTS),\
		printf "  %-30s %s\n" "$(slot):" \
			"$(if $(strip $($(slot))),$(strip $($(slot))) [override],<profile>)"; )
	@echo ""
	@printf "\033[1mRuntime — profile-independent:\033[0m\n"
	@printf "  %-30s %s\n" "PHP_MEMORY_LIMIT:"           "$(PHP_MEMORY_LIMIT)"
	@printf "  %-30s %s\n" "PHP_TIMEZONE:"               "$(PHP_TIMEZONE)"
	@printf "  %-30s %s\n" "PHP_LOG_ERRORS:"             "$(PHP_LOG_ERRORS)"
	@printf "  %-30s %s\n" "max_execution_time (cli):"   "$(PHP_MAX_EXECUTION_TIME_CLI)"
	@printf "  %-30s %s\n" "max_execution_time (web):"   "$(PHP_MAX_EXECUTION_TIME_WEB)"
	@printf "  %-30s %s\n" "APCU_SHM_SIZE:"              "$(APCU_SHM_SIZE)"
	@printf "  %-30s %s\n" "OPCACHE_MEMORY_CONSUMPTION:" "$(OPCACHE_MEMORY_CONSUMPTION)"
	@printf "  %-30s %s\n" "OPCACHE_MAX_ACCELERATED_FILES:" "$(OPCACHE_MAX_ACCELERATED_FILES)"
	@printf "  %-30s %s\n" "OPCACHE_JIT_BUFFER_SIZE:"    "$(OPCACHE_JIT_BUFFER_SIZE)"
	@printf "  %-30s %s\n" "XDEBUG_CLIENT_HOST:PORT:"    "$(XDEBUG_CLIENT_HOST):$(XDEBUG_CLIENT_PORT)"
	@printf "  %-30s %s\n" "XDEBUG_START_WITH_REQUEST:"  "$(XDEBUG_START_WITH_REQUEST)"
	@printf "  %-30s %s\n" "XDEBUG_IDEKEY:"              "$(XDEBUG_IDEKEY)"
	@printf "  %-30s %s\n" "XDEBUG_LOG_LEVEL:"           "$(XDEBUG_LOG_LEVEL)"
	@echo ""
	@printf "\033[1mFPM pool:\033[0m\n"
	@printf "  %-30s %s\n" "pm:"                "$(FPM_PM)"
	@printf "  %-30s %s\n" "max_children:"      "$(FPM_PM_MAX_CHILDREN)"
	@printf "  %-30s %s\n" "start_servers:"     "$(FPM_PM_START_SERVERS)"
	@printf "  %-30s %s\n" "min/max_spare:"     "$(FPM_PM_MIN_SPARE_SERVERS)/$(FPM_PM_MAX_SPARE_SERVERS)"
	@printf "  %-30s %s\n" "max_requests:"      "$(FPM_PM_MAX_REQUESTS)"
	@echo ""
	@printf "\033[1mDemo stack (tests/demo/demo-stack.yml):\033[0m\n"
	@printf "  %-30s %s\n" "Host port:"     "http://localhost:$(DEMO_HTTP_PORT)"
	@printf "  %-30s %s\n" "fpm image:"     "$(DEMO_REGISTRY)/$(IMAGE_NAME_FPM):$(PHP_VERSION)"
	@printf "  %-30s %s\n" "Database:"     "mariadb:$(MARIADB_VERSION), $(DEMO_DB_NAME) as $(DEMO_DB_USER)"
	@printf "  %-30s %s\n" "Passwords:"   "$(DEMO_DB_PASSWORD) / root: $(DEMO_DB_ROOT_PASSWORD)"
.PHONY: info

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help: ## Show this help
	@echo ""
	@printf "\033[1mUsage:\033[0m\n"
	@echo "  make <target>"
	@awk '\
		BEGIN { cols = "\033[36m%-28s\033[0m" } \
		/^##@ / {                                     \
			sub(/^##@ /,"");                           \
			printf "\n\033[1m%s\033[0m\n", $$0; next } \
		/^[A-Za-z0-9_.-]+:.*##/ {                     \
			split($$0, a, ":"); tgt = a[1];           \
			sub(/^.*## /,"");                         \
			printf "  " cols " %s\n", tgt, $$0 }      \
	' $(MAKEFILE_LIST)
	@echo ""
.PHONY: help
