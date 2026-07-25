#!/bin/sh
# ---------------------------------------------------------------------------
# entrypoint.sh — gemeinsamer Entrypoint-Kern aller PHP-Targets
# ---------------------------------------------------------------------------
# Existiert genau einmal (A3.1) und wird von cli, fpm und frankenphp unveraendert
# verwendet. In den Bestands-Repos war dieser Code zu rund 80 % dupliziert.
#
# Ablauf:
#   1. Laufzeit-Benutzer an den Eigentuemer von /app angleichen   (lib-user.sh)
#   2. PHP-Konfiguration aus APP_ENV-Profil + Overrides erzeugen  (lib-phpini.sh)
#   3. Target-Ergaenzungen ausfuehren                             (entrypoint.d/)
#   4. Rechte abgeben und die Nutzlast starten
#
# Target-spezifische Anteile — etwa die FPM-Pool-Erzeugung — liegen als eigene
# Skripte in /usr/local/lib/entrypoint.d/ und werden hier nur eingesammelt
# (A3.2). Dieser Kern kennt kein einziges Target namentlich.
#
# POSIX-sh, nicht bash: derselbe Kern soll auch in einem Image ohne bash laufen
# (FrankenPHP-Alpine). Geprueft wird mit shellcheck im dash-Dialekt.
# ---------------------------------------------------------------------------
set -eu

ENTRYPOINT_LIB_DIR='/usr/local/lib/entrypoint'
ENTRYPOINT_EXT_DIR='/usr/local/lib/entrypoint.d'

# ---------------------------------------------------------------------------
# Meldungen
# ---------------------------------------------------------------------------
# Alles geht nach stderr, damit die Nutzlast-Ausgabe auf stdout unberuehrt
# bleibt — wichtig, weil `docker run ... php -r ...` maschinell gelesen wird.
log_info() { printf 'entrypoint: %s\n' "$1" >&2; }
log_warn() { printf 'entrypoint: WARNUNG: %s\n' "$1" >&2; }

# Bricht sichtbar ab. Kein Aufrufer unterdrueckt diesen Pfad — genau daran
# scheiterte die bisherige UID-Behandlung (U1).
die() {
    printf 'entrypoint: FEHLER: %s\n' "$1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Bibliotheken
# ---------------------------------------------------------------------------
# shellcheck source=./lib-user.sh
. "$ENTRYPOINT_LIB_DIR/lib-user.sh"
# shellcheck source=./lib-phpini.sh
. "$ENTRYPOINT_LIB_DIR/lib-phpini.sh"

# ---------------------------------------------------------------------------
# Target-Ergaenzungen
# ---------------------------------------------------------------------------
# Jede *.sh in entrypoint.d wird gesourct und darf die bereits aufgeloesten
# Werte sowie INI_DIR, APP_USER und die Log-Funktionen nutzen. Reihenfolge ist
# die lexikalische Sortierung.
run_target_extensions() {
    [ -d "$ENTRYPOINT_EXT_DIR" ] || return 0

    for _ep_ext in "$ENTRYPOINT_EXT_DIR"/*.sh; do
        [ -f "$_ep_ext" ] || continue
        log_info "Target-Ergaenzung: $(basename "$_ep_ext")"
        # shellcheck source=/dev/null
        . "$_ep_ext"
    done
}

# ---------------------------------------------------------------------------
# Uebergabe an die Nutzlast
# ---------------------------------------------------------------------------
# Der Container startet als root nur fuer die Einmal-Initialisierung und gibt die
# Rechte hier ab. `exec` ersetzt die Shell, damit die Nutzlast PID 1 wird und
# Signale unmittelbar erhaelt.
#
# Ein leeres RUNTIME_USER heisst: kein Wechsel, die Nutzlast laeuft als root und
# regelt den Rechtewechsel selbst. Genau das braucht php-fpm — siehe unten.
#
# ENTFERNT (P5, 2026-07-25): hier stand ein `chown` auf /proc/self/fd/{1,2},
# uebernommen aus beiden Bestands-Entrypoints samt der Begruendung, er sei fuer
# php-fpm zwingend. Diese Begruendung ist falsch, der Griff ist WIRKUNGSLOS:
# /proc/self/fd/2 ist ein Symlink auf eine anonyme Pipe (pipe:[...]), und das
# pipefs nimmt die Eigentumsaenderung nicht an. `chown` meldet dabei Exit 0 —
# es gibt also nicht einmal einen Fehler, den das danebenstehende `|| true`
# verschlucken koennte. Dieselbe Fehlerklasse "still wirkungslos" wie U1, D16
# und B1.
#
# Belegt am 2026-07-25: headgent/phpfpm:8.2, :8.3 und :8.4 starten deshalb ALLE
# nicht ("failed to open error_log (/proc/self/fd/2): Permission denied"), mit
# und ohne TTY, mit und ohne gemountetes /app. Auch `php-fpm --force-stderr`
# hilft nicht, weil FPM das error_log schon beim Config-Post-Processing oeffnet.
# Das fpm-Target loest das ueber N4-Variante (b): FPM startet als root und
# wechselt seine Worker selbst per `user =` in der Pool-Config — das von PHP
# vorgesehene Betriebsmodell, das auch das offizielle php:X-fpm-Image nutzt.
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
# Orchestrierung — keine eigene Logik, nur Verkettung
# ---------------------------------------------------------------------------
main() {
    align_runtime_user
    apply_php_configuration
    run_target_extensions
    handover "$@"
}

main "$@"
