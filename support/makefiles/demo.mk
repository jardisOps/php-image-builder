# ---------------------------------------------------------------------------
# demo.mk — Demo-Stack (A8, P10)
# ---------------------------------------------------------------------------
# Duenner Wrapper um `docker compose`, aus demselben Grund, aus dem die
# Build-Targets duenne Wrapper um `bake` sind: der Aufruf traegt zwei Griffe,
# die man nicht jedes Mal von Hand richtig hinschreiben will.
#
#   --project-directory .   Compose nimmt sonst compose/ als Projektverzeichnis
#                           und findet die .env im Root nicht — jede Variable
#                           waere leer (gemessen 2026-07-25).
#   DOCKER_HUB=...          Der Stack verweist auf headgent/phpfpm:<ver>, wie
#                           ein Projekt es schreiben wuerde. Unter diesem Namen
#                           liegt bis zum ersten Push (N6) aber nur der
#                           Bestand, und der ist startunfaehig (B9). Bis dahin
#                           faehrt der Stack die lokal gebauten Test-Images.
#
# Nach dem ersten Push entfaellt der zweite Griff ersatzlos:
#   make demo-up DEMO_REGISTRY=$(DOCKER_HUB)
# ---------------------------------------------------------------------------
##@ Demo-Stack

DEMO_FILE     ?= compose/demo-stack.yml
DEMO_REGISTRY ?= $(TEST_REGISTRY)

# Das --wait macht die Zusicherung aus A8.2 zur Startbedingung: der Aufruf
# kehrt erst zurueck, wenn jeder Dienst mit Healthcheck gruen meldet, und
# scheitert sonst sichtbar.
DEMO_COMPOSE = DOCKER_HUB=$(DEMO_REGISTRY) \
               docker compose -f $(DEMO_FILE) --project-directory .

demo-up: test-images ## Demo-Stack starten: mariadb + fpm + offizielles nginx
	@echo "🚀 Demo-Stack startet (Images aus $(DEMO_REGISTRY)/) ..."
	@$(DEMO_COMPOSE) up -d --wait
	@echo ""
	@echo "✅ Erreichbar unter http://localhost:$(DEMO_HTTP_PORT)"
	@echo "   Abbauen mit: make demo-down"
.PHONY: demo-up

demo-down: ## Demo-Stack abbauen (Container, Netz und Volumes)
	@$(DEMO_COMPOSE) down --volumes --remove-orphans
	@echo "✅ Demo-Stack abgebaut"
.PHONY: demo-down

demo-logs: ## Logs des Demo-Stacks folgen
	@$(DEMO_COMPOSE) logs -f
.PHONY: demo-logs

demo-config: ## Aufgeloeste Stack-Definition zeigen (startet nichts)
	@$(DEMO_COMPOSE) config
.PHONY: demo-config
