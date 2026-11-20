#!/bin/bash
# ---------------------------------------------------------------------------
# check-restricted.sh <web-image> - the web image without root
# ---------------------------------------------------------------------------
# Proves the second operating mode next to the root start: the conditions a
# Kubernetes namespace enforces under Pod Security "restricted", expressed as
# their docker run equivalents (numeric non-root user, no capabilities, no
# privilege escalation, default seccomp profile), optionally on a read-only
# root filesystem.
#
# The application code is baked into a derived image, root-owned and
# read-only - the shape of a deploy image, and the precondition for the
# claim that the worker cannot modify its own code.
set -eu

WEB_IMAGE=${1:?Usage: check-restricted.sh <web-image>}

SFX=$$
APP_IMAGE=php-image-builder-test/restricted-app:$SFX
C_SEED=check-restricted-seed-$SFX
C_RUN=check-restricted-run-$SFX
C_RO=check-restricted-ro-$SFX
C_NOMOUNT=check-restricted-nomount-$SFX
C_STDIO=check-restricted-stdio-$SFX
C_BADLOG=check-restricted-badlog-$SFX

PASS=0; FAIL=0

cleanup() {
  docker rm -f "$C_SEED" "$C_RUN" "$C_RO" "$C_NOMOUNT" "$C_STDIO" "$C_BADLOG" >/dev/null 2>&1 || true
  docker rmi -f "$APP_IMAGE" >/dev/null 2>&1 || true
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

http() { # <container> <path> -> "<body> [<status>]"
  port=$(docker port "$1" 80/tcp | head -1 | awk -F: '{print $NF}')
  curl -s -w ' [%{http_code}]' "http://127.0.0.1:${port}$2"
}

# One line per process: "<uid> <command line>". Read from /proc so the result
# is numeric and does not depend on a ps applet or on /etc/passwd.
processes() { # <container>
  docker exec "$1" sh -c '
    for p in /proc/[0-9]*; do
      [ -r "$p/cmdline" ] || continue
      printf "%s %s\n" "$(awk "/^Uid:/{print \$2}" "$p/status")" "$(tr "\0" " " < "$p/cmdline")"
    done'
}

# ---------------------------------------------------------------------------
# Deploy-shaped image: code under /app, owned by root, not writable
# ---------------------------------------------------------------------------
# Committed from a container instead of built: a derived image would start
# FROM a local test image, which a docker-container builder (the repo's
# multiarch builder, and the CI default) cannot see. The seed container
# replaces the entrypoint with sh, so entrypoint and command are restored on
# commit.
echo ">>> web image without root: $WEB_IMAGE"
docker run -i --name "$C_SEED" --entrypoint sh "$WEB_IMAGE" -c '
  set -e
  mkdir -p /app/public
  cat > /app/public/index.php
  echo victim > /app/public/victim.txt
  chown -R root:root /app
  chmod 0555 /app /app/public
  chmod 0444 /app/public/index.php /app/public/victim.txt' <<'PHP'
<?php
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($path === '/health') {
    echo 'HEALTH-OK';
    return;
}
if ($path === '/write') {
    // The /tmp write is the positive control: it shows the probe can succeed.
    echo 'control=' . var_export(@file_put_contents('/tmp/probe', 'x') !== false, true)
        . ' overwrite=' . var_export(@file_put_contents(__FILE__, 'x') !== false, true)
        . ' create=' . var_export(@file_put_contents(__DIR__ . '/new.php', 'x') !== false, true)
        . ' delete=' . var_export(@unlink(__DIR__ . '/victim.txt'), true);
    return;
}
echo 'APP-OK uid=' . posix_getuid();
PHP
docker commit \
  --change "ENTRYPOINT $(docker inspect -f '{{json .Config.Entrypoint}}' "$WEB_IMAGE")" \
  --change "CMD $(docker inspect -f '{{json .Config.Cmd}}' "$WEB_IMAGE")" \
  "$C_SEED" "$APP_IMAGE" >/dev/null
docker rm -f "$C_SEED" >/dev/null

APP_UID=$(docker run --rm --entrypoint sh "$WEB_IMAGE" -c 'id -u "$APP_USER"')
APP_GID=$(docker run --rm --entrypoint sh "$WEB_IMAGE" -c 'id -g "$APP_USER"')
INI_DIR=$(docker run --rm --entrypoint sh "$WEB_IMAGE" -c 'echo "/home/$APP_USER/php-config"')
RUNTIME_DIR=$(docker run --rm --entrypoint sh "$WEB_IMAGE" -c 'echo "${WEB_RUNTIME_DIR:-}"')

# The docker run equivalent of Pod Security "restricted". seccomp needs no
# flag: Docker applies its default profile unless told otherwise.
RESTRICTED=(--user "$APP_UID:$APP_GID" --cap-drop ALL --security-opt no-new-privileges)

# Read-only root filesystem plus the writable paths the handbook names.
# An image without WEB_RUNTIME_DIR gets none for it - it then fails on its
# own paths, which is the red state this check must show.
#
# uid/gid are required on the two image paths: a Docker tmpfs takes over the
# mode of the directory it covers but is owned by root, so without them the
# mount is not writable for the container user. (/tmp is 1777 already; a
# Kubernetes emptyDir is world-writable and needs no such option.)
TMPFS_OWNER="uid=$APP_UID,gid=$APP_GID"
WRITABLE=(--read-only --tmpfs /tmp --tmpfs "$INI_DIR:$TMPFS_OWNER")
[ -z "$RUNTIME_DIR" ] || WRITABLE+=(--tmpfs "$RUNTIME_DIR:$TMPFS_OWNER")

# ---------------------------------------------------------------------------
# 1: starts and serves under the restricted conditions
# ---------------------------------------------------------------------------
echo ">>> restricted: non-root user, no capabilities, no privilege escalation"
docker run -d --name "$C_RUN" -p 127.0.0.1::80 "${RESTRICTED[@]}" "$APP_IMAGE" >/dev/null

if wait_healthy "$C_RUN"; then
  ok "container becomes healthy as $APP_UID:$APP_GID"

  PROCS=$(processes "$C_RUN")
  MISSING=''
  for name in 's6-svscan' 's6-supervise' 'nginx: master' 'nginx: worker' 'php-fpm: master' 'php-fpm: pool'; do
    echo "$PROCS" | grep -q " $name" || MISSING="$MISSING '$name'"
  done
  ROOT_PROCS=$(echo "$PROCS" | grep -c '^0 ' || true)
  if [ -n "$MISSING" ]; then
    bad "process list incomplete, missing:$MISSING"
  elif [ "$ROOT_PROCS" -eq 0 ]; then
    ok "no process runs as root (s6, nginx master/worker, fpm master/worker)"
  else
    bad "$ROOT_PROCS process(es) run as root"; echo "$PROCS" | grep '^0 '
  fi

  case "$(http "$C_RUN" /health)" in
    "HEALTH-OK [200]") ok "GET /health answers 200 on port 80" ;;
    *)                bad "GET /health did not answer 200 (got '$(http "$C_RUN" /health)')" ;;
  esac

  case "$(http "$C_RUN" /)" in
    "APP-OK uid=$APP_UID [200]") ok "PHP executes as UID $APP_UID" ;;
    *)                          bad "PHP page did not answer as UID $APP_UID (got '$(http "$C_RUN" /)')" ;;
  esac

  WRITE=$(http "$C_RUN" /write)
  case "$WRITE" in
    "control=true overwrite=false create=false delete=false [200]")
      ok "worker cannot overwrite, create or delete code under /app" ;;
    *) bad "worker write probe: expected control=true and three times false (got '$WRITE')" ;;
  esac

  # Default log destination: the access log is a file, not the container log.
  # `-f` and not a link first: if the log pointed at stdout, grep would read
  # from the exec's own stream and never return.
  if docker exec "$C_RUN" sh -c \
       '[ -f /var/log/nginx/access.log ] && [ ! -L /var/log/nginx/access.log ] && grep -q "GET /health" /var/log/nginx/access.log' \
     && ! docker logs "$C_RUN" 2>&1 | grep -q 'GET /health'; then
    ok "NGINX_LOG_OUTPUT=file (default): access log in /var/log/nginx, not in the container log"
  else
    bad "default log destination: request not in /var/log/nginx/access.log, or it leaked into the container log"
  fi
else
  bad "container did not become healthy under the restricted conditions"
  docker logs "$C_RUN" 2>&1 | tail -20
fi
docker rm -f "$C_RUN" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 2: the same on a read-only root filesystem
# ---------------------------------------------------------------------------
echo ">>> restricted + read-only root filesystem"
docker run -d --name "$C_RO" -p 127.0.0.1::80 "${RESTRICTED[@]}" "${WRITABLE[@]}" "$APP_IMAGE" >/dev/null

if wait_healthy "$C_RO"; then
  ok "container becomes healthy with writable ${WRITABLE[*]:1}"

  case "$(http "$C_RO" /health)" in
    "HEALTH-OK [200]") ok "GET /health answers 200" ;;
    *)                bad "GET /health did not answer 200 (got '$(http "$C_RO" /health)')" ;;
  esac

  # The pool file is generated into the writable ini mount. Loopback is one
  # of its values, so this shows FPM loaded that file and not a default.
  if docker exec "$C_RO" netstat -ltn | grep -q '127.0.0.1:9000'; then
    ok "generated pool configuration is in effect (FastCGI on loopback)"
  else
    bad "FastCGI is not on 127.0.0.1:9000 - the generated pool configuration is not in effect"
    docker exec "$C_RO" netstat -ltn
  fi

  if docker exec "$C_RO" touch /etc/probe 2>/dev/null; then
    bad "root filesystem is writable - the check does not run read-only"
  else
    ok "root filesystem is read-only (control: touch /etc/probe refused)"
  fi
else
  bad "container did not become healthy on a read-only root filesystem"
  docker logs "$C_RO" 2>&1 | tail -20
fi
docker rm -f "$C_RO" >/dev/null 2>&1 || true

# Without the runtime mount the start must fail, and say which path it needs.
if [ -n "$RUNTIME_DIR" ]; then
  docker run -d --name "$C_NOMOUNT" "${RESTRICTED[@]}" --read-only \
    --tmpfs /tmp --tmpfs "$INI_DIR:$TMPFS_OWNER" "$APP_IMAGE" >/dev/null
  if wait_dead "$C_NOMOUNT" \
     && [ "$(docker inspect -f '{{.State.ExitCode}}' "$C_NOMOUNT")" != 0 ] \
     && docker logs "$C_NOMOUNT" 2>&1 | grep -q "entrypoint: ERROR: $RUNTIME_DIR is not writable"; then
    ok "without a writable $RUNTIME_DIR the start aborts and names the path"
  else
    bad "without a writable $RUNTIME_DIR: expected an abort naming the path"
    docker logs "$C_NOMOUNT" 2>&1 | tail -10
  fi
  docker rm -f "$C_NOMOUNT" >/dev/null 2>&1 || true
else
  bad "image defines no WEB_RUNTIME_DIR - the missing-mount case cannot be checked"
fi

# ---------------------------------------------------------------------------
# 3: log destination switch
# ---------------------------------------------------------------------------
echo ">>> NGINX_LOG_OUTPUT"
docker run -d --name "$C_STDIO" -p 127.0.0.1::80 -e NGINX_LOG_OUTPUT=stdio \
  "${RESTRICTED[@]}" "${WRITABLE[@]}" "$APP_IMAGE" >/dev/null
if wait_healthy "$C_STDIO"; then
  http "$C_STDIO" /health >/dev/null
  sleep 1
  if docker logs "$C_STDIO" 2>&1 | grep -q 'GET /health'; then
    ok "stdio: the access log arrives in the container log"
  else
    bad "stdio: request not found in the container log"
    docker logs "$C_STDIO" 2>&1 | tail -10
  fi
else
  bad "stdio: container did not become healthy"
  docker logs "$C_STDIO" 2>&1 | tail -20
fi
docker rm -f "$C_STDIO" >/dev/null 2>&1 || true

docker run -d --name "$C_BADLOG" -e NGINX_LOG_OUTPUT=syslog "${RESTRICTED[@]}" "$APP_IMAGE" >/dev/null
if wait_dead "$C_BADLOG" \
   && docker logs "$C_BADLOG" 2>&1 | grep -q "entrypoint: ERROR: NGINX_LOG_OUTPUT='syslog' is invalid"; then
  ok "an invalid value aborts the start and names the allowed ones"
else
  bad "an invalid NGINX_LOG_OUTPUT did not abort the start with a clear error"
  docker logs "$C_BADLOG" 2>&1 | tail -10
fi
docker rm -f "$C_BADLOG" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 4: another command on the same image (worker, cron, schema step)
# ---------------------------------------------------------------------------
# Passed as arguments, the command runs behind the entrypoint and therefore
# with the runtime ini. This is the form the handbook recommends.
echo ">>> other command, passed as arguments"
OUT=$(docker run --rm "${RESTRICTED[@]}" "${WRITABLE[@]}" "$APP_IMAGE" \
  php -r 'echo ini_get("memory_limit") === getenv("PHP_MEMORY_LIMIT") ? "INI-APPLIED" : "INI-MISSING";' 2>/dev/null || true)
if [ "$OUT" = INI-APPLIED ]; then
  ok "php runs behind the entrypoint with the runtime ini applied"
else
  bad "php as arguments: expected INI-APPLIED (got '$OUT')"
fi

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
