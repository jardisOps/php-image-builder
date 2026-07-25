#!/bin/bash
# ---------------------------------------------------------------------------
# check-extensions.sh <image> — alle erwarteten Extensions sind geladen
# ---------------------------------------------------------------------------
# Die gebaute Sollmenge wird NICHT hier gepflegt, sondern aus
# src/shared/php-extensions.env abgeleitet (A2.1). In den Bestands-Repos stand
# sie ein zweites Mal in test.mk — und driftete prompt: phpcli listete dort
# pcntl, phpfpm nicht (D1). Wer eine Extension hinzufuegt, aendert seit P8 genau
# eine Datei, und dieser Test zieht mit.
#
# Dazu kommt eine ZWEITE, eigenstaendige Zusicherung: curl, dom und mbstring
# werden seit B12 bewusst NICHT mehr nachgebaut, weil das offizielle Image sie
# statisch einkompiliert mitbringt. Sie muessen trotzdem geladen sein — faellt
# eine davon im Basis-Image weg, merkte es sonst niemand, bis eine Anwendung
# bricht.
#
# Genau EIN Containerstart fuer alle Extensions. Der Bestand startete einen
# Container je Extension (19 Starts je Architektur) — Minuten ohne Mehrwert.
#
# Umgebung: die Datei php-extensions.env verlangt die sechs PECL-Versionen
# (A2.4, kein Default). Sie kommen aus der .env; deshalb laeuft dieser Test
# ueber `make test-extensions` und nicht von Hand.
set -eu

IMAGE=${1:?Aufruf: check-extensions.sh <image>}
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
EXT_FILE="$REPO_ROOT/src/shared/php-extensions.env"
[ -r "$EXT_FILE" ] || { echo "❌ $EXT_FILE nicht lesbar" >&2; exit 2; }

if [ -z "${APCU_VERSION:-}" ]; then
  echo "❌ Die PECL-Versionen fehlen in der Umgebung — dieser Test laeuft ueber 'make test-extensions'." >&2
  exit 2
fi

# PHP_EXT_CORE traegt Namen, PHP_EXT_PECL die Schreibweise name-version.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../src/shared/php-extensions.env
. "$EXT_FILE"

# Vom Basis-Image erwartet, nicht von uns gebaut (B12).
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
    echo "  ❌ fehlt: $ext"; FAIL=$((FAIL + 1))
  fi
done

# OPcache meldet sich als "Zend OPcache" und faellt damit durch das -x-Raster
# oben. Ab PHP 8.5 ist es statisch einkompiliert (B13) — geprueft wird deshalb,
# dass es geladen ist, nicht woher es kommt.
if printf '%s\n' "$LOADED" | grep -q 'Zend OPcache'; then
  PASS=$((PASS + 1))
else
  echo "  ❌ fehlt: Zend OPcache"; FAIL=$((FAIL + 1))
fi

echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "  ✅ alle erwarteten Extensions geladen"
