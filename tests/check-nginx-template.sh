#!/bin/bash
# ---------------------------------------------------------------------------
# check-nginx-template.sh <fpm-image> [nginx-image] - the nginx template
# ---------------------------------------------------------------------------
# Tests tests/nginx/templates/default.conf.template against the UNMODIFIED
# official nginx image: no custom entrypoint, no custom build. Same setup a
# project would run - an fpm container plus official nginx, sharing /app.
#
# Two instances, because one alone proves nothing: instance A runs with only
# the defaults file, showing the stack works without any custom config;
# instance B overrides every value, showing the variables actually take
# effect rather than merely matching the default by coincidence.
#
# Measured against $_SERVER inside the PHP process and against status codes,
# not just the rendered config file. A text check on the rendered file is
# added only where an effect isn't affordably measurable (send/connect
# timeout).
set -eu

FPM_IMAGE=${1:?Usage: check-nginx-template.sh <fpm-image> [nginx-image]}
NGINX_IMAGE=${2:-nginx:1.28-alpine}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TEMPLATES="$REPO_ROOT/tests/nginx/templates"
DEFAULTS="$REPO_ROOT/tests/nginx/nginx-defaults.env"

SFX=$$
NET=check-nginx-net-$SFX
VOL=check-nginx-app-$SFX
APP=app                      # service name = FASTCGI_UPSTREAM default
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
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

# ---------------------------------------------------------------------------
# Setup: one fpm container plus a shared /app volume
# ---------------------------------------------------------------------------
# Probes are written into the volume via `docker exec`, not a bind mount, so
# the test doesn't depend on the ownership quirks of the Docker Desktop file
# bridge.
docker network create "$NET" >/dev/null
docker volume create "$VOL" >/dev/null

docker run -d --name "$APP-$SFX" --network "$NET" --network-alias "$APP" \
  -v "$VOL:/app" "$FPM_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-$SFX" 2>/dev/null)" = healthy ] && break
  sleep 1
done
if [ "$(docker inspect -f '{{.State.Health.Status}}' "$APP-$SFX" 2>/dev/null)" != healthy ]; then
  echo "  ❌ fpm container did not become healthy — aborting"
  docker logs "$APP-$SFX" 2>&1 | tail -20
  exit 1
fi

# Probe: outputs the $_SERVER values the template is measured against.
# ?sleep=N delays the request so FASTCGI_READ_TIMEOUT becomes measurable.
write_probe() { # <directory> <filename> <marker>
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

write_probe /app/public index.php index    # default document root
write_probe /app/public info.php  info     # fallback location (real .php file)
write_probe /app/web    app.php   alt      # differing DOCUMENT_ROOT/INDEX_FILE

# Hardening probes (checked further below).
#
#   upload.jpg     a REAL uploaded file containing PHP code - the only way to
#                  measure whether /upload.jpg/x.php executes it.
#   exec-check.php the same line as a real .php file, the positive control:
#                  it proves the content is executable at all, so a 404 on
#                  the .jpg chain can't just mean the measurement missed.
#   a.css          a static file for the header check.
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
  echo "  ❌ $name is not responding — rendered configuration and log:"
  docker logs "$name" 2>&1 | tail -20
  return 1
}

# Fetch the response: first line is the status code, second is the body.
# The body file is cleared first — wget doesn't create it on 4xx/5xx, and a
# leftover from the previous call would be read as this call's response.
resp() { # <container> <path> [extra wget args...]
  local c=$1 p=$2; shift 2
  docker exec "$c" sh -c "
    : > /tmp/body
    wget -S -O /tmp/body $* 'http://127.0.0.1$p' 2>/tmp/hdr || true
    grep -om1 'HTTP/1\.[01] [0-9][0-9][0-9]' /tmp/hdr | grep -oE '[0-9]{3}' | head -1 || true
    tr -d '\r' < /tmp/body | tail -1"
}
status() { echo "$1" | head -1; }
body()   { echo "$1" | tail -1; }

# Fetch response headers. busybox wget writes them to stderr with -S, each
# line indented and CR-terminated.
hdrs() { # <container> <path>
  docker exec "$1" sh -c "wget -S -O /dev/null 'http://127.0.0.1$2' 2>&1 | tr -d '\r'" || true
}
# <header block> <name> <expected substring in value>
# $2 and $3 become part of a grep pattern, not literal text: every caller
# below passes literals without regex special characters. A value containing
# '.', '[' or '*' would need escaping, or the pattern stops matching what's
# meant.
has_header() { echo "$1" | grep -qi "^[[:space:]]*$2:.*$3"; }
field()  { # <body> <key>
  echo "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"
}

# ---------------------------------------------------------------------------
# Instance A — only the defaults file
# ---------------------------------------------------------------------------
echo ">>> Instance A — $NGINX_IMAGE, only $(basename "$DEFAULTS")"
start_web "$WEB_A" || { FAIL=$((FAIL + 1)); echo "  passed: $PASS   failed: $FAIL"; exit 1; }
ok "starts without custom configuration and without a custom entrypoint"

# Nothing may be left unsubstituted. envsubst leaves a missing variable as
# ${NAME}; nginx then fails to start, but not always visibly at the cause, so
# this is checked explicitly.
rendered=$(docker exec "$WEB_A" cat /etc/nginx/conf.d/default.conf)
# SC2016 is intentional here, not an oversight: the literal dollar-brace
# sequence is what's being searched for. If it were expanded, the test would
# look for a variable's value instead of the unreplaced placeholder — and
# would never find anything.
# shellcheck disable=SC2016
if echo "$rendered" | grep -q '\${'; then
  bad "unsubstituted variables in the rendered configuration: $(echo "$rendered" | grep -o '\${[A-Z_]*}' | sort -u | tr '\n' ' ')"
else
  ok "no unsubstituted variable in the rendered configuration"
fi

# The three values whose effect isn't affordably measurable are checked
# against the rendering. fastcgi_pass appears twice (location 2 and 3) and
# must both times come from FASTCGI_UPSTREAM/PHP_PORT.
check "fastcgi_pass app:9000 (2x)"        "$(echo "$rendered" | grep -c 'fastcgi_pass   app:9000;')"      "2"
check "client_max_body_size 100m"         "$(echo "$rendered" | grep -c 'client_max_body_size 100m;')"     "1"
check "fastcgi_read_timeout 600 (2x)"     "$(echo "$rendered" | grep -c 'fastcgi_read_timeout    600;')"   "2"
check "fastcgi_send_timeout 600 (2x)"     "$(echo "$rendered" | grep -c 'fastcgi_send_timeout    600;')"   "2"
check "fastcgi_connect_timeout 300 (2x)"  "$(echo "$rendered" | grep -c 'fastcgi_connect_timeout 300;')"   "2"

# Front controller: try_files falls back to ${INDEX_FILE}.
r=$(resp "$WEB_A" /does/not/exist)
check "GET /does/not/exist — status"     "$(status "$r")" "200"
check "  lands in the front controller"   "$(field "$(body "$r")" PROBE)" "index"
check "  REQUEST_URI preserved"           "$(field "$(body "$r")" REQUEST_URI)" "/does/not/exist"

# Location 2: PATH_INFO. This is the reason this location exists at all.
r=$(resp "$WEB_A" /index.php/foo/bar)
check "GET /index.php/foo/bar — status"   "$(status "$r")" "200"
check "  PATH_INFO"                       "$(field "$(body "$r")" PATH_INFO)" "/foo/bar"
check "  SCRIPT_FILENAME"                 "$(field "$(body "$r")" SCRIPT_FILENAME)" "/app/public/index.php"
check "  DOCUMENT_ROOT"                   "$(field "$(body "$r")" DOCUMENT_ROOT)" "/app/public"
check "  SERVER_NAME from HOST"           "$(field "$(body "$r")" SERVER_NAME)" "localhost"

# Location 3: a real .php file next to the front controller.
r=$(resp "$WEB_A" /info.php)
check "GET /info.php — status"            "$(status "$r")" "200"
check "  hits the fallback location"      "$(field "$(body "$r")" PROBE)" "info"
check "  SCRIPT_FILENAME"                 "$(field "$(body "$r")" SCRIPT_FILENAME)" "/app/public/info.php"

# Default page: without a TLS proxy, HTTPS must NOT be set. That was exactly
# what the legacy setup hardcoded, and it was wrong.
b=$(body "$(resp "$WEB_A" /index.php)")
check "REQUEST_SCHEME (default)"          "$(field "$b" REQUEST_SCHEME)" "http"
check "HTTPS not passed"                  "$(field "$b" HTTPS)" "-"
check "HTTP_X_FORWARDED_PROTO"            "$(field "$b" HTTP_X_FORWARDED_PROTO)" "http"

# Hidden stays forbidden.
check "GET /.env — status"                "$(status "$(resp "$WEB_A" /.env)")" "404"

# ---------------------------------------------------------------------------
# Instance B — every value overridden (the control run)
# ---------------------------------------------------------------------------
echo ">>> Instance B — every value overridden"
start_web "$WEB_B" \
  -e HOST=probe.example \
  -e DOCUMENT_ROOT=/web \
  -e INDEX_FILE=app.php \
  -e REQUEST_SCHEME=https \
  -e CLIENT_MAX_BODY_SIZE=1k \
  -e FASTCGI_READ_TIMEOUT=1 \
  || { FAIL=$((FAIL + 1)); echo "  passed: $PASS   failed: $FAIL"; exit 1; }
ok "starts with overridden values (environment beats env_file)"

r=$(resp "$WEB_B" /app.php/foo/bar)
b=$(body "$r")
check "GET /app.php/foo/bar — status"     "$(status "$r")" "200"
check "  DOCUMENT_ROOT takes effect"      "$(field "$b" PROBE)" "alt"
check "  INDEX_FILE takes effect (PATH_INFO)" "$(field "$b" PATH_INFO)" "/foo/bar"
check "  SCRIPT_FILENAME"                 "$(field "$b" SCRIPT_FILENAME)" "/app/web/app.php"
check "  HOST takes effect"               "$(field "$b" SERVER_NAME)" "probe.example"

# The other side: ONE switch sets both fastcgi values.
check "HTTPS=on behind a TLS proxy"       "$(field "$b" HTTPS)" "on"
check "REQUEST_SCHEME=https"              "$(field "$b" REQUEST_SCHEME)" "https"
check "HTTP_X_FORWARDED_PROTO=https"      "$(field "$b" HTTP_X_FORWARDED_PROTO)" "https"

# CLIENT_MAX_BODY_SIZE: effect, not just rendering. 2000 B against 1k.
#
# --post-data and NOT --post-file: busybox-wget 1.37.0 sets the method to POST
# with --post-file but sends no body (CONTENT_LENGTH=0). A 2 MB POST against
# 1m would then land on 200 and the test would measure nothing — so the
# positive case also checks the body length that actually arrived.
POST_BODY=$(head -c 2000 /dev/zero | tr '\0' x)
check "POST 2000 B against 1k — status"   "$(status "$(resp "$WEB_B" /app.php --post-data "'$POST_BODY'")")" "413"
r=$(resp "$WEB_A" /index.php --post-data "'$POST_BODY'")
check "POST 2000 B against 100m — status" "$(status "$r")" "200"
check "  body arrived (control)"          "$(field "$(body "$r")" CONTENT_LENGTH)" "2000"
check "  as POST"                         "$(field "$(body "$r")" REQUEST_METHOD)" "POST"

# FASTCGI_READ_TIMEOUT: effect. 3 s sleep against a 1 s limit.
check "3 s response against a 1 s limit"  "$(status "$(resp "$WEB_B" '/app.php?sleep=3' -T 30)")" "504"
check "3 s response against a 600 s limit" "$(status "$(resp "$WEB_A" '/index.php?sleep=3' -T 30)")" "200"

# ---------------------------------------------------------------------------
# FASTCGI_UPSTREAM — the variable really lands in fastcgi_pass
# ---------------------------------------------------------------------------
# nginx resolves the upstream name already at config-test time. The only
# difference between the two runs is the variable.
echo ">>> FASTCGI_UPSTREAM"
conftest() { # <upstream name>
  docker run --rm --network "$NET" --env-file "$DEFAULTS" -e FASTCGI_UPSTREAM="$1" \
    -v "$TEMPLATES:/etc/nginx/templates:ro" -v "$VOL:/app:ro" \
    "$NGINX_IMAGE" nginx -t 2>&1 | tail -2
}
if conftest "$APP" | grep -q 'test is successful'; then
  ok "FASTCGI_UPSTREAM=$APP — configuration valid"
else
  bad "FASTCGI_UPSTREAM=$APP — configuration test failed"
fi
if conftest no-such-host | grep -q 'host not found in upstream "no-such-host"'; then
  ok "FASTCGI_UPSTREAM=no-such-host — nginx reports the upstream visibly"
else
  bad "FASTCGI_UPSTREAM has no effect on fastcgi_pass"
fi

# ---------------------------------------------------------------------------
# Hardening — only existing .php files reach the upstream
# ---------------------------------------------------------------------------
# Measured against a real /app/public/upload.jpg containing PHP code. Before
# this hardening, /upload.jpg/x.php answered with 403 — caught only by the
# php-fpm's security.limit_extensions, not by the template. With
# `try_files $uri =404;`, nginx itself answers 404. That status-code
# difference is the evidence; the control at the end of this section also
# shows the response never reaches the upstream at all.
echo ">>> Hardening — .php fallback location"

r=$(resp "$WEB_A" /exec-check.php)
check "Positive control /exec-check.php — status" "$(status "$r")" "200"
check "  content is really executed"          "$(body "$r")"   "$MARKE"

r=$(resp "$WEB_A" /upload.jpg)
check "GET /upload.jpg — status"              "$(status "$r")" "200"
check "  source instead of execution"         "$(body "$r")"   "$PHP_ZEILE"

check "GET /upload.jpg/x.php — status"        "$(status "$(resp "$WEB_A" /upload.jpg/x.php)")" "404"
check "GET /gibtesnicht.php — status"         "$(status "$(resp "$WEB_A" /gibtesnicht.php)")"  "404"

# ---------------------------------------------------------------------------
# Hardening — static responses carry the security headers
# ---------------------------------------------------------------------------
# nginx only inherits add_header into levels that don't already carry one.
# The static location carried one (Cache-Control "public") and thereby lost
# all six server headers — with nosniff mattering most for static files. That
# line has been removed.
echo ">>> Hardening — security headers on static responses"

h_css=$(hdrs "$WEB_A" /a.css)
h_php=$(hdrs "$WEB_A" /index.php)
for paar in "X-Content-Type-Options:nosniff" \
            "X-Frame-Options:SAMEORIGIN" \
            "Strict-Transport-Security:max-age=31536000"; do
  name=${paar%%:*}; wert=${paar#*:}
  # Positive control on the PHP response: it always carried these headers.
  # If it fails, it's not the template that's broken but this measurement.
  if has_header "$h_php" "$name" "$wert"; then
    ok "$name on /index.php (positive control)"
  else
    bad "$name missing on /index.php — the header measurement itself is broken"
  fi
  if has_header "$h_css" "$name" "$wert"; then
    ok "$name on /a.css"
  else
    bad "$name missing on the static response"
  fi
done

# Control: Cache-Control is still present (from `expires 1y`), but without
# "public". Without the first half, the second would also report green if
# Cache-Control had disappeared entirely.
if has_header "$h_css" Cache-Control "max-age=31536000"; then
  ok "Cache-Control from 'expires 1y' is preserved"
else
  bad "Cache-Control missing on the static response — 'expires 1y' has no effect"
fi
if has_header "$h_css" Cache-Control "public"; then
  bad "Cache-Control still carries 'public' — the add_header line wasn't removed"
else
  ok "Cache-Control has lost 'public' (control check)"
fi

# ---------------------------------------------------------------------------
# The decisive control check — last, because it stops the fpm
# ---------------------------------------------------------------------------
# With the upstream up, a 404 from nginx can't be reliably distinguished from
# a 404 from fpm. With fpm stopped it's unambiguous: whatever still returns
# 404 never reached the upstream, and whatever would have reached it now
# returns 502.
echo ">>> Hardening — control check with fpm stopped"
docker stop -t 5 "$APP-$SFX" >/dev/null
check "GET /upload.jpg/x.php — status (fpm stopped)" \
      "$(status "$(resp "$WEB_A" /upload.jpg/x.php)")" "404"
check "GET /index.php — status (confirms: upstream is really down)" \
      "$(status "$(resp "$WEB_A" /index.php)")" "502"

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
