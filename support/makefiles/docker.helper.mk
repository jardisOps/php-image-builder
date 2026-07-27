# ---------------------------------------------------------------------------
# docker.helper.mk — configuration & helpers
# ---------------------------------------------------------------------------
# Carries everything several build modules need in common: image references,
# the version matrix, the cache backend, and the buildx builder. The build and
# push targets themselves live in docker.build.local.mk / docker.build.push.mk
# as thin wrappers around docker-bake.hcl.
#
# Values come from ../../.env — this file only holds derivations and switches.
# ---------------------------------------------------------------------------
##@ Build

# ---------------------------------------------------------------------------
# Version matrix
# ---------------------------------------------------------------------------
# The single definition of the build matrix; PHP_LATEST is derived, not
# maintained separately. The series is 8.3 / 8.4 / 8.5; PHP_LATEST resolves to
# 8.5 and drives the :latest tag.
PHP_VERSIONS ?= 8.3 8.4 8.5
PHP_LATEST   := $(lastword $(PHP_VERSIONS))

# ---------------------------------------------------------------------------
# Image references
# ---------------------------------------------------------------------------
# The names themselves live in .env; this only builds the full registry
# references.
CLI_IMAGE = $(DOCKER_HUB)/$(IMAGE_NAME_CLI)
FPM_IMAGE = $(DOCKER_HUB)/$(IMAGE_NAME_FPM)

# ---------------------------------------------------------------------------
# Immutable date tag (UTC)
# ---------------------------------------------------------------------------
# Set in the push targets alongside the moving :<ver>/:latest tags, binding all
# artifacts of one run to the same version string so consumers can pin a
# reproducible combination (e.g. headgent/phpcli:8.4-20260725 +
# headgent/phpfpm:8.4-20260725). Overridable for a reproducible re-tag:
# make ... IMAGE_DATE=20260725
IMAGE_DATE ?= $(shell date -u +%Y%m%d)

# ---------------------------------------------------------------------------
# OCI labels
# ---------------------------------------------------------------------------
# Three derived values, kept here rather than in .env: a hand-maintained
# commit hash or timestamp would go stale after the next commit.
#
# IMAGE_SOURCE is assembled from GITHUB_ORG/GITHUB_REPO in .env rather than
# maintaining the URL a second time — the same two keys `make init` uses for
# the remote.
#
# IMAGE_REVISION reports `unknown` when built outside a git working tree
# (tarball, build context without .git) — a visible placeholder, not a silent
# empty string.
#
# IMAGE_VERSION is not here: it differs per matrix entry (<php>-<date>) and is
# built in docker-bake.hcl instead.
IMAGE_SOURCE   ?= https://github.com/$(GITHUB_ORG)/$(GITHUB_REPO)
IMAGE_REVISION ?= $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
IMAGE_CREATED  ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# ---------------------------------------------------------------------------
# Build switches
# ---------------------------------------------------------------------------
PLATFORMS ?= linux/amd64 linux/arm64

# bake wants the platforms comma-separated; they are maintained
# space-separated like everywhere else in the repo. The conversion happens
# here once so PLATFORMS stays the one maintained form.
comma         := ,
empty         :=
space         := $(empty) $(empty)
PLATFORMS_CSV  = $(subst $(space),$(comma),$(strip $(PLATFORMS)))

BUILD_EXTRA_FLAGS  ?=

# --sbom, not --attest: `docker buildx build` knows --attest, `docker buildx
# bake` does not. There the two shorthands --provenance and --sbom stand for
# --set='*.attest=type=...'. The push targets call bake, so an --attest here
# aborts the whole run with "unknown flag" before a single layer is built.
BUILD_ATTEST_FLAGS ?= --provenance=mode=max --sbom=true

# ---------------------------------------------------------------------------
# Cache backend: auto|none|local|registry|gha
# ---------------------------------------------------------------------------
CACHE_BACKEND ?= auto
CACHE_REF     ?=
CACHE_DIR     ?= .buildx-cache

# gha only. BuildKit writes into one shared "buildkit" namespace by default,
# so the matrix jobs would overwrite each other; CI passes one scope per PHP
# version and job. Empty keeps BuildKit's default.
#   CACHE_SCOPE        written and read
#   CACHE_READ_SCOPES  read in addition, never written — how the publish job
#                      picks up what the test job just built. A cache key is
#                      immutable once written and the second writer loses, so
#                      a shared write scope would drop whichever job finishes
#                      last: the arm64 layers, the expensive ones.
CACHE_SCOPE       ?=
CACHE_READ_SCOPES ?=

# rw = read and write (default), w = write only. The scheduled rebuild runs
# with w: it exists to pick up patched base layers, and reading the stored
# cache would republish the previous state under a new date tag. It still
# writes, so the cache never ages past the last scheduled run.
CACHE_MODE ?= rw

# ---------------------------------------------------------------------------
# buildx builder
# ---------------------------------------------------------------------------
BUILDX_BUILDER ?= multiarch-builder

buildx-builder-create: ## Create or activate the multiarch builder
	@if docker buildx ls | grep -q '$(BUILDX_BUILDER)'; then \
		echo "✅ $(BUILDX_BUILDER) already exists"; \
		docker buildx use $(BUILDX_BUILDER); \
	else \
		echo "🔧 Creating $(BUILDX_BUILDER) ..."; \
		docker buildx create --name $(BUILDX_BUILDER) --use --driver docker-container; \
	fi
.PHONY: buildx-builder-create

builder-reset: ## Remove and recreate the multiarch builder
	@echo "🔄 Resetting $(BUILDX_BUILDER) ..."
	@docker buildx rm $(BUILDX_BUILDER) 2>/dev/null || true
	@docker buildx create --name $(BUILDX_BUILDER) --use --driver docker-container
	@echo "✅ $(BUILDX_BUILDER) recreated"
.PHONY: builder-reset

build-cache-delete: ## Delete all cached image layers
	@docker buildx prune -a -f
.PHONY: build-cache-delete

# ---------------------------------------------------------------------------
# cache_flags — sets CFROM/CTO for the chosen backend type
# ---------------------------------------------------------------------------
# Embedded in one shell line: $(call cache_flags) ; docker buildx bake ...
#
# The gha export carries `ignore-error=true`: a failing cache must slow the
# build down, never stop it — an outage at GitHub would otherwise turn every
# job red and block publishing with them. Measured with an injected fault, a
# well-formed token pointed at an endpoint answering HTML: without the flag
# the build dies with exit 1, with it exit 0, and both error blocks stay in
# the log. The import side needs nothing, a failing cache-from is not fatal by
# itself. local and registry deliberately do without it: those are picked by
# hand on a command line, where a failed export is news.
define cache_flags
  set +u; \
  BACKEND="$${CACHE_BACKEND:-auto}"; \
  if [ -z "$$BACKEND" ] || [ "$$BACKEND" = "auto" ]; then \
    if [ "$${GITHUB_ACTIONS:-}" = "true" ]; then BACKEND="gha"; \
    elif [ "$${CI:-}" = "true" ]; then BACKEND="registry"; \
    else BACKEND="none"; fi; \
  fi; \
  SCOPE=""; if [ -n "$(CACHE_SCOPE)" ]; then SCOPE=",scope=$(CACHE_SCOPE)"; fi; \
  READ_SCOPES="$(CACHE_READ_SCOPES)"; \
  case "$$BACKEND" in \
    gha)      CFROM="--set=*.cache-from=type=gha$$SCOPE"; \
              for s in $$READ_SCOPES; do \
                CFROM="$$CFROM --set=*.cache-from=type=gha,scope=$$s"; \
              done; \
              CTO="--set=*.cache-to=type=gha,mode=max,ignore-error=true$$SCOPE";; \
    registry) if [ -z "$(CACHE_REF)" ]; then echo "ERROR: CACHE_REF is required for the registry backend" >&2; exit 2; fi; \
              CFROM="--set=*.cache-from=type=registry,ref=$(CACHE_REF)"; \
              CTO="--set=*.cache-to=type=registry,ref=$(CACHE_REF),mode=max";; \
    local)    mkdir -p "$(CACHE_DIR)"; \
              CFROM="--set=*.cache-from=type=local,src=$(CACHE_DIR)"; \
              CTO="--set=*.cache-to=type=local,dest=$(CACHE_DIR),mode=max";; \
    none|"")  CFROM=""; CTO="";; \
    *)        echo "ERROR: unknown CACHE_BACKEND=$$BACKEND" >&2; exit 2;; \
  esac; \
  case "$(CACHE_MODE)" in \
    rw)       ;; \
    w)        CFROM="";; \
    *)        echo "ERROR: unknown CACHE_MODE=$(CACHE_MODE), expected rw or w" >&2; exit 2;; \
  esac; \
  echo ">> Cache backend: $$BACKEND, mode $(CACHE_MODE)$${SCOPE:+, scope $(CACHE_SCOPE)}"
endef
