#!/bin/bash
# ---------------------------------------------------------------------------
# check-app-env.sh <image> — the APP_ENV profiles work in the real image
# ---------------------------------------------------------------------------
# Distinction from check-phpini.sh: that one checks lib-phpini.sh in
# isolation, with 33 cases and no container — that's where logic coverage
# lives. This one checks only what the built image alone can show: that the
# resolved values actually arrive as a PHP setting. The 33 cases are
# deliberately not rebuilt here to avoid double maintenance.
set -eu

IMAGE=${1:?Usage: check-app-env.sh <image>}
PASS=0; FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

# Runs PHP code IN the container — through the entrypoint, not around it.
# `--entrypoint php` would be the classic measurement error: lib-phpini.sh
# would never run, there would be no runtime INI, and the test would read
# the extensions' defaults instead of our profiles.
php_in() { # <php-code> [env ...]
  local code=$1; shift
  local args=()
  for e in "$@"; do args+=(-e "$e"); done
  # ${args[@]+"${args[@]}"} and not plain "${args[@]}": with an empty array and
  # `set -u`, bash 3.2 (macOS default) aborts with "unbound variable", while
  # bash 4.4+ on the CI runner does not. Callers without an env argument are
  # therefore only broken on one of the two platforms.
  docker run --rm ${args[@]+"${args[@]}"} "$IMAGE" php -r "$code" 2>/dev/null
}

# xdebug.mode is NOT readable via ini_get: Xdebug reports an empty string for
# mode=off. The environment variable is authoritative, since Xdebug 3 gives
# it precedence anyway — and it's also what the entrypoint sets.
xdebug_mode() { php_in 'echo getenv("XDEBUG_MODE");' "$@"; }
ini()         { local n=$1; shift; php_in "echo ini_get('$n');" "$@"; }

echo ">>> APP_ENV profiles in $IMAGE"

# ini_get('display_errors') returns "1" for On and an EMPTY STRING for Off —
# a PHP quirk, not a misconfiguration.
#
# error_reporting comes back numeric, and those numbers are NOT the same
# across the matrix: E_STRICT (2048) left E_ALL in PHP 8.4, so E_ALL is 32767
# up to 8.3 and 30719 from 8.4 on. Written down here, the check would test the
# PHP version instead of the profile. The expected values are therefore read
# from the image's own constants; what stays under test is that the profile
# resolves to E_ALL in dev and to E_ALL & ~E_DEPRECATED in prod.
E_ALL_EXPECTED=$(php_in 'echo E_ALL;')
E_ALL_NO_DEPRECATED_EXPECTED=$(php_in 'echo E_ALL & ~E_DEPRECATED;')

# Control check: without it the two comparisons below would report green on an
# empty expected value against an equally empty measured one — measuring
# nothing. Each value is checked on its own; testing them concatenated would
# let an empty one hide behind a numeric one.
numeric() { case "${2:-}" in '' | *[!0-9]*) bad "$1 could not be read from the image (got '${2:-}')"; return 1 ;; esac; return 0; }
if numeric "E_ALL" "$E_ALL_EXPECTED" && numeric "E_ALL & ~E_DEPRECATED" "$E_ALL_NO_DEPRECATED_EXPECTED"; then
  ok "expected values read from the image (E_ALL $E_ALL_EXPECTED, without E_DEPRECATED $E_ALL_NO_DEPRECATED_EXPECTED)"
fi

echo "  dev"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=dev)" "debug"
check "pcov.enabled"    "$(ini pcov.enabled    APP_ENV=dev)" "0"
check "display_errors"  "$(ini display_errors  APP_ENV=dev)" "1"
check "error_reporting" "$(ini error_reporting APP_ENV=dev)" "$E_ALL_EXPECTED"

echo "  test"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=test)" "off"
check "pcov.enabled"    "$(ini pcov.enabled    APP_ENV=test)" "1"

echo "  prod"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=prod)" "off"
check "display_errors"  "$(ini display_errors  APP_ENV=prod)" ""
check "error_reporting" "$(ini error_reporting APP_ENV=prod)" "$E_ALL_NO_DEPRECATED_EXPECTED"

# An explicitly set single variable overrides the profile — the assurance
# that today's fine-grained control keeps working.
echo "  an override beats the profile"
check "xdebug.mode in dev"  "$(xdebug_mode APP_ENV=dev XDEBUG_MODE=off)"               "off"
check "display_errors"      "$(ini display_errors APP_ENV=prod PHP_DISPLAY_ERRORS=On)" "1"

# Xdebug 3 reads the environment variable and gives it precedence over the
# INI, so it must be exported, not just set.
echo "  XDEBUG_MODE is exported"
check "in the child process" \
  "$(docker run --rm -e APP_ENV=test "$IMAGE" printenv XDEBUG_MODE 2>/dev/null)" "off"

# Active Xdebug in production aborts visibly instead of running silently —
# the abort IS the expected behavior.
echo "  prod with active Xdebug aborts"
if OUT=$(docker run --rm -e APP_ENV=prod -e XDEBUG_MODE=debug "$IMAGE" php -r 'exit(0);' 2>&1); then
  bad "no abort — the container ran through"
else
  case "$OUT" in
    *rod*|*[Xx]debug*) ok "abort with a reason" ;;
    *)                 bad "abort, but without a recognizable reason: $OUT" ;;
  esac
fi

# A typo does not land in the INI unchecked.
echo "  invalid value aborts"
if docker run --rm -e APP_ENV=dev -e XDEBUG_MODE=degug "$IMAGE" php -r 'exit(0);' >/dev/null 2>&1; then
  bad "an invalid XDEBUG_MODE was accepted"
else
  ok "invalid XDEBUG_MODE rejected"
fi
if docker run --rm -e APP_ENV=produktion "$IMAGE" php -r 'exit(0);' >/dev/null 2>&1; then
  bad "an invalid APP_ENV was accepted"
else
  ok "invalid APP_ENV rejected"
fi

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
