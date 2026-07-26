#!/bin/bash
# ---------------------------------------------------------------------------
# check-uid-linux-host.sh <cli-image> [dind-image] — UID/GID alignment against a real Linux bind mount
# ---------------------------------------------------------------------------
# Under Docker Desktop, a bind mount from macOS runs through the VM's file
# bridge, which rewrites all owners to the container's identity — a UID bug
# would stay invisible there. A `docker:*-dind` container is a real Linux host
# with its own filesystem and Docker daemon, so a bind mount from it goes
# through no bridge; the foreign UID here is even freely chosen (4711) rather
# than runner-assigned.
#
# Distinction from the other two UID checks:
#   check-user-alignment.sh  lib-user.sh in isolation, without our image
#   check-uid-image.sh       real image, real Docker named volumes
#   this file                real image, real bind mount from a Linux host
#
# The ownership reset on first mount only affects empty named volumes, not
# bind mounts — Docker leaves those untouched. This script still verifies the
# given ownership is still in place before each run, as a cross-check.
set -eu

IMAGE=${1:?Usage: check-uid-linux-host.sh <cli-image> [dind-image]}
DIND_IMAGE=${2:-docker:28-dind}

DIND=check-uid-linux-$$
PASS=0; FAIL=0

cleanup() { docker rm -f "$DIND" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()     { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()    { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

# Run everything inside the Linux host.
host() { docker exec "$DIND" sh -c "$1"; }

echo ">>> UID/GID against a real Linux bind mount — $IMAGE"
echo "  Linux host: $DIND_IMAGE"

# ---------------------------------------------------------------------------
# Bring up the Linux host
# ---------------------------------------------------------------------------
# DOCKER_TLS_CERTDIR empty: the inner daemon is only reached over the local
# socket, never the network. Without this line the image would generate a TLS
# certificate on every start and listen on 2376 — pointless here.
docker run -d --privileged --name "$DIND" -e DOCKER_TLS_CERTDIR= "$DIND_IMAGE" >/dev/null

ready=no
for _ in $(seq 1 60); do
  if docker exec "$DIND" docker info >/dev/null 2>&1; then ready=yes; break; fi
  [ "$(docker inspect -f '{{.State.Running}}' "$DIND" 2>/dev/null)" = true ] || break
  sleep 1
done
if [ "$ready" != yes ]; then
  bad "inner Docker daemon never became ready — aborting"
  docker logs "$DIND" 2>&1 | tail -20
  echo; echo "  passed: $PASS   failed: $FAIL"
  exit 1
fi
ok "Linux host is running, own Docker daemon is ready"

expect "it really is Linux" "$(host 'uname -s')" "Linux"

# Get our image into the inner daemon. Via save/load, not a registry: nothing
# may leave the machine, and this way the exact artifact built locally is
# what gets tested.
docker save "$IMAGE" | docker exec -i "$DIND" docker load >/dev/null
if host "docker image inspect '$IMAGE' >/dev/null 2>&1"; then
  ok "test image is present in the Linux host (via save/load, no registry involved)"
else
  bad "test image did not arrive in the Linux host — aborting"
  echo; echo "  passed: $PASS   failed: $FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# A directory on the Linux filesystem, with a given owner
# ---------------------------------------------------------------------------
# vorbereiten recreates the directory and sets its owner; empty = leave as-is (root:root).
prepare() { # <path> [owner]
  host "rm -rf '$1' && mkdir -p '$1'"
  if [ -n "${2:-}" ]; then
    host "chown $2 '$1'"
  fi
}

# Cross-check against the empty-volume ownership-reset trap: verify the given
# ownership is still in place before testing — otherwise everything below
# would measure a state nobody set.
owner_on_host() { host "stat -c '%u:%g' '$1'"; }

# Starts our image on the bind mount — THROUGH the entrypoint, not around it
# (--entrypoint would skip lib-user.sh, i.e. exactly what's under test here).
#
# Reports the PROCESS IDENTITY first, then the directory owner. This order is
# the whole point: the directory owner is usually the INPUT of the test case
# and never changes — asserting on it measures nothing. Whether alignment
# actually happened is shown only by the process's `id -u`/`id -g`.
probe() { # <path> [extra docker args ...]
  _p=$1; shift
  host "docker run --rm -v '$_p:/app' $* '$IMAGE' sh -c '
    touch /app/probe 2>/dev/null && w=writable || w=NOT-writable
    printf \"%s %s %s\n\" \"\$(id -u):\$(id -g)\" \"\$(stat -c %u:%g /app)\" \"\$w\"
  ' 2>/dev/null"
}

# <expected> has the form "<process-uid:gid> <dir-uid:gid> <writable>"
case_run() { # <heading> <path> <owner|""> <expected>
  echo "  $1"
  prepare "$2" "$3"
  expect "    given ownership is still on the Linux filesystem" \
    "$(owner_on_host "$2")" "${3:-0:0}"
  expect "    process identity / directory / write permission" "$(probe "$2")" "$4"
}

case_run "Host UID != 1000 (bind mount, 4711:4711)" /srv/app-foreign  4711:4711 "4711:4711 4711:4711 writable"
case_run "occupied target GID (20 = dialout)"        /srv/app-gid20  1234:20   "1234:20 1234:20 writable"
case_run "root-owned directory, empty"               /srv/app-root   ""        "1000:1000 1000:1000 writable"

# Proof only a bind mount can give: the file the container wrote is afterwards
# on the LINUX FILESYSTEM and carries the aligned identity there. With a named
# volume this would not be the same, and over the macOS file bridge the value
# would be rewritten.
expect "    file written by the container carries the aligned identity on the host" \
  "$(host "stat -c '%u:%g' /srv/app-foreign/probe")" "4711:4711"

# A root-owned directory that already has content. Only the directory itself
# is handed over; a recursive chown would rewrite foreign data in a
# deliberately root-owned tree.
echo "  root-owned directory WITH content"
prepare /srv/app-full ""
host "install -m 644 /dev/null /srv/app-full/foreign.txt"
expect "    process identity / directory / write permission" \
  "$(probe /srv/app-full)" "1000:1000 1000:1000 writable"
expect "    existing content stays root" \
  "$(host "stat -c '%u:%g' /srv/app-full/foreign.txt")" "0:0"

# externally given identity: no adjustment.
echo "  start with --user 4711:4711"
prepare /srv/app-user 4711:4711
expect "    runs unchanged under the given identity" \
  "$(probe /srv/app-user --user 4711:4711)" "4711:4711 4711:4711 writable"

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
