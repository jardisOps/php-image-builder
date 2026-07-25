# shellcheck shell=dash
# ---------------------------------------------------------------------------
# fpm-pool.sh — Target-Ergaenzung des fpm-Images (A3.2)
# ---------------------------------------------------------------------------
# Liegt im Image unter /usr/local/lib/entrypoint.d/ und wird von entrypoint.sh
# gesourct, nachdem der Laufzeit-Benutzer bestimmt und die PHP-INI erzeugt ist.
# Der Kern kennt dieses Target nicht — er sammelt nur ein, was in entrypoint.d
# liegt. Das ist der ganze Unterschied zwischen fpm und cli auf Skriptebene.
#
# Erwartet aus dem Kern: APP_USER, INI_DIR, RUNTIME_USER, appuser_gid(),
#                        log_info/log_warn/die
# Setzt:                 RUNTIME_USER='' — siehe "Rechtewechsel" unten
#
# ---------------------------------------------------------------------------
# RECHTEWECHSEL (N4, entschieden 2026-07-25: Variante b)
# ---------------------------------------------------------------------------
# FPM startet als root und wechselt seine Worker SELBST ueber `user =` in dieser
# Pool-Config. Der Master bleibt root, die Worker laufen unprivilegiert — das von
# PHP vorgesehene Betriebsmodell, das auch das offizielle php:X-fpm-Image nutzt
# (`user = www-data` in www.conf).
#
# Der Weg des Bestands (Entrypoint wechselt per su-exec, Master unprivilegiert)
# ist NICHT umsetzbar: FPM oeffnet das globale error_log (/proc/self/fd/2) nach
# dem Wechsel neu und scheitert daran. Der Griff, der das verhindern sollte —
# `chown` auf die stdio-Deskriptoren — ist wirkungslos, weil dort eine anonyme
# Pipe haengt. Belegt: headgent/phpfpm:8.2/:8.3/:8.4 starten deshalb alle nicht.
# Ausfuehrlich in entrypoint.sh bei handover() und in docs/PROGRESS.md (B9).
#
# Sicherheitseinordnung: der Master parst die Konfiguration, oeffnet Socket und
# Logs und verwaltet Worker — er verarbeitet KEINE Requests. Der gesamte
# Angriffskontakt liegt in den Workern, und die sind unprivilegiert.
# ---------------------------------------------------------------------------

FPM_VALUE_HINT='ist nicht gesetzt — dieser Wert muss als ENV aus dem Image kommen (src/fpm/Dockerfile, gespeist aus der .env).'

_fpm_require_values() {
    : "${FPM_PM:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_CHILDREN:?$FPM_VALUE_HINT}" \
      "${FPM_PM_START_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MIN_SPARE_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_SPARE_SERVERS:?$FPM_VALUE_HINT}" \
      "${FPM_PM_MAX_REQUESTS:?$FPM_VALUE_HINT}"

    case "$FPM_PM" in
        static|dynamic|ondemand) ;;
        *) die "FPM_PM='$FPM_PM' ist ungueltig. Erlaubt: static, dynamic, ondemand." ;;
    esac
}

# ---------------------------------------------------------------------------
# Zielkennung der Worker
# ---------------------------------------------------------------------------
# Uebernimmt, was lib-user.sh ermittelt hat, statt "appuser" fest anzunehmen:
#
#   RUNTIME_USER='appuser'   Regelfall — die Gruppe wird NUMERISCH gesetzt, weil
#                            nach einer Angleichung an eine belegte Ziel-GID die
#                            Gruppe "appuser" noch mit ihrer alten GID existiert
#                            (derselbe Grund wie bei appuser_owner()).
#   RUNTIME_USER='1:1000'    Ziel-UID war belegt, appuser wurde nicht
#                            umnummeriert — die Worker laufen direkt unter der
#                            numerischen Kennung.
#   RUNTIME_USER=''          Container wurde von aussen per --user gestartet
#                            (A4.4). FPM laeuft dann nicht als root und wuerde
#                            user/group mit einer NOTICE verwerfen — deshalb
#                            werden die beiden Zeilen weggelassen.
_fpm_resolve_worker_identity() {
    FPM_USER_LINES=''

    [ -n "${RUNTIME_USER:-}" ] || {
        log_info "Container laeuft unter einer von aussen vorgegebenen Kennung — die Pool-Direktiven user/group entfallen, FPM uebernimmt die laufende Kennung."
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
# Pool-Konfiguration
# ---------------------------------------------------------------------------
# Die Datei heisst zz-fpm-runtime.conf und wird damit als letzte aus
# php-fpm.d/*.conf gelesen — sie ueberschreibt die Vorgaben des offiziellen
# Images (www.conf, zz-docker.conf). Sie liegt in INI_DIR und haengt per Symlink
# in php-fpm.d/, genau wie 99-runtime-config.ini in conf.d haengt.
_fpm_write_pool_config() {
    cat > "$INI_DIR/zz-fpm-runtime.conf" <<FPMCONF
; ---------------------------------------------------------------------------
; Erzeugt beim Containerstart von entrypoint.d/10-fpm-pool.sh — fluechtig.
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

; /ping traegt den Healthcheck des Images, /status die Betriebsbeobachtung.
pm.status_path = /status
ping.path = /ping
ping.response = pong

access.log = /dev/stdout
slowlog = /dev/stderr
request_slowlog_timeout = 5s

; clear_env=no ist Voraussetzung dafuer, dass die Worker die vom Entrypoint
; aufgeloesten Werte sehen — insbesondere XDEBUG_MODE, dem Xdebug 3 Vorrang vor
; der INI gibt (A10.5).
clear_env = no
catch_workers_output = yes
decorate_workers_output = no
FPMCONF
}

# ---------------------------------------------------------------------------
# Ausfuehrung (die Datei wird gesourct, es gibt keinen eigenen Einstiegspunkt)
# ---------------------------------------------------------------------------
_fpm_require_values
_fpm_resolve_worker_identity
_fpm_write_pool_config

# Der Symlink in php-fpm.d/ zeigt fest auf /home/$APP_USER/php-config/. Ist
# INI_DIR ausgewichen (A4.4-Ausweichpfad in lib-phpini.sh), findet FPM die Datei
# dort nicht und faellt auf die Vorgaben des offiziellen Images zurueck. Das wird
# gemeldet statt verschwiegen.
[ "$INI_DIR" = "/home/$APP_USER/php-config" ] || \
    log_warn "Die Pool-Konfiguration liegt in $INI_DIR, der Symlink in php-fpm.d/ zeigt aber auf /home/$APP_USER/php-config. FPM startet mit den Vorgaben des Basis-Images; die FPM_PM_*-Werte wirken nicht."

# Kein su-exec: FPM braucht root, um sein error_log zu oeffnen und danach selbst
# auf die Worker-Kennung zu wechseln (N4-Variante b, s.o.). handover() im Kern
# uebergibt bei leerem RUNTIME_USER direkt per exec.
RUNTIME_USER=''

if [ -n "$FPM_USER_LINES" ]; then
    log_info "FPM-Pool erzeugt: pm=$FPM_PM, max_children=$FPM_PM_MAX_CHILDREN, Worker laufen als $_fpm_user:$_fpm_group (Master bleibt root)."
else
    log_info "FPM-Pool erzeugt: pm=$FPM_PM, max_children=$FPM_PM_MAX_CHILDREN, Worker laufen unter der von aussen vorgegebenen Kennung."
fi
