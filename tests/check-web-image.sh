#!/bin/bash
# ---------------------------------------------------------------------------
# check-web-image.sh <web-image> - the combined fpm+nginx image
# ---------------------------------------------------------------------------
# Three claims, each measured against the running container, not the config:
#
#   1. The image becomes HEALTHY on its own - the healthcheck goes through
#      nginx to FPM's /ping, so "healthy" proves the whole request chain
#      without any application code.
#   2. PHP actually executes through the chain: a probe written into
#      /app/public answers over the published HTTP port.
#   3. No half-alive state: killing EITHER php-fpm OR nginx takes the whole
#      container down (s6 finish -> s6-svscanctl -t). A web image where
#      nginx keeps answering 502 over a dead pool would look "up" to every
#      orchestrator that only watches the container state.
set -eu

WEB_IMAGE=${1:?Usage: check-web-image.sh <web-image>}

SFX=$$
C_MAIN=check-web-main-$SFX
C_FPM=check-web-kill-fpm-$SFX
C_NGX=check-web-kill-nginx-$SFX

PASS=0; FAIL=0

cleanup() {
  docker rm -f "$C_MAIN" "$C_FPM" "$C_NGX" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

wait_healthy() { # <container> -> 0 if healthy in time
  for _ in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ] || return 1
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null)" = healthy ] && return 0
    sleep 1
  done
  return 1
}

wait_dead() { # <container> -> 0 if no longer running in time
  for _ in $(seq 1 20); do
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = true ] || return 0
    sleep 1
  done
  return 1
}

# ---------------------------------------------------------------------------
# 1 + 2: chain healthy, PHP answers over HTTP
# ---------------------------------------------------------------------------
echo ">>> web image: $WEB_IMAGE"
docker run -d --name "$C_MAIN" -p 127.0.0.1::80 "$WEB_IMAGE" >/dev/null

if wait_healthy "$C_MAIN"; then
  ok "container becomes healthy (nginx -> fpm /ping)"
else
  bad "container did not become healthy"
  docker logs "$C_MAIN" 2>&1 | tail -20
fi

PORT=$(docker port "$C_MAIN" 80/tcp | head -1 | awk -F: '{print $NF}')

# Probe written into the running container, not bind-mounted - the test must
# not depend on the ownership quirks of the Docker Desktop file bridge (same
# reasoning as in check-nginx-template.sh).
docker exec "$C_MAIN" sh -c \
  'mkdir -p /app/public && printf "%s" "<?php echo \"WEB-OK \" . PHP_VERSION;" > /app/public/index.php'

BODY=$(curl -fsS "http://127.0.0.1:${PORT}/" 2>/dev/null || echo CURL-FAILED)
case "$BODY" in
  WEB-OK*) ok "PHP executes through nginx -> fpm ($BODY)" ;;
  *)       bad "front controller did not answer with PHP output (got '$BODY')" ;;
esac

docker rm -f "$C_MAIN" >/dev/null

# ---------------------------------------------------------------------------
# 3: a dead process takes the container down
# ---------------------------------------------------------------------------
kill_and_expect_dead() { # <container> <process> <label>
  docker run -d --name "$1" "$WEB_IMAGE" >/dev/null
  if ! wait_healthy "$1"; then
    bad "$3: container did not become healthy before the kill"
    return
  fi
  docker exec "$1" pkill "$2" >/dev/null 2>&1 || true
  if wait_dead "$1"; then
    ok "$3: container exits when $2 dies"
  else
    bad "$3: container still running with dead $2 - half-alive state"
    docker logs "$1" 2>&1 | tail -10
  fi
  docker rm -f "$1" >/dev/null 2>&1 || true
}

kill_and_expect_dead "$C_FPM" php-fpm "kill php-fpm"
kill_and_expect_dead "$C_NGX" nginx   "kill nginx"

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
