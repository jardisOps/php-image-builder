# ---------------------------------------------------------------------------
# test.mk — the test run
# ---------------------------------------------------------------------------
# Make orchestrates, the scripts assert. The assertions themselves live in
# tests/, not here, and can also run standalone.
#
# TEST IMAGES: built via the same support/docker-bake.hcl as everything else,
# just with a different registry prefix, so a test run never overwrites the
# local headgent/*-Images while still testing exactly the artifact that would
# later be pushed.
#
# ONE PHP version per run (PHP_VERSION from .env, overridable via the
# environment): `make build-all` compiles three versions at once and needs
# noticeable disk space, which a test run should not trigger incidentally. The
# CI drives the full matrix, building one job per version.
# ---------------------------------------------------------------------------
##@ Test

TEST_REGISTRY  ?= php-image-builder-test
CLI_TEST_IMAGE  = $(TEST_REGISTRY)/$(IMAGE_NAME_CLI):$(PHP_VERSION)
FPM_TEST_IMAGE  = $(TEST_REGISTRY)/$(IMAGE_NAME_FPM):$(PHP_VERSION)

# Own host port for the demo stack during the test run: a stack already
# running via `make demo-up` occupies DEMO_HTTP_PORT, and a test run should not
# tear it down. For the same reason check-demo-stack.sh runs under its own
# project name.
DEMO_TEST_PORT ?= 18080

TESTS_DIR = tests

# ---------------------------------------------------------------------------
# Static checks — no image required
# ---------------------------------------------------------------------------
HADOLINT_CONFIG  ?= support/hadolint.yaml
HADOLINT_IMAGE   ?= hadolint/hadolint:latest
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable

# All shell files in the repo. php-extensions.env is sourced, not executed,
# but belongs to the same check.
SHELL_FILES = src/shared/entrypoint/entrypoint.sh \
              src/shared/entrypoint/lib-user.sh \
              src/shared/entrypoint/lib-phpini.sh \
              src/shared/php-extensions.env \
              src/fpm/fpm-pool.sh \
              $(wildcard $(TESTS_DIR)/*.sh)

DOCKERFILES = src/base/Dockerfile src/cli/Dockerfile src/fpm/Dockerfile

test-lint: ## hadolint over all Dockerfiles, shellcheck over all shell files
	@echo ">>> hadolint"
	@for f in $(DOCKERFILES); do \
	  docker run --rm -i -v "$(CURDIR)/$(HADOLINT_CONFIG):/hadolint.yaml:ro" \
	    $(HADOLINT_IMAGE) hadolint --config /hadolint.yaml - < "$$f" || exit 1; \
	  echo "  ✅ $$f"; \
	done
	@echo ">>> shellcheck"
	@docker run --rm -v "$(CURDIR):/mnt" -w /mnt $(SHELLCHECK_IMAGE) \
	  --external-sources --source-path=src/shared/entrypoint $(SHELL_FILES)
	@echo "  ✅ $(words $(SHELL_FILES)) shell files clean"
.PHONY: test-lint

# ---------------------------------------------------------------------------
# Logic checks for the entrypoint libraries — no built image required
# ---------------------------------------------------------------------------
test-phpini: ## APP_ENV profiles, precedence rule, and validation (lib-phpini.sh)
	@bash $(TESTS_DIR)/check-phpini.sh
.PHONY: test-phpini

test-bake: ## Resolved bake definition: base dependency and tag set
	@bash $(TESTS_DIR)/check-bake-graph.sh
.PHONY: test-bake

test-user: ## UID/GID alignment in isolation (lib-user.sh, in alpine)
	@docker run --rm --platform linux/amd64 \
	  -v "$(CURDIR)/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
	  -v "$(CURDIR)/$(TESTS_DIR)/check-user-alignment.sh:/check.sh:ro" \
	  alpine:3.23 sh /check.sh
.PHONY: test-user

# ---------------------------------------------------------------------------
# Checks against the built image
# ---------------------------------------------------------------------------
test-images: buildx-builder-create ## Build test images for PHP_VERSION (own prefix, overwrites nothing)
	@echo "🔧 Building test images for PHP $(PHP_VERSION) under $(TEST_REGISTRY)/ ..."
	@$(call cache_flags); \
	 DOCKER_HUB=$(TEST_REGISTRY) PHP_VERSIONS="$(PHP_VERSION)" \
	 docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS)
.PHONY: test-images

test-extensions: test-images ## All expected extensions loaded in cli AND fpm
	@bash $(TESTS_DIR)/check-extensions.sh $(CLI_TEST_IMAGE)
	@bash $(TESTS_DIR)/check-extensions.sh $(FPM_TEST_IMAGE)
.PHONY: test-extensions

test-opcache: test-images ## OPcache/JIT per profile and revalidation in the running FPM
	@bash $(TESTS_DIR)/check-opcache.sh $(FPM_TEST_IMAGE)
.PHONY: test-opcache

test-app-env: test-images ## APP_ENV profiles take effect in the real image
	@bash $(TESTS_DIR)/check-app-env.sh $(CLI_TEST_IMAGE)
.PHONY: test-app-env

test-uid: test-images ## UID/GID against real Docker volumes (as far as possible without a Linux host)
	@bash $(TESTS_DIR)/check-uid-image.sh $(CLI_TEST_IMAGE)
.PHONY: test-uid

# Requires --privileged: the Linux host is a docker:*-dind container with its
# own daemon — the price of proving the bind-mount behavior without a
# GitHub runner.
DIND_IMAGE ?= docker:28-dind

test-uid-linux: test-images ## UID/GID against a REAL Linux bind mount
	@bash $(TESTS_DIR)/check-uid-linux-host.sh $(CLI_TEST_IMAGE) $(DIND_IMAGE)
.PHONY: test-uid-linux

test-nginx: test-images ## nginx template against the UNMODIFIED official image
	@bash $(TESTS_DIR)/check-nginx-template.sh $(FPM_TEST_IMAGE) nginx:$(NGINX_VERSION)-alpine
.PHONY: test-nginx

test-demo: test-images ## Demo stack: one `up`, all services healthy, DB connected
	@bash $(TESTS_DIR)/check-demo-stack.sh $(TEST_REGISTRY) $(DEMO_TEST_PORT)
.PHONY: test-demo

test-labels: test-images ## OCI labels in cli AND fpm, inherited via `FROM base`
	@bash $(TESTS_DIR)/check-oci-labels.sh $(CLI_TEST_IMAGE) $(PHP_VERSION)-$(IMAGE_DATE)
	@bash $(TESTS_DIR)/check-oci-labels.sh $(FPM_TEST_IMAGE) $(PHP_VERSION)-$(IMAGE_DATE)
.PHONY: test-labels

test-boot: test-images ## Start cli and fpm; fpm becomes healthy (FastCGI ping)
	@echo ">>> Starting cli and fpm"
	@docker run --rm --entrypoint php $(CLI_TEST_IMAGE) --version >/dev/null \
	  && echo "  ✅ cli starts"
	@cid=$$(docker run -d $(FPM_TEST_IMAGE)); \
	 status=starting; \
	 for i in $$(seq 1 30); do \
	   if [ "$$(docker inspect -f '{{.State.Running}}' $$cid 2>/dev/null)" != "true" ]; then status=exited; break; fi; \
	   status=$$(docker inspect -f '{{.State.Health.Status}}' $$cid 2>/dev/null || echo nohealth); \
	   [ "$$status" = "healthy" ] && break; \
	   sleep 1; \
	 done; \
	 docker logs $$cid > /tmp/fpm-boot.log 2>&1 || true; \
	 docker rm -f $$cid >/dev/null 2>&1 || true; \
	 if [ "$$status" != "healthy" ]; then \
	   echo "  ❌ fpm not healthy (status=$$status)"; cat /tmp/fpm-boot.log; exit 1; \
	 fi; \
	 echo "  ✅ fpm starts and responds on /ping"
.PHONY: test-boot

# ---------------------------------------------------------------------------
# Bundle
# ---------------------------------------------------------------------------
# Ordered by runtime: what runs without an image goes first, failing fast
# instead of only after a build.
test-all: test-lint test-bake test-phpini test-user test-boot test-labels test-extensions test-app-env test-uid test-uid-linux test-opcache test-nginx test-demo ## All checks
	@echo ""
	@echo "✅ All checks passed — PHP $(PHP_VERSION)"
.PHONY: test-all
