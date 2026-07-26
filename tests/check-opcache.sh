#!/bin/bash
# ---------------------------------------------------------------------------
# check-opcache.sh <fpm-image> — OPcache, JIT and revalidation
# ---------------------------------------------------------------------------
# Two parts: (1) static — OPcache loaded and active, JIT on when Xdebug is
# off and JIT off when Xdebug is on; APP_ENV=test/prod alone drives this via
# the profile. (2) in the dev profile FPM notices code changes without a
# restart, in the prod profile it doesn't — proven here instead of by hand.
#
# BY DEFAULT, OPCACHE DOES NOT CACHE A FILE MODIFIED IN THE LAST 2 SECONDS
# (opcache.file_update_protection). An earlier attempt at part 2 seemed to
# show prod noticing changes too — in reality nothing was ever cached
# (num_cached_scripts=0). So the test waits out that window AND checks
# num_cached_scripts/hits: without that second half it measures nothing and
# still reports green.
#
# Why FPM and not CLI: a CLI invocation is its own process with its own SHM.
# The difference between validate_timestamps 0 and 1 isn't observable across
# separate processes. Only the FPM master holds the cache.
set -eu

IMAGE=${1:?Usage: check-opcache.sh <fpm-image>}
CONTAINER=check-opcache-$$
PASS=0; FAIL=0

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

# ---------------------------------------------------------------------------
# Part 1 — static settings per profile
# ---------------------------------------------------------------------------
# Measured THROUGH the entrypoint, not around it: with `--entrypoint php`,
# lib-phpini.sh never runs and the test would read the image defaults
# instead of the profiles. The entrypoint logs to stderr, hence 2>/dev/null.
php_in() { # <app_env> <php code>
  docker run --rm -e APP_ENV="$1" "$IMAGE" php -r "$2" 2>/dev/null
}
ini() { php_in "$1" "echo ini_get('$2');"; }

# Only runtime state tells whether JIT is really running — ini_get('opcache.jit')
# reports 'off', '0' or an empty string depending on how it was disabled.
jit_enabled() { php_in "$1" 'echo opcache_get_status(false)["jit"]["enabled"] ? "yes" : "no";'; }

echo ">>> OPcache and JIT in $IMAGE"

check "opcache.enable (prod)"      "$(ini prod opcache.enable)"      "1"
check "opcache.enable_cli (prod)"  "$(ini prod opcache.enable_cli)"  "1"
check "validate_timestamps (prod)" "$(ini prod opcache.validate_timestamps)" "0"
check "validate_timestamps (dev)"  "$(ini dev  opcache.validate_timestamps)" "1"

# JIT runs exactly when no extension takes over zend_execute_ex().
check "JIT runs in prod"                      "$(jit_enabled prod)" "yes"
check "JIT off in dev (Xdebug active)"        "$(jit_enabled dev)"  "no"
check "JIT off in test (PCOV active)"         "$(jit_enabled test)" "no"

# The warning itself must not appear in ANY profile — the JIT auto-disable
# logic must cover PCOV as well as Xdebug, since both take over
# zend_execute_ex().
for profile in dev test prod; do
  if docker run --rm -e APP_ENV="$profile" "$IMAGE" php -r 'exit(0);' 2>&1 | grep -qi 'JIT is incompatible'; then
    bad "JIT warning in profile $profile"
  else
    ok "no JIT warning in profile $profile"
  fi
done

# ---------------------------------------------------------------------------
# Part 2 — does FPM notice code changes?
# ---------------------------------------------------------------------------
# Per profile: write the script, wait out the update-protection window, fetch
# twice (fills the cache), change the script, wait out the window again,
# fetch once more.
UPDATE_PROTECTION_S=3   # opcache.file_update_protection is 2 s — with margin

fcgi() { # <path> -> response body
  docker exec \
    -e SCRIPT_NAME="$1" -e SCRIPT_FILENAME="$1" -e REQUEST_METHOD=GET \
    "$CONTAINER" cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | tr -d '\r' | tail -1
}

write_script() { # <version>
  docker exec "$CONTAINER" sh -c "cat > /app/ak15.php <<'PHP'
<?php
\$s = opcache_get_status(false);
echo 'VERSION-$1',
     ' cached=', \$s['opcache_statistics']['num_cached_scripts'],
     ' hits=',   \$s['opcache_statistics']['hits'];
PHP"
}

run_ak15() { # <app_env> <expected-after-change>
  local profile=$1 expect=$2 r1 r2 r3
  cleanup
  docker run -d --name "$CONTAINER" -e APP_ENV="$profile" "$IMAGE" >/dev/null

  for _ in $(seq 1 30); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" = healthy ] && break
    sleep 1
  done

  write_script 1
  sleep "$UPDATE_PROTECTION_S"
  r1=$(fcgi /app/ak15.php)
  r2=$(fcgi /app/ak15.php)

  write_script 2
  sleep "$UPDATE_PROTECTION_S"
  r3=$(fcgi /app/ak15.php)

  echo "     $profile: 1='$r1'  2='$r2'  after change='$r3'"

  # First half: an empty cache means the comparison measures nothing.
  case "$r2" in
    *"cached=0"*|"") bad "$profile — nothing was cached, the test measures nothing" ; return ;;
  esac
  case "$r2" in
    *"hits=0"*) bad "$profile — no cache hits, the test measures nothing" ; return ;;
  esac
  ok "$profile — cache is filled and hit (control check passed)"

  case "$r3" in
    "VERSION-$expect"*) ok "$profile — returns VERSION-$expect after the change" ;;
    *)                  bad "$profile — expected VERSION-$expect, got '$r3'" ;;
  esac
}

echo ">>> Revalidation in a running FPM"
run_ak15 dev  2   # dev notices the change      (validate_timestamps=1)
run_ak15 prod 1   # prod does not notice it      (validate_timestamps=0)

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
