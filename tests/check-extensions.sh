#!/bin/bash
# ---------------------------------------------------------------------------
# check-extensions.sh <image> — all expected extensions are loaded
# ---------------------------------------------------------------------------
# The expected set is NOT maintained here but derived from
# src/shared/php-extensions.env. Adding an extension changes exactly one
# file, and this test follows along.
#
# A second, independent assurance: curl, dom and mbstring come compiled in
# statically by the official base image rather than being built here. They
# still must be loaded — if one dropped from the base image, nobody would
# notice until an application broke.
#
# Exactly ONE container start for all extensions, not one per extension.
#
# Environment: php-extensions.env requires the six PECL versions (no
# default). They come from the .env, so this test runs via
# `make test-extensions`, not by hand.
set -eu

IMAGE=${1:?Usage: check-extensions.sh <image>}
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
EXT_FILE="$REPO_ROOT/src/shared/php-extensions.env"
[ -r "$EXT_FILE" ] || { echo "❌ $EXT_FILE not readable" >&2; exit 2; }

if [ -z "${APCU_VERSION:-}" ]; then
  echo "❌ The PECL versions are missing from the environment — this test runs via 'make test-extensions'." >&2
  exit 2
fi

# PHP_EXT_CORE carries names, PHP_EXT_PECL the name-version spelling.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../src/shared/php-extensions.env
. "$EXT_FILE"

# Expected from the base image, not built by us.
FROM_BASE_IMAGE='curl dom mbstring'

EXPECTED="$PHP_EXT_CORE $FROM_BASE_IMAGE"
for e in $PHP_EXT_PECL; do EXPECTED="$EXPECTED ${e%-*}"; done

echo ">>> Extensions in $IMAGE"

LOADED=$(docker run --rm --entrypoint php "$IMAGE" -m)

PASS=0; FAIL=0
for ext in $EXPECTED; do
  if printf '%s\n' "$LOADED" | grep -qix -- "$ext"; then
    PASS=$((PASS + 1))
  else
    echo "  ❌ missing: $ext"; FAIL=$((FAIL + 1))
  fi
done

# OPcache reports itself as "Zend OPcache" and so falls through the -x
# matching above. Since PHP 8.5 it's compiled in statically — checked here is
# that it's loaded, not where it comes from.
if printf '%s\n' "$LOADED" | grep -q 'Zend OPcache'; then
  PASS=$((PASS + 1))
else
  echo "  ❌ missing: Zend OPcache"; FAIL=$((FAIL + 1))
fi

echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "  ✅ all expected extensions loaded"
