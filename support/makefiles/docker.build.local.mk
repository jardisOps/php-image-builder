# ---------------------------------------------------------------------------
# docker.build.local.mk — lokale Builds (--load)
# ---------------------------------------------------------------------------
# Duenner Wrapper um support/docker-bake.hcl. Die Build-Args stehen dort, nicht
# hier:
# in den Bestands-Repos standen dieselben ~35 --build-arg-Zeilen in jedem
# einzelnen Target (Plan-Optimierung 1).
#
# Die Werte kommen ueber die Umgebung, weil das Root-Makefile alles exportiert.
# Damit gilt die Vorrangregel auch hier durchgehend:
#   PHP_VERSION=8.5 make build     baut 8.5, nicht die 8.3 aus der .env
#
# Zwei Stellschrauben, beide optional:
#   BAKE_TARGETS    leer = Gruppe "default" (cli + fpm). `make build
#                   BAKE_TARGETS=fpm` baut nur ein Target — inklusive base,
#                   das als Build-Context automatisch mitgebaut wird.
#   BUILD_PLATFORM  leer = Plattform des Hosts. `make build
#                   BUILD_PLATFORM=linux/amd64` baut die Fremdarchitektur
#                   (emuliert), ohne dafuer pushen zu muessen.
# ---------------------------------------------------------------------------
##@ Image Builder (Local)

BAKE_FILE      ?= support/docker-bake.hcl
BAKE_TARGETS   ?=
BUILD_PLATFORM ?=

# --set greift auf alle Ziele (*), also auch auf das mitgezogene base.
BAKE_PLATFORM_FLAG = $(if $(strip $(BUILD_PLATFORM)),--set '*.platform=$(strip $(BUILD_PLATFORM))')

build: buildx-builder-create ## Baut cli und fpm fuer PHP_VERSION lokal (--load)
	@echo "🔧 Baue $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) fuer PHP $(PHP_VERSION) ..."
	@$(call cache_flags); \
	 PHP_VERSIONS="$(PHP_VERSION)" docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Fertig — PHP $(PHP_VERSION)"
.PHONY: build

build-all: buildx-builder-create ## Baut cli und fpm fuer ALLE PHP_VERSIONS lokal (--load)
	@echo "🔧 Baue $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) fuer PHP $(PHP_VERSIONS) ..."
	@$(call cache_flags); \
	 docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Fertig — PHP $(PHP_VERSIONS), :latest zeigt auf $(PHP_LATEST)"
.PHONY: build-all

bake-print: ## Aufgeloeste Bake-Definition zeigen (Trockenlauf, baut nichts)
	@docker buildx bake -f $(BAKE_FILE) --print $(BAKE_TARGETS)
.PHONY: bake-print
