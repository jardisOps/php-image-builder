# shellcheck shell=dash
# ---------------------------------------------------------------------------
# fpm-pool.sh — target addition for the fpm image
# ---------------------------------------------------------------------------
# Lives in the image under /usr/local/lib/entrypoint.d/ and is sourced by
# entrypoint.sh after the runtime user has been determined and the PHP INI
# generated. The core does not know this target — it only collects whatever
# lives in entrypoint.d. That is the entire difference between fpm and cli at
# the script level.
#
# Expected from the core: APP_USER, INI_DIR, RUNTIME_USER, appuser_gid(),
#                          log_info/log_warn/die
# Sets:                    RUNTIME_USER='' — see "privilege handover" below
#
# ---------------------------------------------------------------------------
# PRIVILEGE HANDOVER
# ---------------------------------------------------------------------------
# FPM starts as root and switches its workers itself via `user =` in this
# pool config. The master stays root, the workers run unprivileged — the
# operating model PHP itself intends and the one the official php:X-fpm image
# uses (`user = www-data` in www.conf).
#
# The alternative (entrypoint switches via su-exec, master unprivileged) is
# not viable: FPM reopens the global error_log (/proc/self/fd/2) after the
# switch and fails, because it is an anonymous pipe there and `chown` on the
# stdio descriptors has no effect on it. Details in entrypoint.sh at
# handover().
#
# Security note: the master parses the configuration, opens the socket and
# logs, and manages workers — it processes NO requests. The entire attack
# surface lies in the workers, and those are unprivileged.
# ---------------------------------------------------------------------------

FPM_VALUE_HINT='is not set — this value must come as an ENV from the image (src/fpm/Dockerfile, fed from .env).'

_fpm_require_values() {
    : "${FPM_PM:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_CHILDREN:?$FPM_VALUE_HINT}" \
      "${FPM_PM_START_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MIN_SPARE_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_SPARE_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_REQUESTS:?$FPM_VALUE_HINT}"

    case "$FPM_PM" in
        static|dynamic|ondemand) ;;
        *) die "FPM_PM='$FPM_PM' is invalid. Allowed: static, dynamic, ondemand." ;;
    esac
}

# ---------------------------------------------------------------------------
# Worker identity
# ---------------------------------------------------------------------------
# Takes over what lib-user.sh has determined instead of assuming "appuser":
#
#   RUNTIME_USER='appuser'   Normal case — the group is set NUMERICALLY,
#                            because after alignment to an already-taken
#                            target GID the "appuser" group still exists
#                            under its old GID (same reason as appuser_owner()).
#   RUNTIME_USER='1:1000'    Target UID was taken, appuser was not
#                            renumbered — the workers run directly under the
#                            numeric identity.
#   RUNTIME_USER=''          Container was started from outside via --user.
#                            FPM then does not run as root and would discard
#                            user/group with a NOTICE — so both lines are
#                            omitted.
_fpm_resolve_worker_identity() {
    FPM_USER_LINES=''

    [ -n "${RUNTIME_USER:-}" ] || {
        log_info "Container is running under an externally supplied identity — the user/group pool directives are omitted, FPM keeps the running identity."
        return 0
    }

    case "$RUNTIME_USER" in
        *:*) _fpm_user="${RUNTIME_USER%%:*}"; _fpm_group="${RUNTIME_USER#*:}" ;;
        *)   _fpm_user="$RUNTIME_USER";       _fpm_group="$(appuser_gid)" ;;
    esac

    FPM_USER_LINES="user = $_fpm_user
group = $_fpm_group
listen.owner = $_fpm_user
listen.group = $_fpm_group"
}

# ---------------------------------------------------------------------------
# Pool configuration
# ---------------------------------------------------------------------------
# The file is named zz-fpm-runtime.conf and is thereby read last from
# php-fpm.d/*.conf — it overrides the official image's defaults (www.conf,
# zz-docker.conf). It lives in INI_DIR and is linked into php-fpm.d/, the same
# way 99-runtime-config.ini is linked in conf.d.
_fpm_write_pool_config() {
    cat > "$INI_DIR/zz-fpm-runtime.conf" <<FPMCONF
; ---------------------------------------------------------------------------
; Generated at container start by entrypoint.d/10-fpm-pool.sh — transient.
; APP_ENV=$APP_ENV
; ---------------------------------------------------------------------------
[www]
$FPM_USER_LINES
listen = 9000

pm = $FPM_PM
pm.max_children = $FPM_PM_MAX_CHILDREN
pm.start_servers = $FPM_PM_START_SERVERS
pm.min_spare_servers = $FPM_PM_MIN_SPARE_SERVERS
pm.max_spare_servers = $FPM_PM_MAX_SPARE_SERVERS
pm.max_requests = $FPM_PM_MAX_REQUESTS

; /ping carries the image's healthcheck, /status is for operational monitoring.
pm.status_path = /status
ping.path = /ping
ping.response = pong

access.log = /dev/stdout
slowlog = /dev/stderr
request_slowlog_timeout = 5s

; clear_env=no is required so the workers see the values resolved by the
; entrypoint — in particular XDEBUG_MODE, which Xdebug 3 gives precedence
; over the INI.
clear_env = no
catch_workers_output = yes
decorate_workers_output = no
FPMCONF
}

# ---------------------------------------------------------------------------
# Execution (this file is sourced, it has no entry point of its own)
# ---------------------------------------------------------------------------
_fpm_require_values
_fpm_resolve_worker_identity
_fpm_write_pool_config

# The symlink in php-fpm.d/ points at a fixed /home/$APP_USER/php-config/. If
# INI_DIR fell back to a different path, FPM won't find the file there and
# falls back to the official image's defaults. This is reported, not
# silenced.
[ "$INI_DIR" = "/home/$APP_USER/php-config" ] || \
    log_warn "The pool configuration lives in $INI_DIR, but the symlink in php-fpm.d/ points at /home/$APP_USER/php-config. FPM starts with the base image's defaults; the FPM_PM_* values have no effect."

# No su-exec: FPM needs root to open its error_log and then switch to the
# worker identity itself (see privilege handover above). handover() in the
# core hands off directly via exec when RUNTIME_USER is empty.
RUNTIME_USER=''

if [ -n "$FPM_USER_LINES" ]; then
    log_info "FPM pool created: pm=$FPM_PM, max_children=$FPM_PM_MAX_CHILDREN, workers run as $_fpm_user:$_fpm_group (master stays root)."
else
    log_info "FPM pool created: pm=$FPM_PM, max_children=$FPM_PM_MAX_CHILDREN, workers run under the externally supplied identity."
fi
