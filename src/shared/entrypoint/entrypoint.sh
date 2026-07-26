#!/bin/sh
# ---------------------------------------------------------------------------
# entrypoint.sh - shared entrypoint core for all PHP targets
# ---------------------------------------------------------------------------
# Used unchanged by both cli and fpm so the logic is not duplicated per target.
#
# Flow:
#   1. Align the runtime user with the owner of /app        (lib-user.sh)
#   2. Build the PHP configuration from APP_ENV + overrides  (lib-phpini.sh)
#   3. Run target-specific extensions                        (entrypoint.d/)
#   4. Drop privileges and hand over to the payload
#
# Target-specific parts (e.g. FPM pool generation) live as separate scripts in
# /usr/local/lib/entrypoint.d/ and are only collected here; this core knows no
# target by name.
#
# POSIX sh, not bash, so the same core also runs on an image without bash.
# Checked with shellcheck in the dash dialect.
# ---------------------------------------------------------------------------
set -eu

ENTRYPOINT_LIB_DIR='/usr/local/lib/entrypoint'
ENTRYPOINT_EXT_DIR='/usr/local/lib/entrypoint.d'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Everything goes to stderr so stdout stays clean for the payload - this
# matters because `docker run ... php -r ...` output may be parsed by tooling.
log_info() { printf 'entrypoint: %s\n' "$1" >&2; }
log_warn() { printf 'entrypoint: WARNING: %s\n' "$1" >&2; }

# Aborts visibly. No caller suppresses this path.
die() {
    printf 'entrypoint: ERROR: %s\n' "$1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Libraries
# ---------------------------------------------------------------------------
# shellcheck source=./lib-user.sh
. "$ENTRYPOINT_LIB_DIR/lib-user.sh"
# shellcheck source=./lib-phpini.sh
. "$ENTRYPOINT_LIB_DIR/lib-phpini.sh"

# ---------------------------------------------------------------------------
# Target extensions
# ---------------------------------------------------------------------------
# Every *.sh in entrypoint.d is sourced and may use the already-resolved
# values plus INI_DIR, APP_USER, and the log functions. Order is lexical.
run_target_extensions() {
    [ -d "$ENTRYPOINT_EXT_DIR" ] || return 0

    for _ep_ext in "$ENTRYPOINT_EXT_DIR"/*.sh; do
        [ -f "$_ep_ext" ] || continue
        log_info "target extension: $(basename "$_ep_ext")"
        # shellcheck source=/dev/null
        . "$_ep_ext"
    done
}

# ---------------------------------------------------------------------------
# Handover to the payload
# ---------------------------------------------------------------------------
# The container runs as root only for one-time initialization and drops
# privileges here. `exec` replaces the shell so the payload becomes PID 1 and
# receives signals directly.
#
# An empty RUNTIME_USER means no switch: the payload runs as root and handles
# the privilege change itself - that is what php-fpm needs, see below.
#
# A `chown` on /proc/self/fd/{1,2} was deliberately removed here: that path is
# a symlink to an anonymous pipe, and pipefs silently ignores ownership
# changes on it (the chown reports exit 0 even though nothing happened). The
# fpm target instead starts php-fpm as root and lets it drop its own workers
# via `user =` in the pool config - the model the official php:X-fpm image
# also uses.
handover() {
    if [ "$(id -u)" != '0' ]; then
        exec "$@"
    fi

    if [ -z "$RUNTIME_USER" ]; then
        exec "$@"
    fi

    exec su-exec "$RUNTIME_USER" "$@"
}

# ---------------------------------------------------------------------------
# Orchestration - no logic of its own, only chaining
# ---------------------------------------------------------------------------
main() {
    align_runtime_user
    apply_php_configuration
    run_target_extensions
    handover "$@"
}

main "$@"
