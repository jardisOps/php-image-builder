# ---------------------------------------------------------------------------
# test.mk — Prueflauf
# ---------------------------------------------------------------------------
# Make orchestriert, die Skripte behaupten. Die Zusicherungen selbst stehen in
# tests/ und nicht hier: in den Bestands-Repos lagen sie als PHP-Einzeiler
# mitten im Makefile, mit `\$$`-Maskierung ueber mehrere Ebenen — unlesbar und
# ausserhalb von make nicht ausfuehrbar. Die Skripte laufen auch einzeln.
#
# TEST-IMAGES: gebaut wird ueber dieselbe support/docker-bake.hcl wie alles
# andere, nur mit einem anderen Registry-Praefix. Damit ueberschreibt ein
# Testlauf NIE die
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

# Eigener Host-Port fuer den Demo-Stack im Prueflauf: ein per `make demo-up`
# laufender Stack belegt DEMO_HTTP_PORT, und ein Testlauf soll ihn nicht
# abschiessen. Aus demselben Grund faehrt check-demo-stack.sh unter einem
# eigenen Projektnamen.
DEMO_TEST_PORT ?= 18080

TESTS_DIR = tests

# ---------------------------------------------------------------------------
# Statische Pruefung — braucht kein Image
# ---------------------------------------------------------------------------
HADOLINT_CONFIG  ?= support/hadolint.yaml
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
	  docker run --rm -i -v "$(CURDIR)/$(HADOLINT_CONFIG):/hadolint.yaml:ro" \
	    $(HADOLINT_IMAGE) hadolint --config /hadolint.yaml - < "$$f" || exit 1; \
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

test-bake: ## Aufgeloeste Bake-Definition: base-Abhaengigkeit und Tag-Satz (A1.2/A1.3/A9.2)
	@bash $(TESTS_DIR)/check-bake-graph.sh
.PHONY: test-bake

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

# Braucht --privileged: der Linux-Host ist ein docker:*-dind-Container mit
# eigenem Daemon. Das ist der Preis dafuer, den Bind-Mount-Nachweis ohne
# GitHub-Runner fuehren zu koennen (AK4/A4.5).
DIND_IMAGE ?= docker:28-dind

test-uid-linux: test-images ## UID/GID gegen einen ECHTEN Linux-Bind-Mount (AK4/A4.5, letzte Haelfte)
	@bash $(TESTS_DIR)/check-uid-linux-host.sh $(CLI_TEST_IMAGE) $(DIND_IMAGE)
.PHONY: test-uid-linux

test-nginx: test-images ## nginx-Vorlage gegen das UNVERAENDERTE offizielle Image (A6/AK7)
	@bash $(TESTS_DIR)/check-nginx-template.sh $(FPM_TEST_IMAGE) nginx:$(NGINX_VERSION)-alpine
.PHONY: test-nginx

test-demo: test-images ## Demo-Stack: ein `up`, alle Dienste healthy, DB verbunden (A8/AK9/AK12)
	@bash $(TESTS_DIR)/check-demo-stack.sh $(TEST_REGISTRY) $(DEMO_TEST_PORT)
.PHONY: test-demo

test-labels: test-images ## OCI-Labels in cli UND fpm, ueber `FROM base` vererbt (A7.4/AK8)
	@bash $(TESTS_DIR)/check-oci-labels.sh $(CLI_TEST_IMAGE) $(PHP_VERSION)-$(IMAGE_DATE)
	@bash $(TESTS_DIR)/check-oci-labels.sh $(FPM_TEST_IMAGE) $(PHP_VERSION)-$(IMAGE_DATE)
.PHONY: test-labels

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
test-all: test-lint test-bake test-phpini test-user test-boot test-labels test-extensions test-app-env test-uid test-uid-linux test-opcache test-nginx test-demo ## Alle Pruefungen
	@echo ""
	@echo "✅ Alle Pruefungen bestanden — PHP $(PHP_VERSION)"
.PHONY: test-all
