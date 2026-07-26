#!/bin/sh
# Runs INSIDE alpine:3.23 and checks lib-user.sh. /lib-user.sh is mounted in.
set -u
PASS=0; FAIL=0

apk add --no-cache shadow su-exec >/dev/null 2>&1 || { echo "apk failed"; exit 2; }

APP_USER=appuser
APP_ROOT=/app
export APP_USER APP_ROOT

# Starting state as in the image: appuser 1000:1000
addgroup -g 1000 appuser
adduser -G appuser -u 1000 -D appuser
mkdir -p /home/appuser/php-config /run/php-fpm
chown -R appuser:appuser /home/appuser /run/php-fpm

check() { # name, actual, expected
  if [ "$2" = "$3" ]; then echo "  OK   $1"; PASS=$((PASS+1))
  else echo "  FAIL $1 — actual='$2' expected='$3'"; FAIL=$((FAIL+1)); fi
}
contains() { # name, haystack, needle
  case "$2" in *"$3"*) echo "  OK   $1"; PASS=$((PASS+1)) ;;
               *) echo "  FAIL $1 — '$3' not in output:"; echo "$2" | sed 's/^/         /'; FAIL=$((FAIL+1)) ;;
  esac
}

# Calls align_runtime_user in a subshell and prints result + messages.
align() {
  ( log_info() { printf 'INFO %s\n' "$1"; }
    log_warn() { printf 'WARN %s\n' "$1"; }
    die()      { printf 'DIE %s\n'  "$1"; exit 1; }
    . /lib-user.sh
    align_runtime_user || exit 1
    printf 'RESULT uid=%s gid=%s runtime_user=%s\n' \
      "$(id -u "$APP_USER")" "$(id -g "$APP_USER")" "$RUNTIME_USER"
  ) 2>&1
}

reset_ids() {
  usermod  -u 1000 appuser 2>/dev/null
  groupmod -g 1000 appuser 2>/dev/null
  usermod  -g 1000 appuser 2>/dev/null
  chown -R 1000:1000 /home/appuser /run/php-fpm
  rm -rf /app; mkdir -p /app
}

echo "=== Case 1: /app owned by 1234:1234 (both IDs free) — normal case ==="
reset_ids; chown 1234:1234 /app
O=$(align)
contains "IDs aligned" "$O" "RESULT uid=1234 gid=1234 runtime_user=appuser"
contains "ownership carried forward" "$O" "Ownership transferred to"
check    "/home/appuser owned by the new UID" "$(stat -c '%u:%g' /home/appuser)" "1234:1234"
check    "APP_OWNED_PATHS untouched without a value" "$(stat -c '%u:%g' /run/php-fpm)" "1000:1000"

echo "=== Case 1b: with APP_OWNED_PATHS=/run/php-fpm (fpm target) ==="
reset_ids; chown 1234:1234 /app
O=$(APP_OWNED_PATHS=/run/php-fpm align)
check "/run/php-fpm carried forward" "$(stat -c '%u:%g' /run/php-fpm)" "1234:1234"

echo "=== Case 2: /app owned by 1234:20 — GID 20 is taken by 'dialout' ==="
reset_ids; chown 1234:20 /app
O=$(align)
contains "no silent swallowing, group is reused" "$O" "GID 20 is taken by group 'dialout'"
contains "IDs aligned"  "$O" "RESULT uid=1234 gid=20"
check    "appuser is in GID 20" "$(id -g appuser)" "20"
check    "/home/appuser at 1234:20" "$(stat -c '%u:%g' /home/appuser)" "1234:20"

echo "=== Case 2b: /app owned by 1234:100 — GID 100 is taken by 'users' ==="
reset_ids; chown 1234:100 /app
O=$(align)
contains "group 'users' reused" "$O" "GID 100 is taken by group 'users'"
check    "appuser is in GID 100" "$(id -g appuser)" "100"

echo "=== Case 3: /app owned by 0:0 — fresh named volume ==="
reset_ids; chown 0:0 /app
O=$(align)
contains "case is handled, not skipped" "$O" "was owned by root and is empty"
check    "/app is now owned by appuser" "$(stat -c '%u:%g' /app)" "1000:1000"
contains "runs as appuser" "$O" "runtime_user=appuser"

echo "=== Case 3b: /app owned by 0:0 and NOT empty ==="
reset_ids; chown 0:0 /app; touch /app/root-file; chown 0:0 /app/root-file
O=$(align)
contains "visible warning instead of silent takeover" "$O" "WARN /app was owned by root and is not empty"
check    "directory handed over" "$(stat -c '%u:%g' /app)" "1000:1000"
check    "content deliberately NOT changed recursively" "$(stat -c '%u:%g' /app/root-file)" "0:0"

echo "=== Case 4: target UID taken — 'bin' has UID 1 ==="
reset_ids; chown 1:1 /app
O=$(align)
contains "visible hint"  "$O" "UID 1 is taken by user 'bin'"
contains "runs numerically under the target identity" "$O" "runtime_user=1:1"
check    "appuser NOT renumbered" "$(id -u appuser)" "1000"

echo "=== Case 5: container started from outside with --user ==="
reset_ids; chown 1234:1234 /app
# SC2016 as above: source text for the subshell, deliberately unexpanded.
# shellcheck disable=SC2016
O=$(su-exec 4711:4711 sh -c '
  log_info() { printf "INFO %s\n" "$1"; }
  log_warn() { printf "WARN %s\n" "$1"; }
  die()      { printf "DIE %s\n"  "$1"; exit 1; }
  . /lib-user.sh
  align_runtime_user
  printf "RESULT runtime_user=[%s]\n" "$RUNTIME_USER"' 2>&1)
contains "no adjustment"        "$O" "given from outside"
contains "no privilege change" "$O" "RESULT runtime_user=[]"
check    "appuser unchanged"   "$(id -u appuser)" "1000"

echo "=== Case 6: /app does not exist ==="
reset_ids; rm -rf /app
O=$(align)
contains "no error" "$O" "does not exist"
contains "runs as appuser" "$O" "runtime_user=appuser"

echo "=== Case 7: /app is already owned by appuser — no action ==="
reset_ids; mkdir -p /app; chown 1000:1000 /app
O=$(align)
contains "no chown needed" "$O" "runtime_user=appuser"
check "no carry-forward message" "$(echo "$O" | grep -c 'Ownership transferred')" "0"

echo
echo "===================================="
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
