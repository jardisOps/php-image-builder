#!/bin/bash
# ---------------------------------------------------------------------------
# check-demo-stack.sh [registry] [host-port] — der Demo-Stack (A8/AK9/AK12)
# ---------------------------------------------------------------------------
# Faehrt tests/demo/demo-stack.yml hoch und misst, was der Stack belegen soll:
#
#   AK9   ein Aufruf, keine Nacharbeit — `up -d --wait` ist die Zusicherung
#         selbst: er kehrt erst zurueck, wenn jeder Dienst mit Healthcheck
#         gruen meldet, und scheitert sonst.
#   A8.1  Datenbank und Webserver laufen als UNVERAENDERTE offizielle Images.
#   A8.2  Health-Checks fuer ALLE Dienste — einzeln nachgesehen, nicht dem
#         --wait ueberlassen (siehe unten).
#   A8.3  die Vorlagen-Variablen aus P9 sind befuellt und wirken.
#   AK12  das Repo baut kein nginx-Image mehr.
#
# WARUM DIE HEALTHCHECKS EINZELN NACHGESEHEN WERDEN: `up --wait` wartet nur auf
# Dienste, die einen Healthcheck HABEN. Ein Dienst ohne einen gilt als fertig,
# sobald er laeuft. Ein Stack, dem ein Healthcheck fehlt, wuerde also gruen
# melden — die Klasse "der Test misst nichts", die in diesem Vorhaben schon
# fuenfmal zugeschlagen hatte (B11, B16, B19, B20, B21). Hier ist sie das
# sechste Mal belegt: in der Gegenprobe wurde der Healthcheck des Webservers
# entfernt, `up --wait` kehrte mit Exit 0 zurueck (B27). Deshalb wird fuer jeden
# Dienst der Health-Status abgefragt; "kein Healthcheck" ist ein Fehler.
#
# Der Stack laeuft unter einem eigenen Projektnamen und mit eigenem Port, damit
# ein parallel laufender `make demo-up` nicht gestoert wird.
set -eu

REGISTRY=${1:-php-image-builder-test}
HTTP_PORT=${2:-18080}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
STACK="$REPO_ROOT/tests/demo/demo-stack.yml"
PROJECT=demo-stack-check-$$

# Ablagen mit derselben Laufkennung wie der Projektname: zwei gleichzeitige
# Laeufe (etwa `make test-all` fuer zwei PHP-Versionen) duerfen sich weder die
# Container noch die Antwortdateien gegenseitig ueberschreiben.
UP_LOG=/tmp/demo-up-$$.log
BODY=/tmp/demo-body-$$

PASS=0; FAIL=0

compose() {
  DOCKER_HUB="$REGISTRY" DEMO_HTTP_PORT="$HTTP_PORT" \
    docker compose -f "$STACK" --project-directory "$REPO_ROOT" -p "$PROJECT" "$@"
}

cleanup() {
  compose down --volumes --remove-orphans --timeout 5 >/dev/null 2>&1 || true
  rm -f "$UP_LOG" "$BODY"
}
trap cleanup EXIT

ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — '$3' fehlt in: $(echo "$2" | head -c 200)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — '$3' steht unerwartet in der Antwort" ;; *) ok "$1" ;; esac; }

echo ">>> Demo-Stack — $STACK (Images aus $REGISTRY/, Port $HTTP_PORT)"

# ---------------------------------------------------------------------------
# AK12 — es wird nichts gebaut
# ---------------------------------------------------------------------------
# Am aufgeloesten Modell geprueft, nicht am Text der Datei: ein build:-Abschnitt
# in einem includierten Fragment wuerde in der Datei selbst nicht auftauchen.
definition=$(compose config)
if echo "$definition" | grep -qE '^\s+build:'; then
  bad "AK12 — der Stack enthaelt einen build:-Abschnitt"
else
  ok "AK12 — kein Dienst wird gebaut, alle drei laufen als fertige Images"
fi
has "A8.1 — nginx kommt als offizielles Image" "$(compose config --images | tr '\n' ' ')" "nginx:"
has "A8.1 — mariadb kommt als offizielles Image" "$(compose config --images | tr '\n' ' ')" "mariadb:"

# ---------------------------------------------------------------------------
# AK9 — ein Aufruf, keine Nacharbeit
# ---------------------------------------------------------------------------
echo ">>> up -d --wait"
if compose up -d --wait >"$UP_LOG" 2>&1; then
  ok "AK9 — ein Aufruf, keine Nacharbeit: up -d --wait kehrt gruen zurueck"
else
  bad "AK9 — der Stack kam nicht hoch"
  tail -30 "$UP_LOG"
  compose ps
  echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# A8.2 — Health-Checks fuer ALLE Dienste
# ---------------------------------------------------------------------------
for svc in db app web; do
  cid=$(compose ps -q "$svc")
  if [ -z "$cid" ]; then
    bad "A8.2 — Dienst '$svc' laeuft nicht"
    continue
  fi
  # Ein Dienst OHNE Healthcheck hat kein .State.Health — der Ausdruck liefert
  # dann "<no value>" bzw. leer. Beides ist hier ein Fehlschlag und kein
  # stillschweigendes Gruen.
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}KEIN-HEALTHCHECK{{end}}' "$cid")
  check "A8.2 — Dienst '$svc'" "$health" "healthy"
done

# ---------------------------------------------------------------------------
# Die Anwendung antwortet — ueber den veroeffentlichten Port vom Host aus
# ---------------------------------------------------------------------------
echo ">>> HTTP"
url="http://127.0.0.1:$HTTP_PORT"

status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/" || echo 000)
body=$(cat "$BODY" 2>/dev/null || true)
check "GET / — Status" "$status" "200"
has   "  Front-Controller antwortet" "$body" "PROBE=demo-app"

# Die Datenbank. Der Marker traegt die Serverkennung aus SELECT VERSION(); die
# Demo-App schreibt bei einem Verbindungsfehler "FEHLER: ..." an dieselbe
# Stelle. Geprueft wird der herausgeloeste Wert und nicht bloss, DASS "DB="
# vorkommt — sonst wuerde eine gescheiterte Verbindung als Erfolg durchgehen.
dbv=$(sed -n 's/^<!-- PROBE=demo-app DB=\(.*\) -->$/\1/p' "$BODY" | head -1)
if echo "$dbv" | grep -qE '^[0-9]+\.[0-9]+'; then
  ok "A8.1 — Verbindung zur Datenbank steht (SELECT VERSION() = $dbv)"
else
  bad "A8.1 — Datenbank antwortet nicht mit einer Version: '$dbv'"
fi

# A8.3 — die Vorlagen-Variablen wirken im Stack, nicht nur im Prueflauf aus P9.
has   "A8.3 — SERVER_NAME aus HOST" "$body" "<th>SERVER_NAME</th>"
has   "A8.3 — REQUEST_SCHEME=http"  "$body" "<td>http</td>"
# A6.2: ohne TLS-Proxy darf HTTPS gar nicht ankommen. Die Zeile existiert, ihr
# Wert ist "<nicht uebergeben>" — ein "on" irgendwo in der Tabelle waere der
# fest verdrahtete Zustand des Bestands.
has   "A8.3 — HTTPS-Zeile vorhanden" "$body" "<th>HTTPS</th>"
hasnt "A8.3 — HTTPS wird nicht uebergeben (A6.2)" "$body" "<td>on</td>"

# PATH_INFO — der Grund, aus dem die Vorlage eine eigene Location dafuer hat.
status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/index.php/foo/bar" || echo 000)
check "GET /index.php/foo/bar — Status" "$status" "200"
has   "  PATH_INFO kommt an" "$(cat "$BODY")" "<td>/foo/bar</td>"

# Statische Auslieferung: nginx antwortet ohne php-fpm. Das ist derselbe Weg,
# den der Healthcheck des Webservers geht.
status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/health.txt" || echo 000)
check "GET /health.txt — Status" "$status" "200"
check "  Inhalt unveraendert"     "$(tr -d '\n' < "$BODY")" "demo-stack-ok"

status=$(curl -s -o /dev/null -w '%{http_code}' "$url/demo.css" || echo 000)
check "GET /demo.css — Status (Static-Location)" "$status" "200"

# Verborgenes bleibt verboten.
status=$(curl -s -o /dev/null -w '%{http_code}' "$url/.env" || echo 000)
check "GET /.env — Status" "$status" "404"

# ---------------------------------------------------------------------------
# Abbau
# ---------------------------------------------------------------------------
echo ">>> down"
compose down --volumes --remove-orphans >/dev/null 2>&1
left=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | wc -l | tr -d ' ')
check "nach down keine Container mehr uebrig" "$left" "0"

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
