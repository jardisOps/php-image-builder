#!/bin/bash
# Prueft lib-phpini.sh gegen die A10-Anforderungen, ohne Container.
#
# Der Pfad wird aus dem Ort DIESER Datei abgeleitet, nicht absolut gepflegt: der
# vorherige Wert zeigte auf ein Verzeichnis auf genau einem Rechner und haette
# den Test auf jedem anderen System und auf dem CI-Runner (P11) scheitern
# lassen. Befund B17.
REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LIB="$REPO_ROOT/src/shared/entrypoint/lib-phpini.sh"
[ -r "$LIB" ] || { echo "❌ lib-phpini.sh nicht gefunden unter $LIB" >&2; exit 2; }
PASS=0; FAIL=0

# Ruft apply_php_configuration in einer Subshell mit gesetzter Umgebung auf.
# Gibt die aufgeloesten Werte als KEY=VALUE aus, oder "DIE: <meldung>".
# SC2016 ist hier der Zweck, kein Versehen: der Rumpf unten ist Quelltext fuer
# die Subshell und darf NICHT vorher expandiert werden — sonst setzte die
# aufrufende Shell ihre eigenen Werte ein, statt die der Bibliothek zu messen.
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

# SC2001: die Ersetzung setzt JEDER Zeile einen Einzug voran. Das leistet
# ${var//muster/ersatz} nicht — es kennt keinen Zeilenanfang.
# shellcheck disable=SC2001
check() { # name, output, expected-substring
  if grep -qF "$3" <<<"$2"; then echo "  ✅ $1"; PASS=$((PASS+1))
  else echo "  ❌ $1 — erwartet: '$3'"; echo "$2" | sed 's/^/       /'; FAIL=$((FAIL+1)); fi
}

# Werte, die ein Image mitbringt (profilunabhaengig)
IMG=(PHP_MEMORY_LIMIT=512M PHP_MAX_EXECUTION_TIME=0 PHP_TIMEZONE=UTC PHP_LOG_ERRORS=On
     APCU_SHM_SIZE=64M OPCACHE_MEMORY_CONSUMPTION=128 OPCACHE_MAX_ACCELERATED_FILES=4000
     OPCACHE_JIT_BUFFER_SIZE=128M XDEBUG_START_WITH_REQUEST=yes
     XDEBUG_CLIENT_HOST=host.docker.internal XDEBUG_CLIENT_PORT=9003
     XDEBUG_LOG_LEVEL=0 XDEBUG_IDEKEY=PHPSTORM)

echo "AK13 — APP_ENV=dev setzt ein konsistentes Profil"
O=$(run_case "${IMG[@]}" APP_ENV=dev)
check "xdebug.mode=debug"            "$O" "XDEBUG_MODE=debug"
check "pcov aus"                     "$O" "PCOV_ENABLED=0"
check "validate_timestamps=1 (L-C)"  "$O" "OPCACHE_VALIDATE_TIMESTAMPS=1"
check "display_errors=On (L-D)"      "$O" "PHP_DISPLAY_ERRORS=On"
check "error_reporting ohne E_STRICT (L-G)" "$O" "PHP_ERROR_REPORTING=E_ALL"

echo "AK14 — JIT-Automatik bei aktivem Xdebug (L-A)"
check "jit=off statt 1254"           "$O" "OPCACHE_JIT=off"
check "jit_buffer_size=0"            "$O" "OPCACHE_JIT_BUFFER_SIZE=0"

echo "A10.5 — XDEBUG_MODE wird exportiert"
check "im environment"               "$O" "XDEBUG_EXPORTED=1"

echo "INI-Qualitaet"
check "keine leere Direktive"        "$O" "INI_EMPTY_DIRECTIVES=0"

echo "AK13 — APP_ENV=test (L-B: kein Abschalten im Testaufruf mehr noetig)"
O=$(run_case "${IMG[@]}" APP_ENV=test)
check "xdebug aus"                   "$O" "XDEBUG_MODE=off"
check "pcov an"                      "$O" "PCOV_ENABLED=1"
# GEAENDERT 2026-07-25 (Befund B18): erwartet war hier bis P8 OPCACHE_JIT=1254.
# Das war falsch — PCOV uebernimmt zend_execute_ex() genau wie Xdebug, PHP
# schaltet JIT deshalb selbst ab UND warnt bei jedem Aufruf. Im test-Profil ist
# PCOV an, also warnte ausgerechnet jeder Testlauf. Die JIT-Automatik (A10.3)
# deckt seither beide Extensions ab; die Erwartung folgt dem korrigierten
# Verhalten, nicht umgekehrt.
check "jit aus, weil PCOV aktiv (B18)" "$O" "OPCACHE_JIT=off"
check "jit_buffer_size=0"              "$O" "OPCACHE_JIT_BUFFER_SIZE=0"

echo "AK13 — APP_ENV=prod"
O=$(run_case "${IMG[@]}" APP_ENV=prod)
check "xdebug aus"                   "$O" "XDEBUG_MODE=off"
check "validate_timestamps=0"        "$O" "OPCACHE_VALIDATE_TIMESTAMPS=0"
check "display_errors=Off"           "$O" "PHP_DISPLAY_ERRORS=Off"
check "error_reporting ~E_DEPRECATED" "$O" "PHP_ERROR_REPORTING=E_ALL & ~E_DEPRECATED"
check "jit aktiv"                    "$O" "OPCACHE_JIT=1254"

echo "AK14 — prod + aktives Xdebug bricht sichtbar ab (L-F)"
O=$(run_case "${IMG[@]}" APP_ENV=prod XDEBUG_MODE=debug)
check "Abbruch"                      "$O" "DIE: APP_ENV=prod, aber Xdebug"

echo "A10.2 — explizite Einzelvariable schlaegt das Profil"
O=$(run_case "${IMG[@]}" APP_ENV=prod OPCACHE_VALIDATE_TIMESTAMPS=1)
check "Override gewinnt gegen prod"  "$O" "OPCACHE_VALIDATE_TIMESTAMPS=1"
O=$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=off)
check "xdebug off in dev moeglich"   "$O" "XDEBUG_MODE=off"
check "dann ist JIT nutzbar"         "$O" "OPCACHE_JIT=1254"
O=$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=trace,coverage)
check "Mehrfachmodus erlaubt"        "$O" "XDEBUG_MODE=trace,coverage"

echo "E10 — PCOV/Xdebug-Konfliktloesung bleibt erhalten"
O=$(run_case "${IMG[@]}" APP_ENV=dev PCOV_ENABLED=1)
check "xdebug weicht pcov"           "$O" "XDEBUG_MODE=off"
check "pcov bleibt an"               "$O" "PCOV_ENABLED=1"

echo "A10.7 / L-E — ungueltige Werte brechen klar ab"
check "APP_ENV"      "$(run_case "${IMG[@]}" APP_ENV=produktion)"                  "DIE: APP_ENV='produktion' ist ungueltig"
check "XDEBUG_MODE"  "$(run_case "${IMG[@]}" APP_ENV=dev XDEBUG_MODE=degug)"       "DIE: XDEBUG_MODE enthaelt den unbekannten Modus 'degug'"
check "PCOV_ENABLED" "$(run_case "${IMG[@]}" APP_ENV=dev PCOV_ENABLED=yes)"        "DIE: PCOV_ENABLED='yes' ist ungueltig"
check "OPCACHE_JIT"  "$(run_case "${IMG[@]}" APP_ENV=dev OPCACHE_JIT=schnell)"     "DIE: OPCACHE_JIT='schnell' ist ungueltig"
check "memory_limit" "$(run_case "${IMG[@]/PHP_MEMORY_LIMIT=512M/PHP_MEMORY_LIMIT=viel}" APP_ENV=dev)" "DIE: PHP_MEMORY_LIMIT='viel' ist ungueltig"
check "display_errors" "$(run_case "${IMG[@]}" APP_ENV=dev PHP_DISPLAY_ERRORS=ja)" "DIE: PHP_DISPLAY_ERRORS='ja' ist ungueltig"
check "client_port"  "$(run_case "${IMG[@]/XDEBUG_CLIENT_PORT=9003/XDEBUG_CLIENT_PORT=neunkommadrei}" APP_ENV=dev)" "DIE: XDEBUG_CLIENT_PORT='neunkommadrei' ist ungueltig"

echo "Freigabe 2026-07-25 — kein Notwert: fehlender Image-Wert bricht ab"
# PHP_TIMEZONE aus der Image-Umgebung entfernen
IMG_OHNE_TZ=(); for v in "${IMG[@]}"; do [ "$v" = "PHP_TIMEZONE=UTC" ] || IMG_OHNE_TZ+=("$v"); done
check "fehlender Wert"  "$(run_case "${IMG_OHNE_TZ[@]}" APP_ENV=dev)" "PHP_TIMEZONE: ist nicht gesetzt"

echo "A4.4 — INI weicht aus, wenn /home/... nicht beschreibbar ist"
O=$(run_case "${IMG[@]}" APP_ENV=dev)
check "Ausweichverzeichnis genutzt"  "$O" "php-config"

echo
echo "════════════════════════════════════"
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ $FAIL -eq 0 ] || exit 1
