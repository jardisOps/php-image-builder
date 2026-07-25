#!/bin/bash
# ---------------------------------------------------------------------------
# check-app-env.sh <image> — die APP_ENV-Profile wirken im echten Image (AK13)
# ---------------------------------------------------------------------------
# Abgrenzung zu check-phpini.sh: jenes prueft lib-phpini.sh in Isolation, mit 33
# Faellen und ohne Container — dort liegt die Logikabdeckung. Hier wird nur
# geprueft, was NUR das gebaute Image zeigen kann: dass die aufgeloesten Werte
# tatsaechlich als PHP-Einstellung ankommen. Beides zu wiederholen waere
# Doppelpflege; die 33 Faelle werden hier bewusst nicht nachgebaut.
set -eu

IMAGE=${1:?Aufruf: check-app-env.sh <image>}
PASS=0; FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

# Fuehrt PHP-Code IM Container aus — durch den Entrypoint hindurch, nicht daran
# vorbei. `--entrypoint php` waere hier der klassische Messfehler: dann liefe
# lib-phpini.sh nie, es gaebe keine Laufzeit-INI, und der Test laese die
# Defaults der Extensions statt unserer Profile. Der Entrypoint protokolliert
# nach stderr, deshalb genuegt 2>/dev/null fuer einen sauberen Rueckgabewert.
php_in() { # <php-code> [env ...]
  local code=$1; shift
  local args=()
  for e in "$@"; do args+=(-e "$e"); done
  docker run --rm "${args[@]}" "$IMAGE" php -r "$code" 2>/dev/null
}

# xdebug.mode ist ueber ini_get NICHT ablesbar: Xdebug meldet bei mode=off einen
# Leerstring. Massgeblich ist die Umgebungsvariable, der Xdebug 3 ohnehin
# Vorrang gibt (A10.5) — und die ist zugleich das, was der Entrypoint setzt.
xdebug_mode() { php_in 'echo getenv("XDEBUG_MODE");' "$@"; }
ini()         { local n=$1; shift; php_in "echo ini_get('$n');" "$@"; }

echo ">>> APP_ENV-Profile in $IMAGE"

# ini_get('display_errors') liefert "1" fuer On und einen LEERSTRING fuer Off —
# eine PHP-Eigenart, keine Fehlkonfiguration. error_reporting kommt numerisch:
# 32767 = E_ALL, 24575 = E_ALL & ~E_DEPRECATED.
echo "  AK13 — dev"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=dev)" "debug"
check "pcov.enabled"    "$(ini pcov.enabled    APP_ENV=dev)" "0"
check "display_errors"  "$(ini display_errors  APP_ENV=dev)" "1"
check "error_reporting" "$(ini error_reporting APP_ENV=dev)" "32767"

echo "  AK13 — test"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=test)" "off"
check "pcov.enabled"    "$(ini pcov.enabled    APP_ENV=test)" "1"

echo "  AK13 — prod"
check "xdebug.mode"     "$(xdebug_mode         APP_ENV=prod)" "off"
check "display_errors"  "$(ini display_errors  APP_ENV=prod)" ""
check "error_reporting" "$(ini error_reporting APP_ENV=prod)" "24575"

# A10.2 — eine explizit gesetzte Einzelvariable schlaegt das Profil. Das ist die
# Zusicherung, dass die heutige Feinsteuerung erhalten bleibt.
echo "  A10.2 — Override schlaegt das Profil"
check "xdebug.mode in dev"  "$(xdebug_mode APP_ENV=dev XDEBUG_MODE=off)"               "off"
check "display_errors"      "$(ini display_errors APP_ENV=prod PHP_DISPLAY_ERRORS=On)" "1"

# A10.5 — Xdebug 3 liest die Umgebungsvariable und gibt ihr Vorrang vor der INI.
# Sie muss deshalb exportiert sein, nicht nur gesetzt.
echo "  A10.5 — XDEBUG_MODE ist exportiert"
check "im Kindprozess" \
  "$(docker run --rm -e APP_ENV=test "$IMAGE" printenv XDEBUG_MODE 2>/dev/null)" "off"

# AK14/L-F — aktives Xdebug in Produktion bricht sichtbar ab, statt still zu
# laufen. Der Abbruch IST das erwartete Verhalten.
echo "  AK14/L-F — prod mit aktivem Xdebug bricht ab"
if OUT=$(docker run --rm -e APP_ENV=prod -e XDEBUG_MODE=debug "$IMAGE" php -r 'exit(0);' 2>&1); then
  bad "kein Abbruch — der Container lief durch"
else
  case "$OUT" in
    *rod*|*[Xx]debug*) ok "Abbruch mit Begruendung" ;;
    *)                 bad "Abbruch, aber ohne erkennbare Begruendung: $OUT" ;;
  esac
fi

# A10.7/L-E — ein Tippfehler landet nicht ungeprueft in der INI.
echo "  A10.7/L-E — ungueltiger Wert bricht ab"
if docker run --rm -e APP_ENV=dev -e XDEBUG_MODE=degug "$IMAGE" php -r 'exit(0);' >/dev/null 2>&1; then
  bad "ein ungueltiger XDEBUG_MODE wurde angenommen"
else
  ok "ungueltiger XDEBUG_MODE abgewiesen"
fi
if docker run --rm -e APP_ENV=produktion "$IMAGE" php -r 'exit(0);' >/dev/null 2>&1; then
  bad "ein ungueltiges APP_ENV wurde angenommen"
else
  ok "ungueltiges APP_ENV abgewiesen"
fi

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
