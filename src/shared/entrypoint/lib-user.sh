# shellcheck shell=dash
# ---------------------------------------------------------------------------
# lib-user.sh - align the runtime user with the owner of /app
# ---------------------------------------------------------------------------
# Sourced by entrypoint.sh, never executed directly.
#
# Expects: APP_USER, APP_ROOT, log_info/log_warn/die (from entrypoint.sh)
# Optional: APP_OWNED_PATHS - additional image-created paths owned by
#           appuser (e.g. "/run/php-fpm" in the fpm target), letting a
#           target extend ownership without touching this core.
# Sets:     RUNTIME_USER - argument for su-exec; empty means no switch.
#
# Every ID change either succeeds visibly or fails visibly; no path here
# silently swallows an error.
# ---------------------------------------------------------------------------

# --- Queries -----------------------------------------------------------------

# Primary GID of APP_USER (numeric - the group name is no longer guaranteed
# to be "appuser" after a reuse).
appuser_gid() { id -g "$APP_USER"; }
appuser_uid() { id -u "$APP_USER"; }

# chown owner spec. Uses the numeric GID deliberately: after
# `usermod -g <foreign GID>` the "appuser" group still exists under its old
# GID, so `chown appuser:appuser` would set the wrong group.
appuser_owner() { printf '%s:%s' "$APP_USER" "$(appuser_gid)"; }

uid_is_taken() { getent passwd "$1" >/dev/null 2>&1; }
gid_is_taken() { getent group  "$1" >/dev/null 2>&1; }

name_of_uid() { getent passwd "$1" | cut -d: -f1; }
name_of_gid() { getent group  "$1" | cut -d: -f1; }

dir_is_empty() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

# --- Alignment -----------------------------------------------------------------

# Bring APP_USER's primary group to the target GID.
# A taken target GID means the existing group is reused instead of
# renumbering it and damaging a system account.
align_group() {
    _lu_target="$1"

    [ "$(appuser_gid)" = "$_lu_target" ] && return 0

    if gid_is_taken "$_lu_target"; then
        log_info "GID $_lu_target is taken by group '$(name_of_gid "$_lu_target")' - reusing it instead of renumbering."
        usermod -g "$_lu_target" "$APP_USER" \
            || die "Could not assign $APP_USER to the existing group with GID $_lu_target."
    else
        groupmod -g "$_lu_target" "$APP_USER" \
            || die "Could not change the GID of group '$APP_USER' to $_lu_target."
    fi

    LU_IDS_CHANGED=1
}

# Bring APP_USER's UID to the target UID.
# A taken target UID means the process runs directly under that numeric ID
# instead: usermod refuses a taken UID, and freeing it would damage an
# existing account.
align_user() {
    _lu_target="$1"

    [ "$(appuser_uid)" = "$_lu_target" ] && return 0

    if uid_is_taken "$_lu_target"; then
        log_warn "UID $_lu_target is taken by user '$(name_of_uid "$_lu_target")'. $APP_USER is therefore not renumbered; the process runs directly as $_lu_target:$(appuser_gid). Write access to $APP_ROOT is thereby given, but HOME stays /home/$APP_USER and is not writable."
        RUNTIME_USER="$_lu_target:$(appuser_gid)"
        return 0
    fi

    usermod -u "$_lu_target" "$APP_USER" \
        || die "Could not change the UID of '$APP_USER' to $_lu_target."

    LU_IDS_CHANGED=1
}

# After an ID change, re-chown every image-created path owned by APP_USER -
# otherwise they stay orphaned under the old UID. APP_ROOT is deliberately
# excluded: its ownership is the target we just aligned to.
reown_image_paths() {
    [ "${LU_IDS_CHANGED:-0}" = '1' ] || return 0

    _lu_owner="$(appuser_owner)"
    for _lu_path in "/home/$APP_USER" ${APP_OWNED_PATHS:-}; do
        [ -e "$_lu_path" ] || continue
        chown -R "$_lu_owner" "$_lu_path" \
            || die "Could not transfer $_lu_path to $_lu_owner."
    done
    log_info "Ownership transferred to $_lu_owner: /home/$APP_USER ${APP_OWNED_PATHS:-}"
}

# /app is owned by root. Handled by transferring the directory itself to
# APP_USER; a recursive chown is deliberately skipped, since it would rewrite
# foreign data on a bind-mounted, intentionally root-owned tree.
claim_root_owned_app_root() {
    _lu_owner="$(appuser_owner)"

    chown "$_lu_owner" "$APP_ROOT" \
        || die "$APP_ROOT is owned by root and could not be transferred to $_lu_owner."

    if dir_is_empty "$APP_ROOT"; then
        log_info "$APP_ROOT was owned by root and is empty (fresh named volume) - ownership transferred to $_lu_owner."
    else
        log_warn "$APP_ROOT was owned by root and is not empty. Only the directory itself was transferred; its contents remain owned by root. On write errors: fix ownership on the host or start the container with --user <uid>:<gid>."
    fi
}

# --- Entry point ---------------------------------------------------------

# Determines which identity the payload should run as and establishes the
# ownership needed for it.
align_runtime_user() {
    RUNTIME_USER=''
    LU_IDS_CHANGED=0

    # Already started with --user from outside: that identity is the
    # caller's choice and is left untouched; without root, no adjustment
    # would be possible anyway.
    if [ "$(id -u)" != '0' ]; then
        log_info "Running as UID $(id -u):$(id -g) (given from outside) - no adjustment."
        return 0
    fi

    # shellcheck disable=SC2034  # read by entrypoint.sh (handover), not here
    RUNTIME_USER="$APP_USER"

    if [ ! -d "$APP_ROOT" ]; then
        log_info "$APP_ROOT does not exist - no adjustment needed."
        return 0
    fi

    _lu_app_uid="$(stat -c '%u' "$APP_ROOT")" \
        || die "Could not determine the owner of $APP_ROOT."
    _lu_app_gid="$(stat -c '%g' "$APP_ROOT")" \
        || die "Could not determine the group of $APP_ROOT."

    if [ "$_lu_app_uid" = '0' ]; then
        claim_root_owned_app_root
        return 0
    fi

    align_group "$_lu_app_gid"
    align_user  "$_lu_app_uid"
    reown_image_paths
}
