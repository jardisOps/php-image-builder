# shellcheck shell=dash
# ---------------------------------------------------------------------------
# lib-phpini.sh - APP_ENV profiles and generation of the runtime ini
# ---------------------------------------------------------------------------
# Sourced by entrypoint.sh, never executed directly.
#
# Expects: APP_USER, log_info/log_warn/die (from entrypoint.sh)
# Sets:    the resolved PHP settings (exported) plus INI_DIR
#
# PRIORITY RULE, from strong to weak:
#   1. an explicitly set individual variable  (docker run -e XDEBUG_MODE=trace)
#   2. the APP_ENV profile                    (dev | test | prod)
#
# "Unset" and "empty" are deliberately synonymous: the .env carries the
# profile-driven variables as empty slots so the profile can take effect.
#
# There is deliberately no third tier with fallback values: the profile
# table covers every profile variable in every environment, and the
# profile-independent values come from the image. A missing one is a build
# error and aborts visibly here instead of hiding behind a fallback.
# ---------------------------------------------------------------------------

APP_ENV_VALUES='dev test prod'

# ---------------------------------------------------------------------------
# Profile table - the ONE place profile values live
# ---------------------------------------------------------------------------
#
#                              dev        test       prod
#   XDEBUG_MODE                debug      off        off
#   PCOV_ENABLED               0          1          0
#   OPCACHE_ENABLE              1          1          1
#   OPCACHE_VALIDATE_TIMESTAMPS 1         1          0
#   OPCACHE_REVALIDATE_FREQ    0          0          0
#   OPCACHE_JIT                1254*      1254       1254
#   PHP_DISPLAY_ERRORS         On         On         Off
#   PHP_ERROR_REPORTING        E_ALL      E_ALL      E_ALL & ~E_DEPRECATED
#
#   * in dev, the JIT auto-policy switches this to 'off' because Xdebug is
#     active there. The profile value stays 1254 so an explicit
#     XDEBUG_MODE=off in dev immediately yields a usable JIT.
#
# `${VAR:=value}` only sets a variable when it is unset or empty - this one
# shell construct IS the priority rule above. Values identical across all
# environments are set before the `case`; the `case` therefore holds only
# what actually differs between environments.
apply_env_profile() {
    # Same in all environments, still overridable via their slot.
    : "${OPCACHE_ENABLE:=1}" \
      "${OPCACHE_REVALIDATE_FREQ:=0}" \
      "${OPCACHE_JIT:=1254}"

    case "$APP_ENV" in
        dev)
            : "${XDEBUG_MODE:=debug}" \
              "${PCOV_ENABLED:=0}" \
              "${OPCACHE_VALIDATE_TIMESTAMPS:=1}" \
              "${PHP_DISPLAY_ERRORS:=On}" \
              "${PHP_ERROR_REPORTING:=E_ALL}"
            ;;
        test)
            : "${XDEBUG_MODE:=off}" \
              "${PCOV_ENABLED:=1}" \
              "${OPCACHE_VALIDATE_TIMESTAMPS:=1}" \
              "${PHP_DISPLAY_ERRORS:=On}" \
              "${PHP_ERROR_REPORTING:=E_ALL}"
            ;;
        prod)
            : "${XDEBUG_MODE:=off}" \
              "${PCOV_ENABLED:=0}" \
              "${OPCACHE_VALIDATE_TIMESTAMPS:=0}" \
              "${PHP_DISPLAY_ERRORS:=Off}" \
              "${PHP_ERROR_REPORTING:=E_ALL & ~E_DEPRECATED}"
            ;;
        *)
            die "APP_ENV='$APP_ENV' is invalid. Allowed: $APP_ENV_VALUES."
            ;;
    esac

    # The export is mandatory for XDEBUG_MODE: Xdebug 3 reads the
    # environment variable and gives it precedence over the ini setting. It
    # is exported explicitly here for all values, so child processes see the
    # same configuration as the generated ini.
    export XDEBUG_MODE PCOV_ENABLED OPCACHE_ENABLE OPCACHE_VALIDATE_TIMESTAMPS \
           OPCACHE_REVALIDATE_FREQ OPCACHE_JIT PHP_DISPLAY_ERRORS PHP_ERROR_REPORTING
}

# ---------------------------------------------------------------------------
# Values the image must supply
# ---------------------------------------------------------------------------
# Profile-independent: they follow the target's purpose, not the
# environment (e.g. max_execution_time: 0 in CLI, 30 in a request context).
# They arrive as ENV from the Dockerfile, fed from the .env.
# `${VAR:?hint}` checks and aborts in one step if one is missing.
IMAGE_VALUE_HINT='is not set - this value must come as ENV from the image (Dockerfile, fed from the .env). There is deliberately no fallback, because a missing value is a build error.'

require_image_values() {
    : "${PHP_MEMORY_LIMIT:?$IMAGE_VALUE_HINT}" \
      "${PHP_MAX_EXECUTION_TIME:?$IMAGE_VALUE_HINT}" \
      "${PHP_TIMEZONE:?$IMAGE_VALUE_HINT}" \
      "${PHP_LOG_ERRORS:?$IMAGE_VALUE_HINT}" \
      "${APCU_SHM_SIZE:?$IMAGE_VALUE_HINT}" \
      "${OPCACHE_MEMORY_CONSUMPTION:?$IMAGE_VALUE_HINT}" \
      "${OPCACHE_MAX_ACCELERATED_FILES:?$IMAGE_VALUE_HINT}" \
      "${OPCACHE_JIT_BUFFER_SIZE:?$IMAGE_VALUE_HINT}" \
      "${XDEBUG_START_WITH_REQUEST:?$IMAGE_VALUE_HINT}" \
      "${XDEBUG_CLIENT_HOST:?$IMAGE_VALUE_HINT}" \
      "${XDEBUG_CLIENT_PORT:?$IMAGE_VALUE_HINT}" \
      "${XDEBUG_LOG_LEVEL:?$IMAGE_VALUE_HINT}" \
      "${XDEBUG_IDEKEY:?$IMAGE_VALUE_HINT}"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

is_integer()   { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_byte_size() { printf '%s' "$1" | grep -Eq '^[0-9]+[KMGkmg]?$'; }
is_onoff()     { case "$1" in On|Off|on|off|1|0|stderr) return 0 ;; *) return 1 ;; esac; }

# Xdebug 3 accepts a comma-separated list of these modes.
XDEBUG_MODES='off develop coverage debug gcstats profile trace'

validate_xdebug_mode() {
    _lp_old_ifs="$IFS"; IFS=','
    for _lp_mode in $1; do
        case " $XDEBUG_MODES " in
            *" $_lp_mode "*) ;;
            *) IFS="$_lp_old_ifs"
               die "XDEBUG_MODE contains the unknown mode '$_lp_mode'. Allowed (comma-separated): $XDEBUG_MODES." ;;
        esac
    done
    IFS="$_lp_old_ifs"
}

# APP_ENV itself is not checked here but by the `case` in apply_env_profile:
# an unknown value hits the *) branch there and aborts.
validate_values() {
    validate_xdebug_mode "$XDEBUG_MODE"

    case "$PCOV_ENABLED" in 0|1) ;; *)
        die "PCOV_ENABLED='$PCOV_ENABLED' is invalid. Allowed: 0 or 1." ;;
    esac

    case "$OPCACHE_ENABLE" in 0|1) ;; *)
        die "OPCACHE_ENABLE='$OPCACHE_ENABLE' is invalid. Allowed: 0 or 1." ;;
    esac

    case "$OPCACHE_VALIDATE_TIMESTAMPS" in 0|1) ;; *)
        die "OPCACHE_VALIDATE_TIMESTAMPS='$OPCACHE_VALIDATE_TIMESTAMPS' is invalid. Allowed: 0 or 1." ;;
    esac

    # opcache.jit accepts 'off'/'disable'/'tracing'/'function' or four digits (CRTO).
    case "$OPCACHE_JIT" in
        off|disable|on|tracing|function) ;;
        *) is_integer "$OPCACHE_JIT" \
            || die "OPCACHE_JIT='$OPCACHE_JIT' is invalid. Allowed: off, disable, on, tracing, function, or a four-digit CRTO number like 1254." ;;
    esac

    is_onoff "$PHP_DISPLAY_ERRORS" \
        || die "PHP_DISPLAY_ERRORS='$PHP_DISPLAY_ERRORS' is invalid. Allowed: On, Off, or stderr."
    is_onoff "$PHP_LOG_ERRORS" \
        || die "PHP_LOG_ERRORS='$PHP_LOG_ERRORS' is invalid. Allowed: On or Off."

    is_byte_size "$PHP_MEMORY_LIMIT" \
        || die "PHP_MEMORY_LIMIT='$PHP_MEMORY_LIMIT' is invalid. Expected e.g. 512M."
    is_byte_size "$APCU_SHM_SIZE" \
        || die "APCU_SHM_SIZE='$APCU_SHM_SIZE' is invalid. Expected e.g. 64M."
    is_byte_size "$OPCACHE_JIT_BUFFER_SIZE" \
        || die "OPCACHE_JIT_BUFFER_SIZE='$OPCACHE_JIT_BUFFER_SIZE' is invalid. Expected e.g. 128M or 0."

    is_integer "$PHP_MAX_EXECUTION_TIME" \
        || die "PHP_MAX_EXECUTION_TIME='$PHP_MAX_EXECUTION_TIME' is invalid. Expected seconds as a number (0 = unlimited)."
    is_integer "$OPCACHE_MEMORY_CONSUMPTION" \
        || die "OPCACHE_MEMORY_CONSUMPTION='$OPCACHE_MEMORY_CONSUMPTION' is invalid. Expected megabytes as a number."
    is_integer "$OPCACHE_MAX_ACCELERATED_FILES" \
        || die "OPCACHE_MAX_ACCELERATED_FILES='$OPCACHE_MAX_ACCELERATED_FILES' is invalid. Expected a number."
    is_integer "$OPCACHE_REVALIDATE_FREQ" \
        || die "OPCACHE_REVALIDATE_FREQ='$OPCACHE_REVALIDATE_FREQ' is invalid. Expected seconds as a number."
    is_integer "$XDEBUG_CLIENT_PORT" \
        || die "XDEBUG_CLIENT_PORT='$XDEBUG_CLIENT_PORT' is invalid. Expected a port number."
    is_integer "$XDEBUG_LOG_LEVEL" \
        || die "XDEBUG_LOG_LEVEL='$XDEBUG_LOG_LEVEL' is invalid. Expected 0-10."

    [ -n "$PHP_TIMEZONE" ] || die 'PHP_TIMEZONE is empty.'
    [ -n "$PHP_ERROR_REPORTING" ] || die 'PHP_ERROR_REPORTING is empty.'
}

# ---------------------------------------------------------------------------
# Rules derived from the resolved values
# ---------------------------------------------------------------------------

xdebug_is_active() {
    [ -n "$XDEBUG_MODE" ] && [ "$XDEBUG_MODE" != 'off' ]
}

# PCOV and Xdebug are mutually exclusive. PCOV wins because it was
# explicitly enabled.
enforce_pcov_xdebug_exclusion() {
    [ "$PCOV_ENABLED" = '1' ] || return 0
    xdebug_is_active || return 0

    log_info "PCOV is active - XDEBUG_MODE is set from '$XDEBUG_MODE' to 'off' (PCOV and Xdebug are mutually exclusive)."
    XDEBUG_MODE='off'
}

# JIT auto-policy. Without it, the entrypoint would write opcache.jit=1254
# together with xdebug.mode=debug into the ini; PHP then disables JIT itself
# and warns on every single call.
#
# This rule deliberately overrides an explicitly set OPCACHE_JIT too: the
# value would be technically ineffective, and leaving it would bring back
# exactly the warning this policy avoids. The change is logged.
enforce_jit_policy() {
    # The actual reason is not "Xdebug" but "an extension takes over
    # zend_execute_ex()" - true for both Xdebug and PCOV. PHP disables JIT
    # itself in both cases and warns on every call.
    _jit_blocker=''
    if xdebug_is_active; then
        _jit_blocker="Xdebug (XDEBUG_MODE=$XDEBUG_MODE)"
    elif [ "$PCOV_ENABLED" = '1' ]; then
        _jit_blocker='PCOV (PCOV_ENABLED=1)'
    else
        return 0
    fi

    case "$OPCACHE_JIT" in
        off|disable) return 0 ;;
    esac

    log_info "$_jit_blocker is active - opcache.jit is set from '$OPCACHE_JIT' to 'off'. PHP would otherwise disable JIT itself and warn on every call."
    OPCACHE_JIT='off'
    OPCACHE_JIT_BUFFER_SIZE='0'
}

# In prod, active Xdebug is a hard abort, not just a warning. This closes
# the misconfiguration risk in the image itself instead of relying on an
# external check.
guard_production() {
    [ "$APP_ENV" = 'prod' ] || return 0
    xdebug_is_active || return 0

    die "APP_ENV=prod, but Xdebug is active with XDEBUG_MODE='$XDEBUG_MODE'. This is not allowed in production (performance and attack surface). Either set XDEBUG_MODE=off or use APP_ENV=dev or test."
}

# ---------------------------------------------------------------------------
# Runtime ini destination
# ---------------------------------------------------------------------------
# The normal case is /home/$APP_USER/php-config, symlinked into conf.d -
# this lets the entrypoint write as appuser without making conf.d itself
# writable.
#
# If that directory is not writable, the container is running under an
# identity unknown to the image. The ini then falls back to a temporary
# directory wired in via PHP_INI_SCAN_DIR; the default conf.d must be
# listed explicitly there too, or the extension inis would be lost, and our
# directory comes after it so 99-runtime-config.ini is guaranteed to load
# last.
resolve_ini_dir() {
    INI_DIR="/home/$APP_USER/php-config"

    if [ -w "$INI_DIR" ]; then
        export INI_DIR
        return 0
    fi

    INI_DIR="${TMPDIR:-/tmp}/php-config"
    mkdir -p "$INI_DIR" \
        || die "Neither /home/$APP_USER/php-config nor $INI_DIR is writable."
    export PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:$INI_DIR"
    export INI_DIR

    log_warn "/home/$APP_USER/php-config is not writable (container running under an identity unknown to the image). The runtime ini falls back to $INI_DIR, wired in via PHP_INI_SCAN_DIR."
}

# ---------------------------------------------------------------------------
# ini generation
# ---------------------------------------------------------------------------
# The file is named 99-runtime-config.ini, guaranteeing it loads after all
# extension inis - in particular after 00-opcache.ini, which loads OPcache
# as a zend_extension ahead of Xdebug.
write_runtime_ini() {
    cat > "$INI_DIR/99-runtime-config.ini" <<PHPINI
; ---------------------------------------------------------------------------
; Generated at container start by entrypoint.sh - changes here are transient.
; APP_ENV=$APP_ENV
; ---------------------------------------------------------------------------
memory_limit = $PHP_MEMORY_LIMIT
max_execution_time = $PHP_MAX_EXECUTION_TIME
date.timezone = $PHP_TIMEZONE
error_reporting = $PHP_ERROR_REPORTING
display_errors = $PHP_DISPLAY_ERRORS
log_errors = $PHP_LOG_ERRORS
expose_php = Off

; APCu
apc.enabled = 1
apc.shm_size = $APCU_SHM_SIZE
apc.enable_cli = 1
apc.serializer = php

; OPcache + JIT
opcache.enable = $OPCACHE_ENABLE
opcache.enable_cli = $OPCACHE_ENABLE
opcache.memory_consumption = $OPCACHE_MEMORY_CONSUMPTION
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = $OPCACHE_MAX_ACCELERATED_FILES
opcache.validate_timestamps = $OPCACHE_VALIDATE_TIMESTAMPS
opcache.revalidate_freq = $OPCACHE_REVALIDATE_FREQ
opcache.fast_shutdown = 1
opcache.jit = $OPCACHE_JIT
opcache.jit_buffer_size = $OPCACHE_JIT_BUFFER_SIZE

; Xdebug - the mode is additionally exported as an environment variable,
; since Xdebug 3 gives it precedence over this setting.
xdebug.mode = $XDEBUG_MODE
xdebug.start_with_request = $XDEBUG_START_WITH_REQUEST
xdebug.client_host = $XDEBUG_CLIENT_HOST
xdebug.client_port = $XDEBUG_CLIENT_PORT
xdebug.log_level = $XDEBUG_LOG_LEVEL
xdebug.idekey = $XDEBUG_IDEKEY

; PCOV
pcov.enabled = $PCOV_ENABLED
PHPINI
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
apply_php_configuration() {
    APP_ENV="${APP_ENV:-dev}"
    export APP_ENV

    apply_env_profile
    require_image_values
    validate_values

    enforce_pcov_xdebug_exclusion
    guard_production
    enforce_jit_policy

    resolve_ini_dir
    write_runtime_ini

    log_info "APP_ENV=$APP_ENV: xdebug.mode=$XDEBUG_MODE, pcov=$PCOV_ENABLED, opcache=$OPCACHE_ENABLE (validate_timestamps=$OPCACHE_VALIDATE_TIMESTAMPS), jit=$OPCACHE_JIT"
}
