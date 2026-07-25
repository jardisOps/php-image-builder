# shellcheck shell=dash
# ---------------------------------------------------------------------------
# lib-user.sh — Angleichung des Laufzeit-Benutzers an den Eigentuemer von /app
# ---------------------------------------------------------------------------
# Wird von entrypoint.sh gesourct und nie direkt ausgefuehrt.
#
# Erwartet:  APP_USER, APP_ROOT, log_info/log_warn/die (aus entrypoint.sh)
# Optional:  APP_OWNED_PATHS — zusaetzliche, vom Image angelegte Pfade, die
#            appuser gehoeren (z.B. "/run/php-fpm" im fpm-Target). Erlaubt es
#            einem Target, A4.3 zu erfuellen, ohne diesen Kern anzufassen.
# Setzt:     RUNTIME_USER — Argument fuer su-exec; leer = kein Wechsel.
#
# Diese Datei ist ein struktureller Neubau (E7), kein Patch der bisherigen
# Heuristik. Die drei belegten Defekte des Bestands:
#   U1  groupmod/usermod scheiterten bei belegter Ziel-ID, und `2>/dev/null || true`
#       verschluckte den Fehler — die Anpassung fand nicht statt und trat spaeter
#       als unerklaerliches "Permission denied" auf. Alpine belegt u.a. GID 20
#       (dialout) und GID 100 (users), beides haeufige Host-GIDs.
#   U2  `[ "$HOST_UID" != "0" ]` uebersprang den Fall "/app gehoert root", also
#       genau das frische Named Volume, bei dem appuser nicht schreiben kann.
#   U3  usermod zog keinen chown nach; Dateien der alten UID verwaisten.
#
# Leitlinie: jede ID-Aenderung gelingt sichtbar oder scheitert sichtbar. Es gibt
# keinen Pfad, auf dem ein Fehler unterdrueckt wird.
# ---------------------------------------------------------------------------

# --- Abfragen ---------------------------------------------------------------

# Primaere GID von APP_USER (numerisch — der Gruppenname ist nach einer
# Wiederverwendung nicht mehr zwingend "appuser").
appuser_gid() { id -g "$APP_USER"; }
appuser_uid() { id -u "$APP_USER"; }

# chown-Eigentuemer-Angabe. Nutzt bewusst die numerische GID: nach
# `usermod -g <fremde GID>` existiert die Gruppe "appuser" noch mit ihrer alten
# GID, ein `chown appuser:appuser` wuerde also die falsche Gruppe setzen.
appuser_owner() { printf '%s:%s' "$APP_USER" "$(appuser_gid)"; }

uid_is_taken() { getent passwd "$1" >/dev/null 2>&1; }
gid_is_taken() { getent group  "$1" >/dev/null 2>&1; }

name_of_uid() { getent passwd "$1" | cut -d: -f1; }
name_of_gid() { getent group  "$1" | cut -d: -f1; }

dir_is_empty() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

# --- Angleichung ------------------------------------------------------------

# Primaergruppe von APP_USER auf die Ziel-GID bringen.
# Belegte Ziel-GID => die existierende Gruppe wird wiederverwendet (A4.1),
# statt sie umzunummerieren und damit ein Systemkonto zu beschaedigen.
align_group() {
    _lu_target="$1"

    [ "$(appuser_gid)" = "$_lu_target" ] && return 0

    if gid_is_taken "$_lu_target"; then
        log_info "GID $_lu_target ist von Gruppe '$(name_of_gid "$_lu_target")' belegt — sie wird wiederverwendet, statt umnummeriert."
        usermod -g "$_lu_target" "$APP_USER" \
            || die "Konnte $APP_USER nicht der bestehenden Gruppe mit GID $_lu_target zuordnen."
    else
        groupmod -g "$_lu_target" "$APP_USER" \
            || die "Konnte GID der Gruppe '$APP_USER' nicht auf $_lu_target aendern."
    fi

    LU_IDS_CHANGED=1
}

# UID von APP_USER auf die Ziel-UID bringen.
# Belegte Ziel-UID => der Prozess laeuft direkt unter der numerischen Kennung
# (A4.1, Wiederverwendung). APP_USER umzunummerieren ist hier unmoeglich:
# usermod verweigert eine belegte UID, und sie freizuraeumen hiesse, ein
# vorhandenes Konto zu beschaedigen.
align_user() {
    _lu_target="$1"

    [ "$(appuser_uid)" = "$_lu_target" ] && return 0

    if uid_is_taken "$_lu_target"; then
        log_warn "UID $_lu_target ist von Benutzer '$(name_of_uid "$_lu_target")' belegt. $APP_USER wird deshalb nicht umnummeriert; der Prozess laeuft direkt unter $_lu_target:$(appuser_gid). Schreibzugriff auf $APP_ROOT ist damit gegeben, HOME bleibt jedoch /home/$APP_USER und ist nicht beschreibbar."
        RUNTIME_USER="$_lu_target:$(appuser_gid)"
        return 0
    fi

    usermod -u "$_lu_target" "$APP_USER" \
        || die "Konnte UID von '$APP_USER' nicht auf $_lu_target aendern."

    LU_IDS_CHANGED=1
}

# A4.3 — nach einer ID-Aenderung alle vom Image angelegten, APP_USER
# zugeordneten Pfade nachziehen. Ohne diesen Schritt verwaisen sie bei der
# alten UID (U3). APP_ROOT ist bewusst NICHT dabei: dessen Eigentuemer ist die
# Vorgabe, an die wir uns gerade angepasst haben.
reown_image_paths() {
    [ "${LU_IDS_CHANGED:-0}" = '1' ] || return 0

    _lu_owner="$(appuser_owner)"
    for _lu_path in "/home/$APP_USER" ${APP_OWNED_PATHS:-}; do
        [ -e "$_lu_path" ] || continue
        chown -R "$_lu_owner" "$_lu_path" \
            || die "Konnte $_lu_path nicht auf $_lu_owner uebertragen."
    done
    log_info "Eigentum nachgezogen auf $_lu_owner: /home/$APP_USER ${APP_OWNED_PATHS:-}"
}

# A4.2 — /app gehoert root. Der Bestand uebersprang diesen Fall und lief in ein
# nicht schreibbares Volume. Behandelt wird er, indem das Verzeichnis selbst an
# APP_USER uebergeht; ein rekursives chown findet bewusst nicht statt, weil es
# auf einem bind-gemounteten, absichtlich root-eigenen Baum fremde Daten
# umschreiben wuerde.
claim_root_owned_app_root() {
    _lu_owner="$(appuser_owner)"

    chown "$_lu_owner" "$APP_ROOT" \
        || die "$APP_ROOT gehoert root und liess sich nicht an $_lu_owner uebertragen."

    if dir_is_empty "$APP_ROOT"; then
        log_info "$APP_ROOT gehoerte root und ist leer (frisches Named Volume) — Eigentum an $_lu_owner uebertragen."
    else
        log_warn "$APP_ROOT gehoerte root und ist nicht leer. Uebertragen wurde nur das Verzeichnis selbst, die Inhalte gehoeren weiter root. Bei Schreibfehlern: Eigentuemer auf dem Host korrigieren oder den Container mit --user <uid>:<gid> starten."
    fi
}

# --- Einstiegspunkt ---------------------------------------------------------

# Bestimmt, unter welcher Kennung die Nutzlast laufen soll, und stellt die dafuer
# noetigen Eigentumsverhaeltnisse her.
align_runtime_user() {
    RUNTIME_USER=''
    LU_IDS_CHANGED=0

    # A4.4 — von aussen bereits per --user gestartet. Dann ist die Kennung eine
    # Vorgabe des Aufrufers und wird nicht angetastet; ohne root-Rechte waere
    # jede Anpassung ohnehin unmoeglich.
    if [ "$(id -u)" != '0' ]; then
        log_info "Laeuft als UID $(id -u):$(id -g) (von aussen vorgegeben) — keine Anpassung."
        return 0
    fi

    # shellcheck disable=SC2034  # von entrypoint.sh (handover) gelesen, nicht hier
    RUNTIME_USER="$APP_USER"

    if [ ! -d "$APP_ROOT" ]; then
        log_info "$APP_ROOT existiert nicht — keine Anpassung noetig."
        return 0
    fi

    _lu_app_uid="$(stat -c '%u' "$APP_ROOT")" \
        || die "Konnte den Eigentuemer von $APP_ROOT nicht ermitteln."
    _lu_app_gid="$(stat -c '%g' "$APP_ROOT")" \
        || die "Konnte die Gruppe von $APP_ROOT nicht ermitteln."

    if [ "$_lu_app_uid" = '0' ]; then
        claim_root_owned_app_root
        return 0
    fi

    align_group "$_lu_app_gid"
    align_user  "$_lu_app_uid"
    reown_image_paths
}
