#!/bin/bash
# ---------------------------------------------------------------------------
# check-uid-image.sh <cli-image> — UID/GID alignment on the built image
# ---------------------------------------------------------------------------
# Distinction from check-user-alignment.sh: that one checks lib-user.sh in
# isolation, in alpine:3.23, against directories created inside the
# container. Here the same logic runs in the REAL image against REAL Docker
# volumes.
#
# This holds up on macOS too: a named volume lives in the Linux VM and
# carries real Unix owners there. A helper container sets them, our image
# sees them like on a Linux host — covering all three required conditions:
#
#   Host UID != 1000     volume owned by 1234:1234
#   occupied target GID  volume owned by 1234:20 — GID 20 is "dialout" in
#                        Alpine. Exactly here the legacy code failed
#                        silently: groupmod failed, `2>/dev/null || true`
#                        swallowed it, and the error later surfaced as an
#                        unexplained "Permission denied".
#   root-owned volume    fresh volume, as Docker creates it
#
# NOT covered: a bind mount from a real Linux host — check-uid-linux-host.sh
# covers that in a docker-in-docker Linux host, with a different source of
# ownership but the same mechanism. Both scripts stay side by side: this one
# runs without --privileged and catches the same bug earlier.
set -eu

IMAGE=${1:?Usage: check-uid-image.sh <cli-image>}
VOLUME=check-uid-$$
PASS=0; FAIL=0

cleanup() { docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

# Recreates the volume and sets its owner. Empty = leave as Docker creates
# it (root:root).
# The marker file is not incidental but required: mounting an EMPTY named
# volume onto a path the image knows makes Docker copy the image content and
# its owners into it — resetting exactly the ownership this test wants to
# set. A non-empty volume is left untouched by Docker. Without this trick the
# test reported 1000:1000 three times and would have called an alignment
# "occupied" that never happened.
prepare_volume() { # [owner]
  docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true
  docker volume create "$VOLUME" >/dev/null
  docker run --rm -v "$VOLUME:/app" alpine:3.23 \
    sh -c 'touch /app/.keep'"${1:+ && chown -R $1 /app}"
}

# Starts the image on the volume and reports owner and writability.
# THROUGH the entrypoint, not around it: `--entrypoint sh` would have
# skipped lib-user.sh — exactly the alignment under test here.
probe() { # [extra docker args ...]
  docker run --rm -v "$VOLUME:/app" "$@" "$IMAGE" sh -c '
    touch /app/probe 2>/dev/null && w=writable || w=NOT-writable
    printf "%s %s\n" "$(stat -c %u:%g /app)" "$w"
  ' 2>/dev/null
}

expect() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi
}

echo ">>> UID/GID alignment in $IMAGE"

echo "  Host UID != 1000"
prepare_volume 1234:1234
expect "/app is owned by the runtime user afterwards and is writable" \
  "$(probe)" "1234:1234 writable"

echo "  occupied target GID (20 = dialout)"
prepare_volume 1234:20
expect "group is reused instead of failing silently" \
  "$(probe)" "1234:20 writable"

echo "  fresh named volume (root:root)"
prepare_volume
expect "root-owned volume is handled, not skipped" \
  "$(probe)" "1000:1000 writable"

# externally given identity: no adjustment, no privilege change, and the
# image still works under a UID it does not know.
echo "  start with --user 4711:4711"
prepare_volume 4711:4711
expect "runs unchanged under the given identity" \
  "$(probe --user 4711:4711)" "4711:4711 writable"

if docker run --rm --user 4711:4711 -e APP_ENV=test --entrypoint php "$IMAGE" \
     -r 'exit(0);' >/dev/null 2>&1; then
  ok "PHP runs under an unknown UID (INI falls back to a fallback directory)"
else
  bad "PHP fails under an unknown UID"
fi

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
