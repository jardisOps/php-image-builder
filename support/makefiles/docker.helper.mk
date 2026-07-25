# ---------------------------------------------------------------------------
# docker.helper.mk — Konfiguration & Helfer
# ---------------------------------------------------------------------------
# Traegt alles, was mehrere Build-Module gemeinsam brauchen: Image-Referenzen,
# die Versions-Matrix, das Cache-Backend und den buildx-Builder. Die Build- und
# Push-Targets selbst liegen in docker.build.local.mk / docker.build.push.mk und
# sind duenne Wrapper um docker-bake.hcl.
#
# Werte kommen aus ../../.env — hier stehen nur Ableitungen und Build-Schalter.
# ---------------------------------------------------------------------------
##@ Build

# ---------------------------------------------------------------------------
# Versions-Matrix
# ---------------------------------------------------------------------------
# Einzige Definition der Build-Matrix; PHP_LATEST wird abgeleitet, nicht
# gepflegt (in den Bestands-Repos war das zweimal unterschiedlich gelöst).
#
# 8.2 wurde am 2026-07-25 auf Anweisung des Users gestrichen, 8.5 aufgenommen.
# Die Reihe ist damit 8.3 / 8.4 / 8.5; PHP_LATEST wird zu 8.5 und treibt den
# :latest-Tag. Die Bestands-Repos bauten 8.2/8.3/8.4.
PHP_VERSIONS ?= 8.3 8.4 8.5
PHP_LATEST   := $(lastword $(PHP_VERSIONS))

# ---------------------------------------------------------------------------
# Image-Referenzen
# ---------------------------------------------------------------------------
# Die Namen selbst stehen in .env (E2: unveraendert gegenueber den
# Bestands-Repos); hier entstehen nur die vollen Registry-Referenzen.
CLI_IMAGE = $(DOCKER_HUB)/$(IMAGE_NAME_CLI)
FPM_IMAGE = $(DOCKER_HUB)/$(IMAGE_NAME_FPM)

# ---------------------------------------------------------------------------
# Unveraenderliches Datums-Tag (UTC)
# ---------------------------------------------------------------------------
# Wird in den Push-Targets neben die wandernden :<ver>/:latest-Tags gesetzt und
# bindet alle Artefakte EINES Laufs an denselben Versionsstring (A1.3), sodass
# Konsumenten eine reproduzierbare Kombination pinnen koennen
# (z.B. headgent/phpcli:8.4-20260725 + headgent/phpfpm:8.4-20260725).
# Fuer einen reproduzierbaren Re-Tag ueberschreibbar: make ... IMAGE_DATE=20260725
IMAGE_DATE ?= $(shell date -u +%Y%m%d)

# ---------------------------------------------------------------------------
# Build-Schalter
# ---------------------------------------------------------------------------
PLATFORMS ?= linux/amd64 linux/arm64
NO_CACHE  ?= false

# bake will die Plattformen kommasepariert, gepflegt sind sie (wie ueberall im
# Repo) leerzeichensepariert. Die Umrechnung steht hier einmal, damit PLATFORMS
# die einzige gepflegte Form bleibt.
comma         := ,
empty         :=
space         := $(empty) $(empty)
PLATFORMS_CSV  = $(subst $(space),$(comma),$(strip $(PLATFORMS)))

BUILD_EXTRA_FLAGS  ?=
BUILD_ATTEST_FLAGS ?= --provenance=mode=max --attest=type=sbom

# ---------------------------------------------------------------------------
# Cache-Backend: auto|none|local|registry|gha
# ---------------------------------------------------------------------------
CACHE_BACKEND ?= auto
CACHE_REF     ?=
CACHE_DIR     ?= .buildx-cache

# ---------------------------------------------------------------------------
# buildx-Builder
# ---------------------------------------------------------------------------
BUILDX_BUILDER ?= multiarch-builder

buildx-builder-create: ## Multiarch-Builder anlegen bzw. aktivieren
	@if docker buildx ls | grep -q '$(BUILDX_BUILDER)'; then \
		echo "✅ $(BUILDX_BUILDER) existiert bereits"; \
		docker buildx use $(BUILDX_BUILDER); \
	else \
		echo "🔧 $(BUILDX_BUILDER) wird angelegt ..."; \
		docker buildx create --name $(BUILDX_BUILDER) --use --driver docker-container; \
	fi
.PHONY: buildx-builder-create

builder-reset: ## Multiarch-Builder loeschen und neu anlegen
	@echo "🔄 $(BUILDX_BUILDER) wird zurueckgesetzt ..."
	@docker buildx rm $(BUILDX_BUILDER) 2>/dev/null || true
	@docker buildx create --name $(BUILDX_BUILDER) --use --driver docker-container
	@echo "✅ $(BUILDX_BUILDER) wurde neu erstellt"
.PHONY: builder-reset

build-cache-delete: ## Alle gecachten Image-Layer loeschen
	@docker buildx prune -a -f
.PHONY: build-cache-delete

# ---------------------------------------------------------------------------
# cache_flags — setzt CFROM/CTO fuer den gewaehlten Backend-Typ
# ---------------------------------------------------------------------------
# In eine Shell-Zeile eingebunden: $(call cache_flags) ; docker buildx bake ...
define cache_flags
  set +u; \
  BACKEND="$${CACHE_BACKEND:-auto}"; \
  if [ -z "$$BACKEND" ] || [ "$$BACKEND" = "auto" ]; then \
    if [ "$${GITHUB_ACTIONS:-}" = "true" ]; then BACKEND="gha"; \
    elif [ "$${CI:-}" = "true" ]; then BACKEND="registry"; \
    else BACKEND="none"; fi; \
  fi; \
  case "$$BACKEND" in \
    gha)      CFROM="--set=*.cache-from=type=gha"; \
              CTO="--set=*.cache-to=type=gha,mode=max";; \
    registry) if [ -z "$(CACHE_REF)" ]; then echo "FEHLER: CACHE_REF ist fuer das registry-Backend erforderlich" >&2; exit 2; fi; \
              CFROM="--set=*.cache-from=type=registry,ref=$(CACHE_REF)"; \
              CTO="--set=*.cache-to=type=registry,ref=$(CACHE_REF),mode=max";; \
    local)    mkdir -p "$(CACHE_DIR)"; \
              CFROM="--set=*.cache-from=type=local,src=$(CACHE_DIR)"; \
              CTO="--set=*.cache-to=type=local,dest=$(CACHE_DIR),mode=max";; \
    none|"")  CFROM=""; CTO="";; \
    *)        echo "FEHLER: unbekanntes CACHE_BACKEND=$$BACKEND" >&2; exit 2;; \
  esac; \
  echo ">> Cache-Backend: $$BACKEND"
endef
