# ---------------------------------------------------------------------------
# test.mk — Prueflauf
# ---------------------------------------------------------------------------
# Make orchestriert, die Skripte behaupten. Die Zusicherungen selbst stehen in
# support/tests/ und nicht hier: in den Bestands-Repos lagen sie als PHP-Einzeiler
# mitten im Makefile, mit `\$$`-Maskierung ueber mehrere Ebenen — unlesbar und
# ausserhalb von make nicht ausfuehrbar. Die Skripte laufen auch einzeln.
#
# TEST-IMAGES: gebaut wird ueber dieselbe docker-bake.hcl wie alles andere, nur
# mit einem anderen Registry-Praefix. Damit ueberschreibt ein Testlauf NIE die
# lokal liegenden headgent/*-Images — und der Test prueft trotzdem exakt das
# Artefakt, das spaeter gepusht wuerde.
#
# EINE PHP-Version je Lauf (PHP_VERSION aus der .env, per Umgebung
# ueberschreibbar). Absicht: `make build-all` uebersetzt drei Versionen
# GLEICHZEITIG und braucht dafuer spuerbar Plattenplatz (Befund B15) — ein
# Testlauf soll das nicht nebenbei ausloesen. Die Matrix faehrt die CI (P11),
# dort baut ohnehin ein Job je Version.
# ---------------------------------------------------------------------------
##@ Test

TEST_REGISTRY  ?= php-image-builder-test
CLI_TEST_IMAGE  = $(TEST_REGISTRY)/$(IMAGE_NAME_CLI):$(PHP_VERSION)
FPM_TEST_IMAGE  = $(TEST_REGISTRY)/$(IMAGE_NAME_FPM):$(PHP_VERSION)

TESTS_DIR = support/tests

# ---------------------------------------------------------------------------
# Statische Pruefung — braucht kein Image
# ---------------------------------------------------------------------------
HADOLINT_IMAGE   ?= hadolint/hadolint:latest
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable

# Alle Shell-Dateien des Repos. php-extensions.env wird gesourct, nicht
# ausgefuehrt, gehoert aber zur selben Pruefung.
SHELL_FILES = src/shared/entrypoint/entrypoint.sh \
              src/shared/entrypoint/lib-user.sh \
              src/shared/entrypoint/lib-phpini.sh \
              src/shared/php-extensions.env \
              src/fpm/fpm-pool.sh \
              $(wildcard $(TESTS_DIR)/*.sh)

DOCKERFILES = src/base/Dockerfile src/cli/Dockerfile src/fpm/Dockerfile

test-lint: ## hadolint ueber alle Dockerfiles, shellcheck ueber alle Shell-Dateien
	@echo ">>> hadolint"
	@for f in $(DOCKERFILES); do \
	  docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" \
	    $(HADOLINT_IMAGE) hadolint --config /.hadolint.yaml - < "$$f" || exit 1; \
	  echo "  ✅ $$f"; \
	done
	@echo ">>> shellcheck"
	@docker run --rm -v "$(CURDIR):/mnt" -w /mnt $(SHELLCHECK_IMAGE) \
	  --external-sources --source-path=src/shared/entrypoint $(SHELL_FILES)
	@echo "  ✅ $(words $(SHELL_FILES)) Shell-Dateien sauber"
.PHONY: test-lint

# ---------------------------------------------------------------------------
# Logik-Pruefung der Entrypoint-Bibliotheken — ohne gebautes Image
# ---------------------------------------------------------------------------
test-phpini: ## APP_ENV-Profile, Vorrangregel und Validierung (lib-phpini.sh)
	@bash $(TESTS_DIR)/check-phpini.sh
.PHONY: test-phpini

test-user: ## UID/GID-Angleichung in Isolation (lib-user.sh, in alpine)
	@docker run --rm --platform linux/amd64 \
	  -v "$(CURDIR)/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
	  -v "$(CURDIR)/$(TESTS_DIR)/check-user-alignment.sh:/check.sh:ro" \
	  alpine:3.23 sh /check.sh
.PHONY: test-user

# ---------------------------------------------------------------------------
# Pruefung am gebauten Image
# ---------------------------------------------------------------------------
test-images: buildx-builder-create ## Test-Images fuer PHP_VERSION bauen (eigenes Praefix, ueberschreibt nichts)
	@echo "🔧 Baue Test-Images fuer PHP $(PHP_VERSION) unter $(TEST_REGISTRY)/ ..."
	@$(call cache_flags); \
	 DOCKER_HUB=$(TEST_REGISTRY) PHP_VERSIONS="$(PHP_VERSION)" \
	 docker buildx bake -f $(BAKE_FILE) --load \
	   $$CFROM $$CTO $(BAKE_PLATFORM_FLAG) $(BUILD_EXTRA_FLAGS)
.PHONY: test-images

test-extensions: test-images ## Alle erwarteten Extensions in cli UND fpm geladen
	@bash $(TESTS_DIR)/check-extensions.sh $(CLI_TEST_IMAGE)
	@bash $(TESTS_DIR)/check-extensions.sh $(FPM_TEST_IMAGE)
.PHONY: test-extensions

test-opcache: test-images ## OPcache/JIT je Profil und AK15-Revalidierung im laufenden FPM
	@bash $(TESTS_DIR)/check-opcache.sh $(FPM_TEST_IMAGE)
.PHONY: test-opcache

test-app-env: test-images ## APP_ENV-Profile wirken im echten Image (AK13/AK14)
	@bash $(TESTS_DIR)/check-app-env.sh $(CLI_TEST_IMAGE)
.PHONY: test-app-env

test-uid: test-images ## UID/GID gegen echte Docker-Volumes (AK4, soweit ohne Linux-Host moeglich)
	@bash $(TESTS_DIR)/check-uid-image.sh $(CLI_TEST_IMAGE)
.PHONY: test-uid

test-nginx: test-images ## nginx-Vorlage gegen das UNVERAENDERTE offizielle Image (A6/AK7)
	@bash $(TESTS_DIR)/check-nginx-template.sh $(FPM_TEST_IMAGE) nginx:$(NGINX_VERSION)-alpine
.PHONY: test-nginx

test-boot: test-images ## cli und fpm starten; fpm wird healthy (FastCGI-Ping)
	@echo ">>> Start von cli und fpm"
	@docker run --rm --entrypoint php $(CLI_TEST_IMAGE) --version >/dev/null \
	  && echo "  ✅ cli startet"
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
	   echo "  ❌ fpm nicht healthy (status=$$status)"; cat /tmp/fpm-boot.log; exit 1; \
	 fi; \
	 echo "  ✅ fpm startet und antwortet auf /ping"
.PHONY: test-boot

# ---------------------------------------------------------------------------
# Buendel
# ---------------------------------------------------------------------------
# Reihenfolge nach Laufzeit: was ohne Image auskommt, laeuft zuerst und faellt
# damit frueh durch, statt erst nach einem Build.
test-all: test-lint test-phpini test-user test-boot test-extensions test-app-env test-uid test-opcache test-nginx ## Alle Pruefungen
	@echo ""
	@echo "✅ Alle Pruefungen bestanden — PHP $(PHP_VERSION)"
.PHONY: test-all
