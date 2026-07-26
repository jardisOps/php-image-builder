# ---------------------------------------------------------------------------
# clean.mk — Platz zurueckholen
# ---------------------------------------------------------------------------
# Ein Bauwerkzeug erzeugt Muell: Test-Images unter zwei Namen mal drei
# Versionen, baumelnde Layer aus jedem abgebrochenen Lauf, den buildx-Cache.
# Befund B15 (`build-all` uebersetzt drei PHP-Versionen gleichzeitig) macht
# daraus regelmaessig ein "No space left on device". Diese Targets raeumen das
# auf, ohne dass man sich die docker-Aufrufe merken muss.
#
# DIE REGEL, DIE ALLE TARGETS HIER EINHALTEN: angefasst wird ausschliesslich,
# was DIESES Repo erzeugt hat — die Referenzen stammen aus der .env, nicht aus
# einem Glob ueber alles Lokale. Ein `docker system prune` als bequemer
# Rundumschlag waere hier falsch: auf einem Entwicklungsrechner liegen fremde
# Images, Volumes und Container daneben, und die gehen dieses Repo nichts an.
#
# Genau EIN Target bricht die Regel bewusst: `clean-system`. Es ist global, es
# ist gefaehrlich, und es ist deshalb hinter CONFIRM=ja verriegelt und zeigt
# vorher an, was es kostet.
#
# Nichts hiervon haengt an `test-all`. Diese Targets loeschen genau die
# Artefakte, gegen die der Prueflauf prueft — sie gehoeren nicht in ihn hinein,
# sondern daneben.
# ---------------------------------------------------------------------------
##@ Aufraeumen

# Die vier Referenzen, die dieses Repo lokal erzeugt: die Test-Images des
# Prueflaufs und die publizierten Namen, wenn `make build` gelaufen ist.
# Abgeleitet aus der .env (A2.1) — kein zweitgepflegter Name.
CLEAN_TEST_REFS = $(TEST_REGISTRY)/$(IMAGE_NAME_CLI) $(TEST_REGISTRY)/$(IMAGE_NAME_FPM)
CLEAN_PUB_REFS  = $(CLI_IMAGE) $(FPM_IMAGE)

# Leer vorbelegt, weil das Root-Makefile mit --warn-undefined-variables laeuft:
# `clean-system` fragt CONFIRM ab, und eine nicht gesetzte Variable soll dabei
# eine Absage sein, keine Make-Warnung.
CONFIRM ?=

# ---------------------------------------------------------------------------
# drop_images — entfernt alle Tags der Repositories in CLEAN_REFS
# ---------------------------------------------------------------------------
# `--filter=reference=<repo>` ohne Tag trifft ALLE Tags dieses Repositories
# (geprueft am 2026-07-26) — deshalb genuegen die Repository-Namen und es
# braucht keine Tag-Liste, die mit jedem IMAGE_DATE veraltet.
#
# Container zuerst: ein Container, der auf dem Image beruht, blockiert das
# Loeschen. Der `ancestor`-Filter findet auch gestoppte Reste eines
# abgebrochenen Prueflaufs.
#
# ABER: `ancestor` arbeitet auf der Image-ID, nicht auf dem Tag (Befund B34,
# aufgefallen an der Attrappe, wo drei Tags auf dieselbe ID zeigten). Die
# Meldung nennt deshalb die entfernten Container beim Namen, statt sie einem
# Tag zuzuschreiben, den sie moeglicherweise gar nicht haben.
#
# Die Referenzen kommen ueber CLEAN_REFS als target-spezifische Variable statt
# als $(call)-Argument: das Root-Makefile laeuft mit --warn-undefined-variables,
# und Make warnt dort ueber die Positionsvariable $(1) im define-Rumpf.
#
# Fehler werden NICHT verschluckt (kein `|| true` am docker-Aufruf): schlaegt
# ein rmi fehl, soll das sichtbar sein statt als "aufgeraeumt" durchzugehen.
# Ein leeres Ergebnis ist dagegen kein Fehler und wird als solches gemeldet.
CLEAN_REFS ?=

define drop_images
	@for ref in $(CLEAN_REFS); do \
	  tags=$$(docker images --filter=reference="$$ref" --format '{{.Repository}}:{{.Tag}}' | sort -u); \
	  if [ -z "$$tags" ]; then \
	    echo "  · $$ref — nichts vorhanden"; \
	    continue; \
	  fi; \
	  for tag in $$tags; do \
	    cids=$$(docker ps -aq --filter ancestor="$$tag"); \
	    if [ -n "$$cids" ]; then \
	      names=$$(docker ps -a --filter ancestor="$$tag" --format '{{.Names}}' | tr '\n' ' '); \
	      docker rm -f $$cids >/dev/null; \
	      echo "  🗑  Container auf demselben Layer entfernt: $$names"; \
	    fi; \
	    docker rmi "$$tag" >/dev/null; \
	    echo "  🗑  $$tag"; \
	  done; \
	done
endef

disk-usage: ## Was Docker belegt und was davon aus diesem Repo stammt (loescht nichts)
	@docker system df
	@echo ""
	@echo "Aus diesem Repo:"
	@for ref in $(CLEAN_TEST_REFS) $(CLEAN_PUB_REFS); do \
	  docker images --filter=reference="$$ref" \
	    --format '  {{.Repository}}:{{.Tag}}	{{.Size}}'; \
	done
	@echo ""
	@echo "  baumelnde Layer (<none>): $$(docker images --filter dangling=true -q | wc -l | tr -d ' ')"
.PHONY: disk-usage

clean-test-images: CLEAN_REFS = $(CLEAN_TEST_REFS)
clean-test-images: ## Test-Images des Prueflaufs entfernen (alle Versionen)
	@echo ">>> Test-Images unter $(TEST_REGISTRY)/"
	$(drop_images)
.PHONY: clean-test-images

clean-images: CLEAN_REFS = $(CLEAN_PUB_REFS)
clean-images: ## Lokal gebaute headgent/*-Images entfernen (alle Versionen)
	@echo ">>> $(CLI_IMAGE) und $(FPM_IMAGE)"
	@echo "    Hinweis: trifft auch die aus der Registry gezogenen Bestands-Images."
	$(drop_images)
.PHONY: clean-images

# Einschraenkung der Repo-Regel, ehrlich benannt: ein baumelnder Layer traegt
# keinen Namen, also laesst sich nicht feststellen, aus wessen Build er stammt —
# `docker image prune` raeumt sie zwangslaeufig alle. Das ist die uebliche und
# ungefaehrliche Operation (ein Layer ohne Tag wird von keinem Image mehr
# referenziert), aber es ist nicht auf dieses Repo begrenzt, und das soll hier
# stehen statt beschoenigt zu werden.
clean-dangling: ## Baumelnde Layer (<none>) entfernen — Reste abgebrochener Builds, rechnerweit
	@n=$$(docker images --filter dangling=true -q | wc -l | tr -d ' '); \
	if [ "$$n" = "0" ]; then \
	  echo "  · keine baumelnden Layer"; \
	else \
	  docker image prune -f; \
	fi
.PHONY: clean-dangling

clean-cache: build-cache-delete ## buildx-Cache leeren (Alias auf build-cache-delete)
.PHONY: clean-cache

# Kein `2>/dev/null || true`: `compose down` kehrt auch dann mit 0 zurueck, wenn
# gar nichts laeuft (geprueft am 2026-07-26), und schweigt dabei. Eine
# Fehlerunterdrueckung waere also nicht Nachsicht, sondern wuerde nur echte
# Fehler verstecken — genau das Muster, an dem der Bestand gescheitert ist (U1).
clean-demo: ## Reste des Demo-Stacks entfernen (Container, Netz, Volumes)
	@$(DEMO_COMPOSE) down --volumes --remove-orphans
	@echo "  · Demo-Stack: nichts mehr uebrig"
.PHONY: clean-demo

clean: clean-demo clean-test-images clean-dangling ## Der Regelfall: Test-Images, Demo-Reste und baumelnde Layer
	@echo ""
	@echo "✅ Aufgeraeumt. Nicht angefasst: der buildx-Cache (make clean-cache),"
	@echo "   die headgent/*-Images (make clean-images) und alles Fremde."
.PHONY: clean

clean-all: clean clean-images clean-cache ## Alles aus diesem Repo: zusaetzlich headgent/* und der buildx-Cache
	@echo ""
	@echo "✅ Alle Artefakte dieses Repos entfernt. Der naechste Prueflauf baut neu."
.PHONY: clean-all

# ---------------------------------------------------------------------------
# clean-system — der globale Vorschlaghammer
# ---------------------------------------------------------------------------
# Das einzige Target hier, das ueber dieses Repo hinausgreift: es entfernt JEDES
# ungenutzte Image, Netz und Volume auf diesem Rechner, auch die fremder
# Projekte. Deshalb zwei Sicherungen: es zeigt erst, worum es geht, und es
# verlangt CONFIRM=ja. Ohne das Wort passiert nichts — ein versehentlich
# getipptes `make clean-system` soll nicht der Moment sein, in dem die Images
# eines anderen Projekts verschwinden.
#
# `$(strip ...)` ist kein Schoenheitsfehler, sondern behebt eine gemessene
# Asymmetrie: Make entfernt bei einer Kommandozeilen-Zuweisung fuehrende
# Leerzeichen selbst, `CONFIRM=" ja"` kam also durch — `CONFIRM="ja "` dagegen
# nicht. Eine Verriegelung, die je nach Seite des Leerzeichens anders
# entscheidet, ist keine. Jetzt gilt einheitlich: umgebende Leerzeichen sind
# egal, alles andere als genau `ja` bricht ab.
clean-system: ## GLOBAL: alles Ungenutzte auf diesem Rechner (verlangt CONFIRM=ja)
	@docker system df
	@echo ""
	@if [ "$(strip $(CONFIRM))" != "ja" ]; then \
	  echo "⚠️  Das entfernt JEDES ungenutzte Image, Netz und Volume auf diesem"; \
	  echo "    Rechner — auch die fremder Projekte. Fuer dieses Repo allein:"; \
	  echo "    make clean-all"; \
	  echo ""; \
	  echo "    Wenn es wirklich global sein soll:  make clean-system CONFIRM=ja"; \
	  exit 1; \
	fi
	@docker system prune -a --volumes -f
.PHONY: clean-system
