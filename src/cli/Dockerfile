# ---------------------------------------------------------------------------
# cli — publiziert als headgent/phpcli (E2, Name unveraendert)
# ---------------------------------------------------------------------------
# Zweck: Worker, Queue-Consumer, Cron, CI- und Build-Kontext.
#
# Alles Inhaltliche steht in base: PHP-Version, Extensions, Composer,
# Laufzeit-Bibliotheken, appuser, Entrypoint-Kern, INI-Ladereihenfolge, WORKDIR.
# Hier steht nur noch, was aus dem Einsatzzweck folgt — und das sind genau die
# drei Werte, die ein Image nur EINMAL tragen kann und die zwischen Worker- und
# Request-Betrieb entgegengesetzt sein muessen (max_execution_time, STOPSIGNAL,
# HEALTHCHECK). Genau daran haengt, dass cli und fpm zwei Artefakte bleiben.
#
# `FROM base` wird von support/docker-bake.hcl ueber
# contexts = { base = "target:base" } aufgeloest (A1.2) — base wird dabei nicht
# publiziert.
#
# DL3006 ("always tag the version explicitly") ist hier ein Fehlalarm: `base` ist
# ein benannter Build-Context, kein Registry-Image — es gibt nichts zu taggen.
# hadolint kennt das bake-Konzept nicht. Der Ignore steht bewusst inline und
# nicht in support/hadolint.yaml, damit ein echtes ungetaggtes FROM in einem
# kuenftigen Dockerfile weiterhin auffaellt.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base

# Der einzige der 13 Pflichtwerte, den base nicht setzt: er folgt dem Prozesstyp,
# nicht der Umgebung (A2.5, begruendetes Delta zu D10). Ein langlaufender Worker
# oder Queue-Consumer darf kein Zeitlimit haben — 0 heisst unbegrenzt. Der
# Schluesselname traegt das _CLI, damit die .env beide Werte nebeneinander
# pflegen kann; im Image heisst er wieder wie die PHP-Einstellung.
ARG PHP_MAX_EXECUTION_TIME_CLI
ENV PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME_CLI}

# Korrigiert das aus dem fpm-Basisimage geerbte SIGQUIT (Befund B6/N5). SIGQUIT
# ist FPMs Signal fuer einen graceful shutdown; ein PHP-Worker kennt es nicht als
# solches und wuerde stattdessen hart abgebrochen. SIGTERM ist das Signal, auf
# das pcntl-basierte Worker-Schleifen hoeren.
STOPSIGNAL SIGTERM

# Geprueft wird, was dieses Image ausmacht: ein lauffaehiger PHP-Interpreter und
# ein benutzbarer Composer. Uebernommen aus phpcli/src/Dockerfile:130-131.
# Bewusst NICHT der FastCGI-Ping des fpm-Targets — hier lauscht kein FPM, der
# Container waere dauerhaft unhealthy.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD sh -c "php --version >/dev/null && composer --version >/dev/null"

# Geerbt und bewusst stehengelassen: EXPOSE 9000 aus dem fpm-Basisimage. Docker
# kennt kein "unexpose"; die Zeile ist reine Metadatenangabe und oeffnet nichts
# (Befund B6).
CMD ["php","--version"]
