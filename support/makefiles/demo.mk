# ---------------------------------------------------------------------------
# demo.mk — the demo stack
# ---------------------------------------------------------------------------
# Thin wrapper around `docker compose`, for the same reason the build targets
# wrap `bake`: two switches nobody wants to type by hand every time.
#
#   --project-directory .   otherwise compose treats tests/demo/ as the project
#                           directory and never finds the root .env, leaving
#                           every variable empty.
#   DOCKER_HUB=...          the stack points at headgent/phpfpm:<ver>, as a
#                           project would write it. Until the first push that
#                           name only holds an unrunnable image, so the stack
#                           uses the locally built test images instead.
#
# After the first push the second switch simply drops out:
#   make demo-up DEMO_REGISTRY=$(DOCKER_HUB)
# ---------------------------------------------------------------------------
##@ Demo Stack

DEMO_FILE     ?= tests/demo/demo-stack.yml
DEMO_REGISTRY ?= $(TEST_REGISTRY)

# --wait turns the health guarantee into a start condition: the call only
# returns once every service with a healthcheck reports green, and fails
# visibly otherwise.
DEMO_COMPOSE = DOCKER_HUB=$(DEMO_REGISTRY) \
               docker compose -f $(DEMO_FILE) --project-directory .

demo-up: test-images ## Start the demo stack: mariadb + fpm + official nginx
	@echo "🚀 Starting the demo stack (images from $(DEMO_REGISTRY)/) ..."
	@$(DEMO_COMPOSE) up -d --wait
	@echo ""
	@echo "✅ Reachable at http://localhost:$(DEMO_HTTP_PORT)"
	@echo "   Tear down with: make demo-down"
.PHONY: demo-up

demo-down: ## Tear down the demo stack (containers, network, and volumes)
	@$(DEMO_COMPOSE) down --volumes --remove-orphans
	@echo "✅ Demo stack torn down"
.PHONY: demo-down

demo-logs: ## Follow the demo stack logs
	@$(DEMO_COMPOSE) logs -f
.PHONY: demo-logs

demo-config: ## Show the resolved stack definition (starts nothing)
	@$(DEMO_COMPOSE) config
.PHONY: demo-config
