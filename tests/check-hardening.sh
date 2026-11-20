#!/bin/bash
# ---------------------------------------------------------------------------
# check-hardening.sh <cli-image> <fpm-image> <web-image> - attack surface
# ---------------------------------------------------------------------------
# Three claims, all measured on the running image:
#
#   1. No setuid/setgid file in any published image (base strips them;
#      a target that installs packages later must not bring new ones).
#   2. FastCGI exposure: the web image's pool is NOT reachable from another
#      container, the fpm image's pool IS (sidecar pattern). The fpm half is
#      the positive control — it proves the probe can succeed at all, so a
#      refused connection on web is not just a broken probe.
#   3. Under the root start the worker identity cannot modify the runtime
#      state the root processes of the web image run on.
set -eu

CLI_IMAGE=${1:?Usage: check-hardening.sh <cli-image> <fpm-image> <web-image>}
FPM_IMAGE=${2:?Usage: check-hardening.sh <cli-image> <fpm-image> <web-image>}
WEB_IMAGE=${3:?Usage: check-hardening.sh <cli-image> <fpm-image> <web-image>}

SFX=$$
C_FPM=check-hardening-fpm-$SFX
C_WEB=check-hardening-web-$SFX

PASS=0; FAIL=0

cleanup() { docker rm -f "$C_FPM" "$C_WEB" >/dev/null 2>&1 || true; }
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

# ---------------------------------------------------------------------------
# 1: setuid/setgid
# ---------------------------------------------------------------------------
echo ">>> setuid/setgid files"
for img in "$CLI_IMAGE" "$FPM_IMAGE" "$WEB_IMAGE"; do
  found=$(docker run --rm --entrypoint sh "$img" -c \
    'find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -print')
  if [ -z "$found" ]; then
    ok "none in $img"
  else
    bad "found in $img: $(echo "$found" | tr '\n' ' ')"
  fi
done

# ---------------------------------------------------------------------------
# 2: FastCGI reachable from a neighbouring container?
# ---------------------------------------------------------------------------
# The probe is cgi-fcgi from the fpm image, sent from a separate container on
# the default bridge to the target's IP — the view any other pod/container
# on the same network has.
probe() { # <target-container> -> prints the probe output
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1")
  docker run --rm --entrypoint sh \
    -e SCRIPT_NAME=/ping -e SCRIPT_FILENAME=/ping -e REQUEST_METHOD=GET \
    "$FPM_IMAGE" -c "timeout 5 cgi-fcgi -bind -connect $ip:9000 2>&1" || true
}

echo ">>> FastCGI exposure"
docker run -d --name "$C_FPM" "$FPM_IMAGE" >/dev/null
docker run -d --name "$C_WEB" "$WEB_IMAGE" >/dev/null

if wait_healthy "$C_FPM"; then
  case "$(probe "$C_FPM")" in
    *pong*) ok "fpm: pool reachable from another container (sidecar pattern, positive control)" ;;
    *)      bad "fpm: pool NOT reachable from another container — the sidecar pattern is broken" ;;
  esac
else
  bad "fpm did not become healthy"; docker logs "$C_FPM" 2>&1 | tail -20
fi

if wait_healthy "$C_WEB"; then
  case "$(probe "$C_WEB")" in
    *pong*) bad "web: pool reachable from another container — FastCGI exposed beyond loopback" ;;
    *)      ok "web: pool not reachable from another container" ;;
  esac

  # Under the root start s6 runs as root on a scan directory below
  # WEB_RUNTIME_DIR. The worker identity must not be able to replace it.
  # The /tmp write is the positive control for the probe itself.
  PROBE=$(docker exec --user appuser "$C_WEB" sh -c '
    touch /tmp/probe && echo control-ok
    mv "$WEB_RUNTIME_DIR/s6" "$WEB_RUNTIME_DIR/s6.moved" 2>/dev/null && echo scan-dir-moved
    touch "$WEB_RUNTIME_DIR/s6/probe" 2>/dev/null && echo scan-dir-written
    touch "$WEB_RUNTIME_DIR/nginx/default.conf" 2>/dev/null && echo vhost-written' || true)
  if [ "$PROBE" = control-ok ]; then
    ok "web: the worker identity cannot modify the s6 scan directory or the vhost (root start)"
  else
    bad "web: the worker identity can modify runtime state of root processes: $(echo "$PROBE" | tr '\n' ' ')"
  fi
else
  bad "web did not become healthy"; docker logs "$C_WEB" 2>&1 | tail -20
fi

echo ""
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
