# ---------------------------------------------------------------------------
# docker.build.push.mk — Multi-Arch-Builds mit Push in die Registry
# ---------------------------------------------------------------------------
# Gleicher Wrapper wie docker.build.local.mk, drei Unterschiede:
#   --push statt --load      (multi-arch laesst sich nicht lokal laden)
#   --set '*.platform=...'   aus PLATFORMS (docker.helper.mk)
#   BUILD_ATTEST_FLAGS       Provenance + SBOM (A7.2/H2)
#
# ACHTUNG — NICHT AUSGEFUEHRT. Diese Targets sind geschrieben, aber bewusst nie
# gelaufen. Der erste Push auf headgent/phpcli bzw. headgent/phpfpm ist der
# einzige Punkt dieses Vorhabens mit Aussenwirkung (N6 in docs/PROGRESS.md):
# er ueberschreibt die wandernden Tags :<ver> und :latest, die laufende Projekte
# ziehen. Vor dem ersten Lauf wird eine Tag-Strategie vorgelegt und freigegeben.
# ---------------------------------------------------------------------------
##@ Image Builder (Push to Registry)

push: buildx-builder-create .check-docker-login ## Baut und pusht cli und fpm fuer PHP_VERSION (multi-arch)
	@echo "🚀 Baue und pushe $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) fuer PHP $(PHP_VERSION) ..."
	@$(call cache_flags); \
	 PHP_VERSIONS="$(PHP_VERSION)" docker buildx bake -f $(BAKE_FILE) --push \
	   --set '*.platform=$(PLATFORMS_CSV)' \
	   $$CFROM $$CTO $(BUILD_ATTEST_FLAGS) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Gepusht — PHP $(PHP_VERSION) (+ :$(PHP_VERSION)-$(IMAGE_DATE))"
.PHONY: push

push-all: buildx-builder-create .check-docker-login ## Baut und pusht cli und fpm fuer ALLE PHP_VERSIONS (multi-arch)
	@echo "🚀 Baue und pushe $(if $(strip $(BAKE_TARGETS)),$(BAKE_TARGETS),cli + fpm) fuer PHP $(PHP_VERSIONS) ..."
	@$(call cache_flags); \
	 docker buildx bake -f $(BAKE_FILE) --push \
	   --set '*.platform=$(PLATFORMS_CSV)' \
	   $$CFROM $$CTO $(BUILD_ATTEST_FLAGS) $(BUILD_EXTRA_FLAGS) $(BAKE_TARGETS)
	@echo "✅ Gepusht — PHP $(PHP_VERSIONS) (+ :<ver>-$(IMAGE_DATE)), :latest zeigt auf $(PHP_LATEST)"
.PHONY: push-all

# ---------------------------------------------------------------------------
# Login-Pruefung
# ---------------------------------------------------------------------------
# Uebernommen aus phpfpm/support/makefiles/docker.build.push.mk:146-153.
.check-docker-login:
	@if [ -z "$(DOCKER_HUB)" ]; then \
		echo "❌ DOCKER_HUB muss gesetzt sein."; exit 1; \
	fi
	@if ! docker info 2>/dev/null | grep -q "Username"; then \
		echo "⚠️  Nicht bei Docker Hub eingeloggt. Bitte 'docker login' ausfuehren."; \
	fi
.PHONY: .check-docker-login
