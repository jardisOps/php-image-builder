# shellcheck shell=dash
# ---------------------------------------------------------------------------
# lib-phpini.sh — APP_ENV-Profile und Erzeugung der Laufzeit-INI
# ---------------------------------------------------------------------------
# Wird von entrypoint.sh gesourct und nie direkt ausgefuehrt.
#
# Erwartet: APP_USER, log_info/log_warn/die (aus entrypoint.sh)
# Setzt:    die aufgeloesten PHP-Einstellungen (exportiert) sowie INI_DIR
#
# VORRANGREGEL (A10.2), von stark nach schwach:
#   1. explizit gesetzte Einzelvariable   (docker run -e XDEBUG_MODE=trace)
#   2. APP_ENV-Profil                     (dev | test | prod)
#
# "Nicht gesetzt" und "leer" sind bewusst gleichbedeutend: die .env fuehrt die
# profilgesteuerten Variablen als leere Slots, damit das Profil greifen kann.
#
# Eine dritte Stufe mit Notwerten gibt es bewusst NICHT (Freigabe Rolf,
# 2026-07-25). A10.2 nennt einen Fallback, er wuerde aber nie greifen: die
# Profiltabelle deckt jede Profilvariable in jeder Umgebung ab, und die
# profilunabhaengigen Werte bringt das Image mit. Fehlt einer, ist das ein
# Build-Fehler — der bricht hier sichtbar ab, statt hinter einem Notwert
# unentdeckt zu bleiben.
# ---------------------------------------------------------------------------

APP_ENV_VALUES='dev test prod'

# ---------------------------------------------------------------------------
# Profiltabelle — die EINZIGE Stelle, an der Profilwerte stehen
# ---------------------------------------------------------------------------
#
#                              dev        test       prod
#   XDEBUG_MODE                debug      off        off
#   PCOV_ENABLED               0          1          0
#   OPCACHE_ENABLE             1          1          1
#   OPCACHE_VALIDATE_TIMESTAMPS 1         1          0
#   OPCACHE_REVALIDATE_FREQ    0          0          0
#   OPCACHE_JIT                1254*      1254       1254
#   PHP_DISPLAY_ERRORS         On         On         Off
#   PHP_ERROR_REPORTING        E_ALL      E_ALL      E_ALL & ~E_DEPRECATED
#
#   * in dev schaltet die JIT-Automatik (A10.3) den Wert auf 'off', weil Xdebug
#     dort aktiv ist. Der Profilwert bleibt 1254, damit ein bewusstes
#     XDEBUG_MODE=off in dev sofort einen nutzbaren JIT ergibt.
#
# Begruendungen der Abweichungen vom Bestand:
#   OPCACHE_VALIDATE_TIMESTAMPS  behebt L-C und D3 — heute bemerkt FPM im
#                                Entwicklungsbetrieb keine Code-Aenderung, und
#                                phpcli setzte den Wert ueberhaupt nicht (A10.6).
#   PHP_DISPLAY_ERRORS=On in dev behebt L-D (beide .env hatten Off).
#   PHP_ERROR_REPORTING ohne E_STRICT behebt L-G (seit PHP 8.0 bedeutungslos).
#   XDEBUG_MODE=off in test    behebt L-B — der Default musste bisher in jedem
#                                einzelnen Testaufruf abgeschaltet werden.
#
# Umsetzung: `${VAR:=wert}` setzt nur, wenn VAR nicht gesetzt oder leer ist —
# dieses eine Sprachmittel IST die Vorrangregel A10.2. Werte, die in allen
# Umgebungen gleich sind, stehen vor dem `case`; im `case` steht damit
# ausschliesslich, was sich zwischen den Umgebungen tatsaechlich unterscheidet.
apply_env_profile() {
    # In allen Umgebungen gleich, ueber ihren Slot dennoch uebersteuerbar.
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
            die "APP_ENV='$APP_ENV' ist ungueltig. Erlaubt: $APP_ENV_VALUES."
            ;;
    esac

    # A10.5 — der Export ist fuer XDEBUG_MODE zwingend: Xdebug 3 liest die
    # Umgebungsvariable und gibt ihr Vorrang vor der INI-Einstellung. Im Bestand
    # funktionierte das nur zufaellig, weil die Variable aus der Image-ENV stammte
    # und ihr Export-Attribut behielt, obwohl der Entrypoint sie ohne `export`
    # ueberschrieb. Hier ist es ausdruecklich — und gilt fuer alle Werte, damit
    # Kindprozesse dieselbe Konfiguration sehen wie die erzeugte INI.
    export XDEBUG_MODE PCOV_ENABLED OPCACHE_ENABLE OPCACHE_VALIDATE_TIMESTAMPS \
           OPCACHE_REVALIDATE_FREQ OPCACHE_JIT PHP_DISPLAY_ERRORS PHP_ERROR_REPORTING
}

# ---------------------------------------------------------------------------
# Werte, die das Image mitbringen muss
# ---------------------------------------------------------------------------
# Profilunabhaengig: sie folgen nicht der Umgebung, sondern dem Einsatzzweck des
# Targets (z.B. max_execution_time: 0 im CLI, 30 im Request-Kontext). Sie kommen
# als ENV aus dem Dockerfile, gespeist aus der .env. Fehlt einer, bricht der
# Start ab — siehe Kopfkommentar. `${VAR:?hinweis}` erledigt Pruefung und
# Abbruch in einem Schritt.
IMAGE_VALUE_HINT='ist nicht gesetzt — dieser Wert muss als ENV aus dem Image kommen (Dockerfile, gespeist aus der .env). Es gibt bewusst keinen Notwert, weil ein fehlender Wert ein Build-Fehler ist.'

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
# Validierung (A10.7, behebt L-E)
# ---------------------------------------------------------------------------

is_integer()   { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_byte_size() { printf '%s' "$1" | grep -Eq '^[0-9]+[KMGkmg]?$'; }
is_onoff()     { case "$1" in On|Off|on|off|1|0|stderr) return 0 ;; *) return 1 ;; esac; }

# Xdebug 3 akzeptiert eine kommaseparierte Liste dieser Modi.
XDEBUG_MODES='off develop coverage debug gcstats profile trace'

validate_xdebug_mode() {
    _lp_old_ifs="$IFS"; IFS=','
    for _lp_mode in $1; do
        case " $XDEBUG_MODES " in
            *" $_lp_mode "*) ;;
            *) IFS="$_lp_old_ifs"
               die "XDEBUG_MODE enthaelt den unbekannten Modus '$_lp_mode'. Erlaubt (kommasepariert): $XDEBUG_MODES." ;;
        esac
    done
    IFS="$_lp_old_ifs"
}

# APP_ENV selbst wird nicht hier geprueft, sondern vom `case` in
# apply_env_profile: ein unbekannter Wert trifft dort den *)-Zweig und bricht ab.
validate_values() {
    validate_xdebug_mode "$XDEBUG_MODE"

    case "$PCOV_ENABLED" in 0|1) ;; *)
        die "PCOV_ENABLED='$PCOV_ENABLED' ist ungueltig. Erlaubt: 0 oder 1." ;;
    esac

    case "$OPCACHE_ENABLE" in 0|1) ;; *)
        die "OPCACHE_ENABLE='$OPCACHE_ENABLE' ist ungueltig. Erlaubt: 0 oder 1." ;;
    esac

    case "$OPCACHE_VALIDATE_TIMESTAMPS" in 0|1) ;; *)
        die "OPCACHE_VALIDATE_TIMESTAMPS='$OPCACHE_VALIDATE_TIMESTAMPS' ist ungueltig. Erlaubt: 0 oder 1." ;;
    esac

    # opcache.jit nimmt 'off'/'disable'/'tracing'/'function' oder vier Ziffern (CRTO).
    case "$OPCACHE_JIT" in
        off|disable|on|tracing|function) ;;
        *) is_integer "$OPCACHE_JIT" \
            || die "OPCACHE_JIT='$OPCACHE_JIT' ist ungueltig. Erlaubt: off, disable, on, tracing, function oder eine vierstellige CRTO-Zahl wie 1254." ;;
    esac

    is_onoff "$PHP_DISPLAY_ERRORS" \
        || die "PHP_DISPLAY_ERRORS='$PHP_DISPLAY_ERRORS' ist ungueltig. Erlaubt: On, Off oder stderr."
    is_onoff "$PHP_LOG_ERRORS" \
        || die "PHP_LOG_ERRORS='$PHP_LOG_ERRORS' ist ungueltig. Erlaubt: On oder Off."

    is_byte_size "$PHP_MEMORY_LIMIT" \
        || die "PHP_MEMORY_LIMIT='$PHP_MEMORY_LIMIT' ist ungueltig. Erwartet z.B. 512M."
    is_byte_size "$APCU_SHM_SIZE" \
        || die "APCU_SHM_SIZE='$APCU_SHM_SIZE' ist ungueltig. Erwartet z.B. 64M."
    is_byte_size "$OPCACHE_JIT_BUFFER_SIZE" \
        || die "OPCACHE_JIT_BUFFER_SIZE='$OPCACHE_JIT_BUFFER_SIZE' ist ungueltig. Erwartet z.B. 128M oder 0."

    is_integer "$PHP_MAX_EXECUTION_TIME" \
        || die "PHP_MAX_EXECUTION_TIME='$PHP_MAX_EXECUTION_TIME' ist ungueltig. Erwartet Sekunden als Zahl (0 = unbegrenzt)."
    is_integer "$OPCACHE_MEMORY_CONSUMPTION" \
        || die "OPCACHE_MEMORY_CONSUMPTION='$OPCACHE_MEMORY_CONSUMPTION' ist ungueltig. Erwartet Megabyte als Zahl."
    is_integer "$OPCACHE_MAX_ACCELERATED_FILES" \
        || die "OPCACHE_MAX_ACCELERATED_FILES='$OPCACHE_MAX_ACCELERATED_FILES' ist ungueltig. Erwartet eine Zahl."
    is_integer "$OPCACHE_REVALIDATE_FREQ" \
        || die "OPCACHE_REVALIDATE_FREQ='$OPCACHE_REVALIDATE_FREQ' ist ungueltig. Erwartet Sekunden als Zahl."
    is_integer "$XDEBUG_CLIENT_PORT" \
        || die "XDEBUG_CLIENT_PORT='$XDEBUG_CLIENT_PORT' ist ungueltig. Erwartet eine Portnummer."
    is_integer "$XDEBUG_LOG_LEVEL" \
        || die "XDEBUG_LOG_LEVEL='$XDEBUG_LOG_LEVEL' ist ungueltig. Erwartet 0-10."

    [ -n "$PHP_TIMEZONE" ] || die 'PHP_TIMEZONE ist leer.'
    [ -n "$PHP_ERROR_REPORTING" ] || die 'PHP_ERROR_REPORTING ist leer.'
}

# ---------------------------------------------------------------------------
# Regeln, die sich aus den aufgeloesten Werten ergeben
# ---------------------------------------------------------------------------

xdebug_is_active() {
    [ -n "$XDEBUG_MODE" ] && [ "$XDEBUG_MODE" != 'off' ]
}

# PCOV und Xdebug schliessen sich gegenseitig aus. Diese Konfliktloesung ist der
# tragfaehige Kern des Bestands (E10) und bleibt erhalten: PCOV gewinnt, weil es
# ausdruecklich eingeschaltet wurde.
enforce_pcov_xdebug_exclusion() {
    [ "$PCOV_ENABLED" = '1' ] || return 0
    xdebug_is_active || return 0

    log_info "PCOV ist aktiv — XDEBUG_MODE wird von '$XDEBUG_MODE' auf 'off' gesetzt (PCOV und Xdebug schliessen sich aus)."
    XDEBUG_MODE='off'
}

# A10.3 — JIT-Automatik. Ohne sie schreibt der Entrypoint opcache.jit=1254 und
# xdebug.mode=debug gemeinsam in die INI; PHP schaltet JIT dann selbst ab und
# warnt bei JEDEM Aufruf (L-A). Bei phpcli war das der Default-Zustand.
#
# Diese Regel schlaegt bewusst auch einen explizit gesetzten OPCACHE_JIT: der
# Wert waere technisch wirkungslos, und ihn stehen zu lassen wuerde genau die
# Warnung zurueckbringen, die A10.3 beseitigt. Der Vorgang wird gemeldet.
enforce_jit_policy() {
    # Der Grund ist nicht "Xdebug", sondern "eine Extension uebernimmt
    # zend_execute_ex()". Das trifft auf Xdebug UND auf PCOV zu — PHP schaltet
    # JIT in beiden Faellen selbst ab und warnt bei jedem Aufruf.
    #
    # Dass PCOV dazugehoert, kostete P2 einen blinden Fleck: die JIT-Automatik
    # kannte nur Xdebug, und ausgerechnet das test-Profil (XDEBUG_MODE=off,
    # PCOV_ENABLED=1, JIT=1254) warnte damit bei JEDEM Aufruf — genau die
    # Warnung, die A10.3/L-A beseitigen soll. Aufgedeckt vom P8-Test am
    # gebauten Image (Befund B18); im Prueffall der Bibliothek war es nicht
    # sichtbar, weil dort kein PHP laeuft.
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

    log_info "$_jit_blocker ist aktiv — opcache.jit wird von '$OPCACHE_JIT' auf 'off' gesetzt. PHP wuerde JIT sonst selbst deaktivieren und bei jedem Aufruf warnen."
    OPCACHE_JIT='off'
    OPCACHE_JIT_BUFFER_SIZE='0'
}

# A10.4 — in prod ist ein aktives Xdebug ein Abbruchgrund, kein Hinweis. Damit
# ist das Fehlkonfigurations-Risiko aus REQUIREMENTS_ANALYSE.md §4.3 im Image
# selbst geschlossen, statt an einen CI-Check delegiert, der nicht existiert (L-F).
guard_production() {
    [ "$APP_ENV" = 'prod' ] || return 0
    xdebug_is_active || return 0

    die "APP_ENV=prod, aber Xdebug ist mit XDEBUG_MODE='$XDEBUG_MODE' aktiv. Das ist in Produktion nicht zulaessig (Leistung und Angriffsflaeche). Entweder XDEBUG_MODE=off setzen oder APP_ENV=dev bzw. test verwenden."
}

# ---------------------------------------------------------------------------
# Zielort der Laufzeit-INI
# ---------------------------------------------------------------------------
# Regelfall ist /home/$APP_USER/php-config, das per Symlink in conf.d haengt —
# so schreibt der Entrypoint als appuser, ohne conf.d beschreibbar zu machen
# (tragfaehiger Kern des Bestands, E10).
#
# Ist dieses Verzeichnis nicht beschreibbar, laeuft der Container mit einer im
# Image unbekannten Kennung (A4.4). Dann weicht die INI in ein temporaeres
# Verzeichnis aus, das ueber PHP_INI_SCAN_DIR eingebunden wird. Das
# Default-conf.d muss dabei ausdruecklich mit aufgefuehrt werden, sonst gingen
# die Extension-INIs verloren; unser Verzeichnis steht dahinter, damit
# 99-runtime-config.ini garantiert zuletzt laedt.
resolve_ini_dir() {
    INI_DIR="/home/$APP_USER/php-config"

    if [ -w "$INI_DIR" ]; then
        export INI_DIR
        return 0
    fi

    INI_DIR="${TMPDIR:-/tmp}/php-config"
    mkdir -p "$INI_DIR" \
        || die "Weder /home/$APP_USER/php-config noch $INI_DIR sind beschreibbar."
    export PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:$INI_DIR"
    export INI_DIR

    log_warn "/home/$APP_USER/php-config ist nicht beschreibbar (Container laeuft unter einer im Image unbekannten Kennung). Die Laufzeit-INI weicht nach $INI_DIR aus, eingebunden ueber PHP_INI_SCAN_DIR."
}

# ---------------------------------------------------------------------------
# INI-Erzeugung
# ---------------------------------------------------------------------------
# Die Datei heisst 99-runtime-config.ini und laedt damit garantiert nach allen
# Extension-INIs — insbesondere nach 00-opcache.ini, das OPcache als
# zend_extension vor Xdebug bringt.
write_runtime_ini() {
    cat > "$INI_DIR/99-runtime-config.ini" <<PHPINI
; ---------------------------------------------------------------------------
; Erzeugt beim Containerstart von entrypoint.sh — Aenderungen sind fluechtig.
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

; Xdebug — der Modus wird zusaetzlich als Umgebungsvariable exportiert, weil
; Xdebug 3 ihr Vorrang vor dieser Einstellung gibt.
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
# Einstiegspunkt
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
