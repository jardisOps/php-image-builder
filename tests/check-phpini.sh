#!/bin/bash
# Checks lib-phpini.sh against the requirements, without a container.
#
# The path is derived from the location of THIS file, not hardcoded — an
# absolute value would only work on one machine and break on any other,
# including CI.
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LIB="$REPO_ROOT/src/shared/entrypoint/lib-phpini.sh"
[ -r "$LIB" ] || { echo "❌ lib-phpini.sh not found at $LIB" >&2; exit 2; }
PASS=0; FAIL=0

# Calls apply_php_configuration in a subshell with the given environment.
# Prints the resolved values as KEY=VALUE, or "DIE: <message>".
# SC2016 is the point here, not an oversight: the body below is source text
# for the subshell and must NOT be expanded early — otherwise the calling
# shell would substitute its own values instead of the library's.
# shellcheck disable=SC2016
run_case() {
  env -i PATH="$PATH" TMPDIR="$(mktemp -d)" APP_USER="$(id -un)" "$@" bash -c '
    log_info() { :; }
    log_warn() { :; }
    die() { printf "DIE: %s\n" "$1"; exit 1; }
    . '"$LIB"'
    apply_php_configuration || exit 1
    for k in XDEBUG_MODE PCOV_ENABLED OPCACHE_ENABLE OPCACHE_VALIDATE_TIMESTAMPS OPCACHE_REVALIDATE_FREQ OPCACHE_JIT PHP_DISPLAY_ERRORS PHP_ERROR_REPORTING PHP_MEMORY_LIMIT PHP_MAX_EXECUTION_TIME PHP_TIMEZONE PHP_LOG_ERRORS APCU_SHM_SIZE OPCACHE_MEMORY_CONSUMPTION OPCACHE_MAX_ACCELERATED_FILES OPCACHE_JIT_BUFFER_SIZE XDEBUG_START_WITH_REQUEST XDEBUG_CLIENT_HOST XDEBUG_CLIENT_PORT XDEBUG_LOG_LEVEL XDEBUG_IDEKEY; do eval "printf \"%s=%s\n\" $k \"\$$k\""; done
    printf "INI_DIR=%s\n" "$INI_DIR"
    printf "XDEBUG_EXPORTED=%s\n" "$(env | grep -c "^XDEBUG_MODE=")"
    printf "INI_EMPTY_DIRECTIVES=%s\n" "$(grep -cE "^[a-z_.]+ = *$" "$INI_DIR/99-runtime-config.ini")"
  ' 2>&1
}

# SC2001: the substitution would prepend an indent to EVERY line, which
# ${var//pattern/replacement} cannot do — it has no notion of line start.
# shellcheck disable=SC2001
check() { # name, output, expected-substring
  if grep -qF "$3" <<<"$2"; then echo "  ✅ $1"; PASS=$((PASS+1))
  else echo "  ❌ $1 — expected: '$3'"; echo "$2" | sed 's/^/       /'; FAIL=$((FAIL+1)); fi
}

# Values an image brings along (profile-independent)
IMG=(PHP_MEMORY_LIMIT=512M PHP_MAX_EXECUTION_TIME=0 PHP_TIMEZONE=UTC PHP_LOG_ERRORS=On
     APCU_SHM_SIZE=64M OPCACHE_MEMORY_CONSUMPTION=128 OPCACHE_MAX_ACCELERATED_FILES=4000
     OPCACHE_JIT_BUFFER_SIZE=128M XDEBUG_START_WITH_REQUEST=yes
     XDEBUG_CLIENT_HOST=host.docker.internal XDEBUG_CLIENT_PORT=9003
     XDEBUG_LOG_LEVEL=0 XDEBUG_IDEKEY=PHPSTORM)

echo "APP_ENV=dev sets a consistent profile"
O=$(run_case "${IMG[@]}" APP_ENV=dev)
check "xdebug.mode=debug"            "$O" "XDEBUG_MODE=debug"
check "pcov off"                     "$O" "PCOV_ENABLED=0"
check "validate_timestamps=1"        "$O" "OPCACHE_VALIDATE_TIMESTAMPS=1"
check "display_errors=On"            "$O" "PHP_DISPLAY_ERRORS=On"
check "error_reporting without E_STRICT" "$O" "PHP_ERROR_REPORTING=E_ALL"

echo "JIT automatically disabled while Xdebug is active"
check "jit=off instead of 1254"      "$O" "OPCACHE_JIT=off"
check "jit_buffer_size=0"            "$O" "OPCACHE_JIT_BUFFER_SIZE=0"

echo "XDEBUG_MODE is exported"
check "into the environment"         "$O" "XDEBUG_EXPORTED=1"

echo "INI quality"
check "no empty directive"          "$O" "INI_EMPTY_DIRECTIVES=0"

echo "APP_ENV=test (no manual disabling needed in test runs anymore)"
O=$(run_case "${IMG[@]}" APP_ENV=test)
check "xdebug off"                   "$O" "XDEBUG_MODE=off"
check "pcov on"                      "$O" "PCOV_ENABLED=1"
# PCOV takes over zend_execute_ex() the same way Xdebug does, so PHP disables
# JIT on its own and would warn on every call unless the auto-disable logic
# covers PCOV as well as Xdebug.
check "jit off because PCOV is active" "$O" "OPCACHE_JIT=off"
check "jit_buffer_size=0"              "$O" "OPCACHE_JIT_BUFFER_SIZE=0"

echo "APP_ENV=prod"
O=$(run_case "${IMG[@]}" APP_ENV=prod)
check "xdebug off"                   "$O" "XDEBUG_MODE=off"
check "validate_timestamps=0"        "$O" "OPCACHE_VALIDATE_TIMESTAMPS=0"
check "display_errors=Off"           "$O" "PHP_DISPLAY_ERRORS=Off"
check "error_reporting ~E_DEPRECATED" "$O" "PHP_ERROR_REPORTING=E_ALL & ~E_DEPRECATED"
check "jit active"                   "$O" "OPCACHE_JIT=1254"

echo "prod + active Xdebug aborts visibly"
O=$(run_case "${IMG[@]}" APP_ENV=prod XDEBUG_MODE=debug)
check "abort"                        "$O" "DIE: APP_ENV=prod, but Xdebug"

echo "an explicit single variable overrides the profile"
O=$(run_case "${IMG[@]}" APP_ENV=prod OPCACHE_VALIDATE_TIMESTAMPS=1)
check "override wins over prod"      "$O" "OPCACHE_VALIDATE_TIMESTAMPS=1"
O=$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=off)
check "xdebug off possible in dev"   "$O" "XDEBUG_MODE=off"
check "then JIT is usable"           "$O" "OPCACHE_JIT=1254"
O=$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=trace,coverage)
check "multiple modes allowed"       "$O" "XDEBUG_MODE=trace,coverage"

echo "PCOV/Xdebug conflict resolution still holds"
O=$(run_case "${IMG[@]}" APP_ENV=dev PCOV_ENABLED=1)
check "xdebug yields to pcov"        "$O" "XDEBUG_MODE=off"
check "pcov stays on"                "$O" "PCOV_ENABLED=1"

echo "invalid values abort clearly"
check "APP_ENV"      "$(run_case "${IMG[@]}" APP_ENV=production)"                  "DIE: APP_ENV='production' is invalid"
check "XDEBUG_MODE"  "$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=degug)"       "DIE: XDEBUG_MODE contains the unknown mode 'degug'"
check "PCOV_ENABLED" "$(run_case "${IMG[@]}" APP_ENV=dev PCOV_ENABLED=yes)"        "DIE: PCOV_ENABLED='yes' is invalid"
check "OPCACHE_JIT"  "$(run_case "${IMG[@]}" APP_ENV=dev OPCACHE_JIT=fast)"        "DIE: OPCACHE_JIT='fast' is invalid"
check "memory_limit" "$(run_case "${IMG[@]/PHP_MEMORY_LIMIT=512M/PHP_MEMORY_LIMIT=lots}" APP_ENV=dev)" "DIE: PHP_MEMORY_LIMIT='lots' is invalid"
check "display_errors" "$(run_case "${IMG[@]}" APP_ENV=dev PHP_DISPLAY_ERRORS=yes)" "DIE: PHP_DISPLAY_ERRORS='yes' is invalid"
check "client_port"  "$(run_case "${IMG[@]/XDEBUG_CLIENT_PORT=9003/XDEBUG_CLIENT_PORT=ninethousand}" APP_ENV=dev)" "DIE: XDEBUG_CLIENT_PORT='ninethousand' is invalid"

echo "no fallback value: a missing image value aborts"
# Remove PHP_TIMEZONE from the image environment
IMG_WITHOUT_TZ=(); for v in "${IMG[@]}"; do [ "$v" = "PHP_TIMEZONE=UTC" ] || IMG_WITHOUT_TZ+=("$v"); done
check "missing value"  "$(run_case "${IMG_WITHOUT_TZ[@]}" APP_ENV=dev)" "PHP_TIMEZONE: is not set"

echo "INI falls back when /home/... is not writable"
O=$(run_case "${IMG[@]}" APP_ENV=dev)
check "fallback directory used"      "$O" "php-config"

echo
echo "════════════════════════════════════"
echo "  passed: $PASS   failed: $FAIL"
[ $FAIL -eq 0 ] || exit 1
