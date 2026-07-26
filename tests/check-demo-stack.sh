#!/bin/bash
# ---------------------------------------------------------------------------
# check-demo-stack.sh [registry] [host-port] — the demo stack
# ---------------------------------------------------------------------------
# Brings up tests/demo/demo-stack.yml and measures what the stack is meant to
# prove: one call with no follow-up work (`up -d --wait` returns only once
# every service with a healthcheck reports healthy, and fails otherwise);
# database and webserver run as UNMODIFIED official images; health checks
# exist for ALL services (checked individually, see below); the template
# variables are populated and take effect; the repo no longer builds its own
# nginx image.
#
# WHY THE HEALTHCHECKS ARE CHECKED INDIVIDUALLY: `up --wait` only waits for
# services that HAVE a healthcheck. A service without one counts as done as
# soon as it's running. A stack missing a healthcheck would therefore report
# green — a test that measures nothing. That was proven once already: in a
# control run with the webserver's healthcheck removed, `up --wait` still
# returned exit 0. So the health status is queried for every service; "no
# healthcheck" is itself a failure.
#
# The stack runs under its own project name and port so a parallel
# `make demo-up` isn't disturbed.
set -eu

REGISTRY=${1:-php-image-builder-test}
HTTP_PORT=${2:-18080}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
STACK="$REPO_ROOT/tests/demo/demo-stack.yml"
PROJECT=demo-stack-check-$$

# Files share the run ID with the project name: two concurrent runs (e.g.
# `make test-all` for two PHP versions) must not overwrite each other's
# containers or response files.
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
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — '$3' missing in: $(echo "$2" | head -c 200)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — '$3' unexpectedly present in the response" ;; *) ok "$1" ;; esac; }

echo ">>> Demo stack — $STACK (images from $REGISTRY/, port $HTTP_PORT)"

# ---------------------------------------------------------------------------
# Nothing gets built
# ---------------------------------------------------------------------------
# Checked against the resolved model, not the file's text: a build: section
# in an included fragment wouldn't show up in the file itself.
definition=$(compose config)
if echo "$definition" | grep -qE '^\s+build:'; then
  bad "the stack contains a build: section"
else
  ok "no service gets built, all three run as finished images"
fi
has "nginx comes as an official image" "$(compose config --images | tr '\n' ' ')" "nginx:"
has "mariadb comes as an official image" "$(compose config --images | tr '\n' ' ')" "mariadb:"

# ---------------------------------------------------------------------------
# One call, no follow-up work
# ---------------------------------------------------------------------------
echo ">>> up -d --wait"
if compose up -d --wait >"$UP_LOG" 2>&1; then
  ok "one call, no follow-up work: up -d --wait returns green"
else
  bad "the stack did not come up"
  tail -30 "$UP_LOG"
  compose ps
  echo "  passed: $PASS   failed: $FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# Health checks for ALL services
# ---------------------------------------------------------------------------
for svc in db app web; do
  cid=$(compose ps -q "$svc")
  if [ -z "$cid" ]; then
    bad "service '$svc' is not running"
    continue
  fi
  # A service WITHOUT a healthcheck has no .State.Health — the expression
  # then returns "<no value>" or empty. Either way counts as a failure here,
  # not a silent pass.
  health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}NO-HEALTHCHECK{{end}}' "$cid")
  check "service '$svc'" "$health" "healthy"
done

# ---------------------------------------------------------------------------
# The application responds — via the published port from the host
# ---------------------------------------------------------------------------
echo ">>> HTTP"
url="http://127.0.0.1:$HTTP_PORT"

status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/" || echo 000)
body=$(cat "$BODY" 2>/dev/null || true)
check "GET / — status" "$status" "200"
has   "  front controller responds" "$body" "PROBE=demo-app"

# The database. The marker carries the server identifier from
# SELECT VERSION(); the demo app writes "ERROR: ..." to the same spot on a
# connection failure. The extracted value is checked, not just whether "DB="
# appears — otherwise a failed connection would pass as success.
dbv=$(sed -n 's/^<!-- PROBE=demo-app DB=\(.*\) -->$/\1/p' "$BODY" | head -1)
if echo "$dbv" | grep -qE '^[0-9]+\.[0-9]+'; then
  ok "database connection is up (SELECT VERSION() = $dbv)"
else
  bad "database does not respond with a version: '$dbv'"
fi

# The template variables take effect in the stack, not just in isolation.
has   "SERVER_NAME from HOST" "$body" "<th>SERVER_NAME</th>"
has   "REQUEST_SCHEME=http"  "$body" "<td>http</td>"
# Without a TLS proxy, HTTPS must not arrive at all. The row exists, its
# value is "<not passed>" — an "on" anywhere in the table would be the
# hardcoded legacy behavior.
has   "HTTPS row present" "$body" "<th>HTTPS</th>"
hasnt "HTTPS is not passed" "$body" "<td>on</td>"

# PATH_INFO — the reason the template has a dedicated location for it.
status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/index.php/foo/bar" || echo 000)
check "GET /index.php/foo/bar — status" "$status" "200"
has   "  PATH_INFO arrives" "$(cat "$BODY")" "<td>/foo/bar</td>"

# Static delivery: nginx responds without php-fpm. Same path the webserver's
# healthcheck takes.
status=$(curl -s -o "$BODY" -w '%{http_code}' "$url/health.txt" || echo 000)
check "GET /health.txt — status" "$status" "200"
check "  content unchanged"     "$(tr -d '\n' < "$BODY")" "demo-stack-ok"

status=$(curl -s -o /dev/null -w '%{http_code}' "$url/demo.css" || echo 000)
check "GET /demo.css — status (static location)" "$status" "200"

# Hidden stays forbidden.
status=$(curl -s -o /dev/null -w '%{http_code}' "$url/.env" || echo 000)
check "GET /.env — status" "$status" "404"

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
echo ">>> down"
compose down --volumes --remove-orphans >/dev/null 2>&1
left=$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | wc -l | tr -d ' ')
check "no containers left after down" "$left" "0"

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
