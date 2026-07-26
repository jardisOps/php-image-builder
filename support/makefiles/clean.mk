# ---------------------------------------------------------------------------
# clean.mk — reclaiming disk space
# ---------------------------------------------------------------------------
# A build tool produces waste: test images under two names times three
# versions, dangling layers from every aborted run, the buildx cache. These
# targets clean that up without having to remember the docker invocations.
#
# THE RULE ALL TARGETS HERE FOLLOW: only touch what THIS repo produced — the
# references come from .env, not a glob over everything local. A
# `docker system prune` as a convenient blanket sweep would be wrong here: a
# development machine also holds images, volumes, and containers from other
# projects, and those are none of this repo's business.
#
# Exactly ONE target deliberately breaks the rule: `clean-system`. It is
# global, it is dangerous, and it is therefore locked behind CONFIRM=ja and
# shows what it costs beforehand.
#
# None of this is wired into `test-all`. These targets delete exactly the
# artifacts the test run checks against — they belong next to it, not inside
# it.
# ---------------------------------------------------------------------------
##@ Cleanup

# The four references this repo produces locally: the test images from the
# test run and the published names once `make build` has run. Derived from
# .env — no separately maintained name.
CLEAN_TEST_REFS = $(TEST_REGISTRY)/$(IMAGE_NAME_CLI) $(TEST_REGISTRY)/$(IMAGE_NAME_FPM)
CLEAN_PUB_REFS  = $(CLI_IMAGE) $(FPM_IMAGE)

# Pre-set to empty because the root Makefile runs with
# --warn-undefined-variables: `clean-system` checks CONFIRM, and an unset
# variable should mean a refusal, not a make warning.
CONFIRM ?=

# ---------------------------------------------------------------------------
# drop_images — removes all tags of the repositories in CLEAN_REFS
# ---------------------------------------------------------------------------
# `--filter=reference=<repo>` without a tag matches ALL tags of that
# repository, so the repository names suffice without a tag list that would
# go stale with every IMAGE_DATE.
#
# Containers first: a container based on the image blocks deletion. The
# `ancestor` filter also finds stopped remnants of an aborted test run, but it
# matches on the image ID rather than the tag, so the message names the
# removed containers rather than attributing them to a tag they may not carry.
#
# References come in via CLEAN_REFS as a target-specific variable rather than
# a $(call) argument, because the root Makefile runs with
# --warn-undefined-variables and would warn about the positional variable
# $(1) in the define body.
#
# Errors are NOT swallowed (no `|| true` on the docker call): a failed rmi
# must be visible instead of passing as "cleaned up". An empty result is not
# an error and is reported as such.
CLEAN_REFS ?=

define drop_images
	@for ref in $(CLEAN_REFS); do \
	  tags=$$(docker images --filter=reference="$$ref" --format '{{.Repository}}:{{.Tag}}' | sort -u); \
	  if [ -z "$$tags" ]; then \
	    echo "  · $$ref — nothing present"; \
	    continue; \
	  fi; \
	  for tag in $$tags; do \
	    cids=$$(docker ps -aq --filter ancestor="$$tag"); \
	    if [ -n "$$cids" ]; then \
	      names=$$(docker ps -a --filter ancestor="$$tag" --format '{{.Names}}' | tr '\n' ' '); \
	      docker rm -f $$cids >/dev/null; \
	      echo "  🗑  Removed containers on the same layer: $$names"; \
	    fi; \
	    docker rmi "$$tag" >/dev/null; \
	    echo "  🗑  $$tag"; \
	  done; \
	done
endef

disk-usage: ## What Docker uses and how much of it comes from this repo (deletes nothing)
	@docker system df
	@echo ""
	@echo "From this repo:"
	@for ref in $(CLEAN_TEST_REFS) $(CLEAN_PUB_REFS); do \
	  docker images --filter=reference="$$ref" \
	    --format '  {{.Repository}}:{{.Tag}}	{{.Size}}'; \
	done
	@echo ""
	@echo "  dangling layers (<none>): $$(docker images --filter dangling=true -q | wc -l | tr -d ' ')"
.PHONY: disk-usage

clean-test-images: CLEAN_REFS = $(CLEAN_TEST_REFS)
clean-test-images: ## Remove the test run's test images (all versions)
	@echo ">>> Test images under $(TEST_REGISTRY)/"
	$(drop_images)
.PHONY: clean-test-images

clean-images: CLEAN_REFS = $(CLEAN_PUB_REFS)
clean-images: ## Remove locally built headgent/*-images (all versions)
	@echo ">>> $(CLI_IMAGE) and $(FPM_IMAGE)"
	@echo "    Note: also affects images pulled from the registry under this name."
	$(drop_images)
.PHONY: clean-images

# An honest exception to the repo rule: a dangling layer carries no name, so
# there is no way to tell whose build it came from — `docker image prune`
# necessarily removes them all, machine-wide. It is the usual, safe operation
# (an untagged layer is referenced by no image), just not scoped to this repo.
clean-dangling: ## Remove dangling layers (<none>) — remnants of aborted builds, machine-wide
	@n=$$(docker images --filter dangling=true -q | wc -l | tr -d ' '); \
	if [ "$$n" = "0" ]; then \
	  echo "  · no dangling layers"; \
	else \
	  docker image prune -f; \
	fi
.PHONY: clean-dangling

clean-cache: build-cache-delete ## Clear the buildx cache (alias for build-cache-delete)
.PHONY: clean-cache

# No `2>/dev/null || true`: `compose down` returns 0 even when nothing is
# running and stays silent about it, so suppressing errors here would only
# hide real ones, not add leniency.
clean-demo: ## Remove demo stack remnants (containers, network, volumes)
	@$(DEMO_COMPOSE) down --volumes --remove-orphans
	@echo "  · demo stack: nothing left"
.PHONY: clean-demo

clean: clean-demo clean-test-images clean-dangling ## The usual case: test images, demo remnants, and dangling layers
	@echo ""
	@echo "✅ Cleaned up. Not touched: the buildx cache (make clean-cache),"
	@echo "   the headgent/*-images (make clean-images), and anything foreign."
.PHONY: clean

clean-all: clean clean-images clean-cache ## Everything from this repo: also headgent/* and the buildx cache
	@echo ""
	@echo "✅ All artifacts of this repo removed. The next test run builds fresh."
.PHONY: clean-all

# ---------------------------------------------------------------------------
# clean-system — the global sledgehammer
# ---------------------------------------------------------------------------
# The only target here that reaches beyond this repo: it removes EVERY unused
# image, network, and volume on this machine, including other projects'. Two
# safeguards: it shows what is at stake first, and it requires CONFIRM=ja —
# without that word, nothing happens.
#
# `$(strip ...)` fixes a real asymmetry: make itself strips leading spaces from
# a command-line assignment, so `CONFIRM=" ja"` used to pass while
# `CONFIRM="ja "` did not. Now surrounding whitespace never matters — anything
# other than exactly `ja` aborts.
clean-system: ## GLOBAL: everything unused on this machine (requires CONFIRM=ja)
	@docker system df
	@echo ""
	@if [ "$(strip $(CONFIRM))" != "ja" ]; then \
	  echo "⚠️  This removes EVERY unused image, network, and volume on this"; \
	  echo "    machine — including other projects'. For this repo alone:"; \
	  echo "    make clean-all"; \
	  echo ""; \
	  echo "    If it really should be global:  make clean-system CONFIRM=ja"; \
	  exit 1; \
	fi
	@docker system prune -a --volumes -f
.PHONY: clean-system
