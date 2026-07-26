# ---------------------------------------------------------------------------
# docker.build.push.mk — multi-arch builds with push to the registry
# ---------------------------------------------------------------------------
# Same wrapper as docker.build.local.mk, three differences:
#   --push instead of --load   (multi-arch cannot be loaded locally)
#   --set '*.platform=...'     from PLATFORMS (docker.helper.mk)
#   BUILD_ATTEST_FLAGS         provenance + SBOM
#
# WARNING — NEVER RUN. These targets are written but deliberately never
# executed. The first push to headgent/phpcli or headgent/phpfpm overwrites
# the moving :<ver> and :latest tags that running projects pull, so it needs
# an approved tag strategy before it ever runs.
# ---------------------------------------------------------------------------
##@ Image Builder (Push to Registry)

push: buildx-builder-create .check-docker-login ## Build and push cli and fpm for PHP_VERSION (multi-arch)
	@echo "🚀 Building and pushing $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) for PHP $(PHP_VERSION) ..."
	@$(call cache_flags); \
	 PHP_VERSIONS="$(PHP_VERSION)" docker buildx bake -f $(BAKE_FILE) --push \
	   --set '*.platform=$(PLATFORMS_CSV)' \
	   $$CFROM $$CTO $(BUILD_ATTEST_FLAGS) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Pushed — PHP $(PHP_VERSION) (+ :$(PHP_VERSION)-$(IMAGE_DATE))"
.PHONY: push

# The dry run for the two targets above: identical flags, --print instead of
# --push. It exists because a wrong flag in the push line could previously only
# be discovered by pushing — `--attest` (a `buildx build` flag that `bake` does
# not have) aborted the first real publish run before a single layer was built.
# Needs no login, no builder, and no network.
push-print: ## Resolved push definition (dry run — same flags as push, pushes nothing)
	@$(call cache_flags) >/dev/null; \
	 PHP_VERSIONS="$(PHP_VERSION)" docker buildx bake -f $(BAKE_FILE) --print \
	   --set '*.platform=$(PLATFORMS_CSV)' \
	   $$CFROM $$CTO $(BUILD_ATTEST_FLAGS) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
.PHONY: push-print

push-all: buildx-builder-create .check-docker-login ## Build and push cli and fpm for ALL PHP_VERSIONS (multi-arch)
	@echo "🚀 Building and pushing $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) for PHP $(PHP_VERSIONS) ..."
	@$(call cache_flags); \
	 docker buildx bake -f $(BAKE_FILE) --push \
	   --set '*.platform=$(PLATFORMS_CSV)' \
	   $$CFROM $$CTO $(BUILD_ATTEST_FLAGS) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Pushed — PHP $(PHP_VERSIONS) (+ :<ver>-$(IMAGE_DATE)), :latest points to $(PHP_LATEST)"
.PHONY: push-all

# ---------------------------------------------------------------------------
# Login check
# ---------------------------------------------------------------------------
.check-docker-login:
	@if [ -z "$(DOCKER_HUB)" ]; then \
		echo "❌ DOCKER_HUB must be set."; exit 1; \
	fi
	@if ! docker info 2>/dev/null | grep -q "Username"; then \
		echo "⚠️  Not logged in to Docker Hub. Please run 'docker login'."; \
	fi
.PHONY: .check-docker-login
