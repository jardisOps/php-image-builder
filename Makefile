# ---------------------------------------------------------------------------
# php-image-builder — Einstiegspunkt
# ---------------------------------------------------------------------------
# Baut die PHP-Laufzeit-Images headgent/phpcli und headgent/phpfpm aus einer
# gemeinsamen Basis. Alle Werte kommen aus ./.env
# (Single Source of Truth); dieses Makefile pflegt keine eigenen Defaults.
# ---------------------------------------------------------------------------
MAKEFLAGS      += --warn-undefined-variables
.SHELLFLAGS    := -eu -o pipefail -c
SHELL          := bash
.DEFAULT_GOAL  := help

# ---------------------------------------------------------------------------
# Konfiguration laden
# ---------------------------------------------------------------------------
# Die profilgesteuerten Override-Slots werden aus dem markierten Abschnitt der
# .env abgeleitet, nicht hier zweitgepflegt: die .env bleibt die einzige Stelle,
# die festlegt, welche Variablen ein APP_ENV-Profil uebersteuern koennen (A10.2).
# Die '\#' sind fuer Make escaped — unescaped wuerde Make den Rest der Zeile als
# eigenen Kommentar lesen und die Klammer der shell-Funktion nie geschlossen sehen.
OVERRIDE_SLOTS := $(shell awk \
	'/^\# --- Override-Slots/ { inblock = 1; next } \
	 inblock && /^\# ---/     { inblock = 0 } \
	 inblock && /^[A-Z_]+=/   { sub(/=.*/, ""); print }' ./.env)

# Alle Schluessel der .env — Grundlage dafuer, die Umgebung Vorrang zu geben.
ENV_KEYS := $(shell awk '/^[A-Z_][A-Z0-9_]*=/ { sub(/=.*/, ""); print }' ./.env)

# Schluessel, die die aufrufende Umgebung bereits gesetzt hat, VOR dem include
# sichern: danach ist ihre Herkunft nicht mehr feststellbar, weil `include` sie
# auf "file" umschreibt.
ENV_SET_KEYS := $(foreach k,$(ENV_KEYS),$(if $(filter environment,$(origin $(k))),$(k)))
$(foreach k,$(ENV_SET_KEYS),$(eval SAVED_$(k) := $($(k))))

include ./.env
export

# Die Umgebung schlaegt die .env — dieselbe Semantik, die auch docker compose
# hat, und Voraussetzung fuer die Vorrangregel A10.2. In reinem Make gewinnt
# sonst immer die Datei: `XDEBUG_MODE=develop make shell` oder
# `APP_ENV=prod make info` waeren still wirkungslos (dieser Defekt steckt heute
# in beiden Bestands-Repos, wo `PHP_VERSION=8.3 make build` dokumentiert, aber
# ohne Wirkung ist). Ueberschrieben werden ausschliesslich .env-Schluessel —
# anders als bei `make -e`, das auch Make-eigene Variablen wie SHELL trifft.
$(foreach k,$(ENV_SET_KEYS),$(eval $(k) := $(SAVED_$(k))))

# ---------------------------------------------------------------------------
# Module einbinden
# ---------------------------------------------------------------------------
include ./support/makefiles/docker.helper.mk
include ./support/makefiles/docker.build.local.mk
include ./support/makefiles/docker.build.push.mk
include ./support/makefiles/test.mk
include ./support/makefiles/demo.mk
include ./support/makefiles/clean.mk
# Unveraendert aus dem Bestand uebernommen. Sie hat mit dem Bauen der Images
# nichts zu tun und steht nur hier, weil sie es in den Vorgaenger-Repos auch tat.
include ./support/makefiles/ssh.mk

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
##@ Setup
init: ## Git Remote auf GITHUB_ORG/GITHUB_REPO aus .env setzen
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
info: ## Build-Konfiguration anzeigen
	@printf "\033[1mHeadgent PHP Image Builder\033[0m\n"
	@printf "\033[1m══════════════════════════\033[0m\n"
	@echo ""
	@printf "\033[1mRepository:\033[0m\n"
	@printf "  %-30s %s\n" "GitHub:"     "$(GITHUB_ORG)/$(GITHUB_REPO)"
	@printf "  %-30s %s\n" "Docker Hub:" "$(DOCKER_HUB)"
	@printf "  %-30s %s\n" "Maintainer:" "$(MAINTAINER_EMAIL)"
	@echo ""
	@printf "\033[1mTargets:\033[0m\n"
	@printf "  %-30s %s\n" "base (nicht publiziert):" "php:<ver>-*-alpine$(ALPINE_VERSION)"
	@printf "  %-30s %s\n" "cli:"                     "$(CLI_IMAGE)"
	@printf "  %-30s %s\n" "fpm:"                     "$(FPM_IMAGE)"
	@echo ""
	@printf "\033[1mVersionen:\033[0m\n"
	@printf "  %-30s %s\n" "Alpine:"          "$(ALPINE_VERSION)"
	@printf "  %-30s %s\n" "PHP (Matrix):"    "$(PHP_VERSIONS)"
	@printf "  %-30s %s\n" "PHP (latest):"    "$(PHP_LATEST)"
	@printf "  %-30s %s\n" "PHP (default):"   "$(PHP_VERSION)"
	@printf "  %-30s %s\n" "Composer:"        "$(COMPOSER_VERSION)"
	@printf "  %-30s %s\n" "nginx (Demo):"    "$(NGINX_VERSION)"
	@printf "  %-30s %s\n" "mariadb (Demo):"  "$(MARIADB_VERSION)"
	@printf "  %-30s %s\n" "Datums-Tag:"      "$(IMAGE_DATE)"
	@echo ""
	@printf "\033[1mPECL-Extensions:\033[0m\n"
	@printf "  %-30s %s\n" "apcu:"    "$(APCU_VERSION)"
	@printf "  %-30s %s\n" "redis:"   "$(REDIS_VERSION)"
	@printf "  %-30s %s\n" "xdebug:"  "$(XDEBUG_VERSION)"
	@printf "  %-30s %s\n" "pcov:"    "$(PCOV_VERSION)"
	@printf "  %-30s %s\n" "amqp:"    "$(AMQP_VERSION)"
	@printf "  %-30s %s\n" "rdkafka:" "$(RDKAFKA_VERSION)"
	@echo ""
	@printf "\033[1mBuild:\033[0m\n"
	@printf "  %-30s %s\n" "Plattformen:"       "$(PLATFORMS)"
	@printf "  %-30s %s\n" "Cache-Backend:"     "$(CACHE_BACKEND)"
	@printf "  %-30s %s\n" "INSTALL_DB_CLIENTS:"  "$(if $(strip $(INSTALL_DB_CLIENTS)),$(INSTALL_DB_CLIENTS),<keine>)"
	@printf "  %-30s %s\n" "appuser (PUID:PGID):" "$(PUID):$(PGID)"
	@printf "  %-30s %s\n" "APP_ROOT:"            "$(APP_ROOT)"
	@echo ""
	@printf "\033[1mLaufzeit — APP_ENV=%s\033[0m\n" "$(APP_ENV)"
	@printf "  Profilwerte kommen aus src/shared/entrypoint/lib-phpini.sh.\n"
	@printf "  Gefuellte Override-Slots schlagen das Profil (A10.2):\n"
	@$(foreach slot,$(OVERRIDE_SLOTS),\
		printf "  %-30s %s\n" "$(slot):" \
			"$(if $(strip $($(slot))),$(strip $($(slot))) [Override],<Profil>)"; )
	@echo ""
	@printf "\033[1mLaufzeit — profilunabhaengig:\033[0m\n"
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
	@printf "\033[1mFPM-Pool:\033[0m\n"
	@printf "  %-30s %s\n" "pm:"                "$(FPM_PM)"
	@printf "  %-30s %s\n" "max_children:"      "$(FPM_PM_MAX_CHILDREN)"
	@printf "  %-30s %s\n" "start_servers:"     "$(FPM_PM_START_SERVERS)"
	@printf "  %-30s %s\n" "min/max_spare:"     "$(FPM_PM_MIN_SPARE_SERVERS)/$(FPM_PM_MAX_SPARE_SERVERS)"
	@printf "  %-30s %s\n" "max_requests:"      "$(FPM_PM_MAX_REQUESTS)"
	@echo ""
	@printf "\033[1mDemo-Stack (tests/demo/demo-stack.yml):\033[0m\n"
	@printf "  %-30s %s\n" "Host-Port:"     "http://localhost:$(DEMO_HTTP_PORT)"
	@printf "  %-30s %s\n" "fpm-Image:"     "$(DEMO_REGISTRY)/$(IMAGE_NAME_FPM):$(PHP_VERSION)"
	@printf "  %-30s %s\n" "Datenbank:"     "mariadb:$(MARIADB_VERSION), $(DEMO_DB_NAME) als $(DEMO_DB_USER)"
	@printf "  %-30s %s\n" "Passwoerter:"   "$(DEMO_DB_PASSWORD) / root: $(DEMO_DB_ROOT_PASSWORD)"
.PHONY: info

# ---------------------------------------------------------------------------
# Hilfe
# ---------------------------------------------------------------------------
help: ## Diese Hilfe anzeigen
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
