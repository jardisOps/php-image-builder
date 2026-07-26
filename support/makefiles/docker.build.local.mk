# ---------------------------------------------------------------------------
# docker.build.local.mk — local builds (--load)
# ---------------------------------------------------------------------------
# Thin wrapper around support/docker-bake.hcl; the build-args live there, not
# here.
#
# Values reach bake through the environment because the root Makefile exports
# everything after resolving overrides — a command-line assignment therefore
# reaches bake too:
#   make build PHP_VERSION=8.5     builds 8.5, not the 8.3 from .env
#
# Two optional switches:
#   BAKE_TARGETS    empty = group "default" (cli + fpm). `make build
#                   BAKE_TARGETS=fpm` builds only one target — including base,
#                   which is pulled in automatically as its build context.
#   BUILD_PLATFORM  empty = host platform. `make build
#                   BUILD_PLATFORM=linux/amd64` builds the foreign
#                   architecture (emulated) without requiring a push.
# ---------------------------------------------------------------------------
##@ Image Builder (Local)

BAKE_FILE      ?= support/docker-bake.hcl
BAKE_TARGETS   ?=
BUILD_PLATFORM ?=

# --set applies to all targets (*), including the pulled-in base.
BAKE_PLATFORM_FLAG = $(if $(strip $(BUILD_PLATFORM)),--set '*.platform=$(strip $(BUILD_PLATFORM))')

build: buildx-builder-create ## Build cli and fpm for PHP_VERSION locally (--load)
	@echo "🔧 Building $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) for PHP $(PHP_VERSION) ..."
	@$(call cache_flags); \
	 PHP_VERSIONS="$(PHP_VERSION)" docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Done — PHP $(PHP_VERSION)"
.PHONY: build

build-all: buildx-builder-create ## Build cli and fpm for ALL PHP_VERSIONS locally (--load)
	@echo "🔧 Building $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) for PHP $(PHP_VERSIONS) ..."
	@$(call cache_flags); \
	 docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Done — PHP $(PHP_VERSIONS), :latest points to $(PHP_LATEST)"
.PHONY: build-all

bake-print: ## Show the resolved bake definition (dry run, builds nothing)
	@docker buildx bake -f $(BAKE_FILE) --print $(BAKE_TARGETS)
.PHONY: bake-print
