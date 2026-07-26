#!/bin/bash
# ---------------------------------------------------------------------------
# check-nginx-template.sh <fpm-image> [nginx-image] — die nginx-Vorlage (A6/AK7)
# ---------------------------------------------------------------------------
# Prueft compose/nginx/templates/default.conf.template gegen das UNVERAENDERTE
# offizielle nginx-Image: kein eigener Entrypoint, kein eigener Build (A6.3).
# Der Aufbau ist derselbe, den ein Projekt fahren soll — fpm-Container plus
# offizielles nginx, gemeinsames /app.
#
# Zwei Instanzen, weil eine allein nichts beweist:
#
#   A  nur die Defaults-Datei, sonst nichts (A6.4). Belegt, dass der Stack ohne
#      jede eigene Konfiguration laeuft.
#   B  jeder Wert ueberschrieben. Belegt, dass die Variablen wirklich wirken und
#      nicht bloss zufaellig zum Default passen — sonst waere das ein Test der
#      Klasse B11/B16/B19/B20: misst nichts, meldet gruen.
#
# Gemessen wird an $_SERVER im PHP-Prozess und an Statuscodes, nicht an der
# erzeugten Konfigurationsdatei allein. Die Textpruefung der gerenderten Datei
# kommt dazu, wo eine Wirkung nicht bezahlbar messbar ist (send/connect-Timeout).
set -eu

FPM_IMAGE=${1:?Aufruf: check-nginx-template.sh <fpm-image> [nginx-image]}
NGINX_IMAGE=${2:-nginx:1.28-alpine}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMPLATES="$REPO_ROOT/compose/nginx/templates"
DEFAULTS="$REPO_ROOT/compose/nginx/nginx-defaults.env"

SFX=$$
NET=check-nginx-net-$SFX
VOL=check-nginx-app-$SFX
APP=app                      # Service-Name = FASTCGI_UPSTREAM-Default
WEB_A=check-nginx-a-$SFX
WEB_B=check-nginx-b-$SFX

PASS=0; FAIL=0

cleanup() {
  docker rm -f "$WEB_A" "$WEB_B" "$APP-$SFX" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  docker volume rm "$VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

# ---------------------------------------------------------------------------
# Aufbau: ein fpm-Container plus ein gemeinsames /app-Volume
# ---------------------------------------------------------------------------
# Die Sonden werden per `docker exec` in das Volume geschrieben, nicht per
# Bind-Mount: so haengt der Test nicht an den Eigentums-Eigenheiten der
# Docker-Desktop-Dateibruecke (vgl. B20).
docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null

docker run -d --name "$APP-$SFX" --network "$NET" --network-alias "$APP" \
  -v "$VOL:/app" "$FPM_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-$SFX" 2>/dev/null)" = healthy ] && break
  sleep 1
done
if [ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-$SFX" 2>/dev/null)" != healthy ]; then
  echo "  ❌ fpm-Container wurde nicht healthy — Abbruch"
  docker logs "$APP-$SFX" 2>&1 | tail -20
  exit 1
fi

# Sonde: gibt die $_SERVER-Werte aus, an denen die Vorlage gemessen wird.
# ?sleep=N haelt den Request auf, damit FASTCGI_READ_TIMEOUT messbar wird.
write_probe() { # <verzeichnis> <dateiname> <marke>
  docker exec "$APP-$SFX" sh -c "mkdir -p '$1' && cat > '$1/$2' <<'PHP'
<?php
if (isset(\$_GET['sleep'])) { sleep((int) \$_GET['sleep']); }
\$keys = ['REQUEST_SCHEME','HTTPS','PATH_INFO','SCRIPT_FILENAME','DOCUMENT_ROOT',
         'HTTP_X_FORWARDED_PROTO','REQUEST_URI','SERVER_NAME',
         'REQUEST_METHOD','CONTENT_LENGTH'];
\$out = 'PROBE=$3';
foreach (\$keys as \$k) { \$out .= ' ' . \$k . '=' . (\$_SERVER[\$k] ?? '-'); }
echo \$out;
PHP"
}

write_probe /app/public index.php index    # Default-Dokumentwurzel
write_probe /app/public info.php  info     # Fallback-Location (echte .php-Datei)
write_probe /app/web    app.php   alt      # abweichende DOCUMENT_ROOT/INDEX_FILE

# Haertungs-Sonden (O6, Abschnitt ganz unten).
#
#   upload.jpg    eine ECHTE hochgeladene Datei mit PHP-Code darin. Nur damit
#                 ist messbar, ob /upload.jpg/x.php sie ausfuehrt (B24).
#   exec-check.php dieselbe Zeile als echte .php-Datei — die Positivprobe. Sie
#                 belegt, dass der Inhalt ueberhaupt ausfuehrbar ist; ohne sie
#                 koennte ein 404 auf die .jpg-Kette auch bedeuten, dass die
#                 Messung ins Leere greift (Klasse B11/B19/B21).
#   a.css         eine statische Datei fuer die Header-Pruefung (B25).
MARKE=AUSGEFUEHRT-$SFX
PHP_ZEILE="<?php echo \"$MARKE\";"
docker exec "$APP-$SFX" sh -c "printf '%s' '$PHP_ZEILE' > /app/public/upload.jpg"
docker exec "$APP-$SFX" sh -c "printf '%s' '$PHP_ZEILE' > /app/public/exec-check.php"
docker exec "$APP-$SFX" sh -c "printf '%s' 'body{color:#000}' > /app/public/a.css"

start_web() { # <container> <env...>
  local name=$1; shift
  docker run -d --name "$name" --network "$NET" \
    --env-file "$DEFAULTS" "$@" \
    -v "$TEMPLATES:/etc/nginx/templates:ro" \
    -v "$VOL:/app:ro" \
    "$NGINX_IMAGE" >/dev/null
  for _ in $(seq 1 20); do
    docker exec "$name" wget -q -O /dev/null --spider http://127.0.0.1/ 2>/dev/null && return 0
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || break
    sleep 1
  done
  echo "  ❌ $name antwortet nicht — erzeugte Konfiguration und Log:"
  docker logs "$name" 2>&1 | tail -20
  return 1
}

# Antwort holen: erste Zeile = Statuscode, zweite = Rumpf.
# Die Rumpfdatei wird vorher geleert: bei 4xx/5xx legt wget sie nicht an, und ein
# Rest aus dem vorigen Aufruf wuerde als Antwort dieses Aufrufs gelesen.
resp() { # <container> <pfad> [wget-zusatz...]
  local c=$1 p=$2; shift 2
  docker exec "$c" sh -c "
    : > /tmp/body
    wget -S -O /tmp/body $* 'http://127.0.0.1$p' 2>/tmp/hdr || true
    grep -om1 'HTTP/1\.[01] [0-9][0-9][0-9]' /tmp/hdr | grep -oE '[0-9]{3}' | head -1 || true
    tr -d '\r' < /tmp/body | tail -1"
}
status() { echo "$1" | head -1; }
body()   { echo "$1" | tail -1; }

# Antwort-Header holen. busybox-wget schreibt sie mit -S nach stderr, jede Zeile
# eingerueckt und mit CR am Ende.
hdrs() { # <container> <pfad>
  docker exec "$1" sh -c "wget -S -O /dev/null 'http://127.0.0.1$2' 2>&1 | tr -d '\r'" || true
}
# <header-block> <name> <erwarteter Teilstring im Wert>
# $2 und $3 landen als Teil eines grep-Musters, nicht als Festtext: alle
# Aufrufer unten uebergeben Literale ohne Regex-Sonderzeichen. Wer hier einen
# Wert mit '.', '[' oder '*' einsetzt, muss ihn maskieren — sonst matcht das
# Muster weiter, aber nicht mehr das Gemeinte.
has_header() { echo "$1" | grep -qi "^[[:space:]]*$2:.*$3"; }
field()  { # <rumpf> <schluessel>
  echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"
}

# ---------------------------------------------------------------------------
# Instanz A — nur die Defaults-Datei (A6.4)
# ---------------------------------------------------------------------------
echo ">>> Instanz A — $NGINX_IMAGE, nur $(basename "$DEFAULTS")"
start_web "$WEB_A" || { FAIL=$((FAIL + 1)); echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"; exit 1; }
ok "startet ohne eigene Konfiguration und ohne eigenen Entrypoint (A6.3/A6.4)"

# Nichts darf unsubstituiert stehengeblieben sein. envsubst laesst eine fehlende
# Variable als ${NAME} stehen; nginx bricht dann ab — aber nicht immer sichtbar
# an der Ursache, deshalb hier ausdruecklich.
rendered=$(docker exec "$WEB_A" cat /etc/nginx/conf.d/default.conf)
# SC2016 ist hier der Zweck, kein Versehen: gesucht wird die Zeichenfolge
# Dollar-Klammer selbst. Wuerde sie expandiert, suchte der Test nach dem Wert
# einer Variablen statt nach dem unersetzten Platzhalter — und faende nie etwas.
# shellcheck disable=SC2016
if echo "$rendered" | grep -q '\${'; then
  bad "unsubstituierte Variablen in der erzeugten Konfiguration: $(echo "$rendered" | grep -o '\${[A-Z_]*}' | sort -u | tr '\n' ' ')"
else
  ok "keine unsubstituierte Variable in der erzeugten Konfiguration"
fi

# Die drei Werte, deren Wirkung nicht bezahlbar messbar ist, werden am Rendering
# geprueft. fastcgi_pass steht zweimal (Location 2 und 3) und muss beide Male
# aus FASTCGI_UPSTREAM/PHP_PORT kommen.
check "fastcgi_pass app:9000 (2x)"        "$(echo "$rendered" | grep -c 'fastcgi_pass   app:9000;')"      "2"
check "client_max_body_size 100m"         "$(echo "$rendered" | grep -c 'client_max_body_size 100m;')"     "1"
check "fastcgi_read_timeout 600 (2x)"     "$(echo "$rendered" | grep -c 'fastcgi_read_timeout    600;')"   "2"
check "fastcgi_send_timeout 600 (2x)"     "$(echo "$rendered" | grep -c 'fastcgi_send_timeout    600;')"   "2"
check "fastcgi_connect_timeout 300 (2x)"  "$(echo "$rendered" | grep -c 'fastcgi_connect_timeout 300;')"   "2"

# Front-Controller: try_files faellt auf ${INDEX_FILE} zurueck.
r=$(resp "$WEB_A" /nicht/vorhanden)
check "GET /nicht/vorhanden — Status"     "$(status "$r")" "200"
check "  landet im Front-Controller"      "$(field "$(body "$r")" PROBE)" "index"
check "  REQUEST_URI erhalten"            "$(field "$(body "$r")" REQUEST_URI)" "/nicht/vorhanden"

# Location 2: PATH_INFO. Das ist der Grund, warum es diese Location gibt.
r=$(resp "$WEB_A" /index.php/foo/bar)
check "GET /index.php/foo/bar — Status"   "$(status "$r")" "200"
check "  PATH_INFO"                       "$(field "$(body "$r")" PATH_INFO)" "/foo/bar"
check "  SCRIPT_FILENAME"                 "$(field "$(body "$r")" SCRIPT_FILENAME)" "/app/public/index.php"
check "  DOCUMENT_ROOT"                   "$(field "$(body "$r")" DOCUMENT_ROOT)" "/app/public"
check "  SERVER_NAME aus HOST"            "$(field "$(body "$r")" SERVER_NAME)" "localhost"

# Location 3: echte .php-Datei neben dem Front-Controller.
r=$(resp "$WEB_A" /info.php)
check "GET /info.php — Status"            "$(status "$r")" "200"
check "  trifft die Fallback-Location"    "$(field "$(body "$r")" PROBE)" "info"
check "  SCRIPT_FILENAME"                 "$(field "$(body "$r")" SCRIPT_FILENAME)" "/app/public/info.php"

# A6.2, Default-Seite: ohne TLS-Proxy darf HTTPS NICHT gesetzt sein. Genau das
# war im Bestand fest verdrahtet und damit falsch.
b=$(body "$(resp "$WEB_A" /index.php)")
check "REQUEST_SCHEME (A6.2, Default)"    "$(field "$b" REQUEST_SCHEME)" "http"
check "HTTPS nicht uebergeben"            "$(field "$b" HTTPS)" "-"
check "HTTP_X_FORWARDED_PROTO"            "$(field "$b" HTTP_X_FORWARDED_PROTO)" "http"

# Verborgenes bleibt verboten.
check "GET /.env — Status"                "$(status "$(resp "$WEB_A" /.env)")" "404"

# ---------------------------------------------------------------------------
# Instanz B — jeder Wert ueberschrieben (die Gegenprobe)
# ---------------------------------------------------------------------------
echo ">>> Instanz B — jeder Wert ueberschrieben"
start_web "$WEB_B" \
  -e HOST=probe.example \
  -e DOCUMENT_ROOT=/web \
  -e INDEX_FILE=app.php \
  -e REQUEST_SCHEME=https \
  -e CLIENT_MAX_BODY_SIZE=1k \
  -e FASTCGI_READ_TIMEOUT=1 \
  || { FAIL=$((FAIL + 1)); echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"; exit 1; }
ok "startet mit ueberschriebenen Werten (environment schlaegt env_file)"

r=$(resp "$WEB_B" /app.php/foo/bar)
b=$(body "$r")
check "GET /app.php/foo/bar — Status"     "$(status "$r")" "200"
check "  DOCUMENT_ROOT wirkt"             "$(field "$b" PROBE)" "alt"
check "  INDEX_FILE wirkt (PATH_INFO)"    "$(field "$b" PATH_INFO)" "/foo/bar"
check "  SCRIPT_FILENAME"                 "$(field "$b" SCRIPT_FILENAME)" "/app/web/app.php"
check "  HOST wirkt"                      "$(field "$b" SERVER_NAME)" "probe.example"

# A6.2, andere Seite: EIN Schalter setzt beide fastcgi-Werte.
check "HTTPS=on hinter TLS-Proxy (A6.2)"  "$(field "$b" HTTPS)" "on"
check "REQUEST_SCHEME=https"              "$(field "$b" REQUEST_SCHEME)" "https"
check "HTTP_X_FORWARDED_PROTO=https"      "$(field "$b" HTTP_X_FORWARDED_PROTO)" "https"

# CLIENT_MAX_BODY_SIZE: Wirkung, nicht nur Rendering. 2000 B gegen 1k.
#
# --post-data und NICHT --post-file: busybox-wget 1.37.0 setzt mit --post-file
# zwar die Methode POST, sendet aber keinen Rumpf (CONTENT_LENGTH=0, belegt am
# 2026-07-25). Ein 2-MB-POST gegen 1m lief damit auf 200 und der Test haette
# nichts gemessen — dieselbe Klasse wie B11/B19. Deshalb prueft der positive Fall
# die tatsaechlich angekommene Rumpflaenge mit.
POST_BODY=$(head -c 2000 /dev/zero | tr '\0' x)
check "POST 2000 B gegen 1k — Status"     "$(status "$(resp "$WEB_B" /app.php --post-data "'$POST_BODY'")")" "413"
r=$(resp "$WEB_A" /index.php --post-data "'$POST_BODY'")
check "POST 2000 B gegen 100m — Status"   "$(status "$r")" "200"
check "  Rumpf kam an (Gegenprobe)"       "$(field "$(body "$r")" CONTENT_LENGTH)" "2000"
check "  als POST"                        "$(field "$(body "$r")" REQUEST_METHOD)" "POST"

# FASTCGI_READ_TIMEOUT: Wirkung. 3 s Schlaf gegen 1 s Limit.
check "3 s Antwort gegen 1 s Limit"       "$(status "$(resp "$WEB_B" '/app.php?sleep=3' -T 30)")" "504"
check "3 s Antwort gegen 600 s Limit"     "$(status "$(resp "$WEB_A" '/index.php?sleep=3' -T 30)")" "200"

# ---------------------------------------------------------------------------
# FASTCGI_UPSTREAM — die Variable landet wirklich im fastcgi_pass
# ---------------------------------------------------------------------------
# nginx loest den Upstream-Namen bereits beim Konfigurationstest auf. Der
# Unterschied zwischen den beiden Laeufen ist allein die Variable.
echo ">>> FASTCGI_UPSTREAM"
conftest() { # <upstream-name>
  docker run --rm --network "$NET" --env-file "$DEFAULTS" -e FASTCGI_UPSTREAM="$1" \
    -v "$TEMPLATES:/etc/nginx/templates:ro" -v "$VOL:/app:ro" \
    "$NGINX_IMAGE" nginx -t 2>&1 | tail -2
}
if conftest "$APP" | grep -q 'test is successful'; then
  ok "FASTCGI_UPSTREAM=$APP — Konfiguration gueltig"
else
  bad "FASTCGI_UPSTREAM=$APP — Konfigurationstest fehlgeschlagen"
fi
if conftest gibt-es-nicht | grep -q 'host not found in upstream "gibt-es-nicht"'; then
  ok "FASTCGI_UPSTREAM=gibt-es-nicht — nginx meldet den Upstream sichtbar"
else
  bad "FASTCGI_UPSTREAM wirkt nicht im fastcgi_pass"
fi

# ---------------------------------------------------------------------------
# Haertung O6 — B24: nur vorhandene .php-Dateien erreichen den Upstream
# ---------------------------------------------------------------------------
# Gemessen wird gegen eine echte /app/public/upload.jpg, die PHP-Code enthaelt.
# Vor der Haertung antwortete /upload.jpg/x.php mit 403 — abgefangen allein von
# security.limit_extensions des php-fpm, nicht von der Vorlage (B24, gemessen am
# 2026-07-25). Mit `try_files $uri =404;` antwortet nginx selbst 404. Genau
# dieser Unterschied im Statuscode ist der Beleg; die Gegenprobe am Ende dieses
# Abschnitts zeigt zusaetzlich, dass die Antwort den Upstream gar nicht mehr
# erreicht.
echo ">>> Haertung O6 — B24 (.php-Fallback-Location)"

r=$(resp "$WEB_A" /exec-check.php)
check "Positivprobe /exec-check.php — Status"  "$(status "$r")" "200"
check "  Inhalt wird wirklich ausgefuehrt"     "$(body "$r")"   "$MARKE"

r=$(resp "$WEB_A" /upload.jpg)
check "GET /upload.jpg — Status"               "$(status "$r")" "200"
check "  Quelltext statt Ausfuehrung"          "$(body "$r")"   "$PHP_ZEILE"

check "GET /upload.jpg/x.php — Status (B24)"   "$(status "$(resp "$WEB_A" /upload.jpg/x.php)")" "404"
check "GET /gibtesnicht.php — Status"          "$(status "$(resp "$WEB_A" /gibtesnicht.php)")"  "404"

# ---------------------------------------------------------------------------
# Haertung O6 — B25: statische Antworten tragen die Security-Header
# ---------------------------------------------------------------------------
# nginx vererbt add_header nur an Ebenen, die selbst keines tragen. Die
# Static-Location trug eines (Cache-Control "public") und verlor damit alle
# sechs Server-Header — ausgerechnet nosniff wirkt bei statischen Dateien am
# meisten. Die Zeile ist geloescht (Variante (b)).
echo ">>> Haertung O6 — B25 (Security-Header auf statischen Antworten)"

h_css=$(hdrs "$WEB_A" /a.css)
h_php=$(hdrs "$WEB_A" /index.php)
for paar in "X-Content-Type-Options:nosniff" \
            "X-Frame-Options:SAMEORIGIN" \
            "Strict-Transport-Security:max-age=31536000"; do
  name=${paar%%:*}; wert=${paar#*:}
  # Positivprobe an der PHP-Antwort: die trug die Header schon immer. Faellt sie
  # aus, misst nicht die Vorlage falsch, sondern dieser Test.
  if has_header "$h_php" "$name" "$wert"; then
    ok "$name auf /index.php (Positivprobe)"
  else
    bad "$name fehlt auf /index.php — die Header-Messung selbst ist defekt"
  fi
  if has_header "$h_css" "$name" "$wert"; then
    ok "$name auf /a.css (B25)"
  else
    bad "$name fehlt auf der statischen Antwort (B25)"
  fi
done

# Gegenprobe: Cache-Control ist weiterhin da (aus `expires 1y`), aber ohne
# "public". Ohne die erste Haelfte wuerde die zweite auch dann gruen melden,
# wenn Cache-Control ganz verschwunden waere.
if has_header "$h_css" Cache-Control "max-age=31536000"; then
  ok "Cache-Control aus 'expires 1y' bleibt erhalten"
else
  bad "Cache-Control fehlt auf der statischen Antwort — 'expires 1y' wirkt nicht mehr"
fi
if has_header "$h_css" Cache-Control "public"; then
  bad "Cache-Control traegt weiterhin 'public' — die add_header-Zeile ist nicht geloescht"
else
  ok "Cache-Control hat 'public' verloren (Gegenprobe zu B25)"
fi

# ---------------------------------------------------------------------------
# Die entscheidende Gegenprobe zu B24 — zuletzt, weil sie den fpm anhaelt
# ---------------------------------------------------------------------------
# Steht der Upstream, laesst sich ein 404 von nginx nicht zweifelsfrei von einem
# 404 des fpm unterscheiden. Mit angehaltenem fpm ist es eindeutig: was jetzt
# noch 404 liefert, hat den Upstream nie erreicht — und was ihn erreicht haette,
# liefert 502.
echo ">>> Haertung O6 — Gegenprobe mit angehaltenem fpm"
docker stop -t 5 "$APP-$SFX" >/dev/null
check "GET /upload.jpg/x.php — Status (B24, fpm aus)" \
      "$(status "$(resp "$WEB_A" /upload.jpg/x.php)")" "404"
check "GET /index.php — Status (belegt: Upstream ist wirklich aus)" \
      "$(status "$(resp "$WEB_A" /index.php)")" "502"

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
