#!/bin/sh
# Laeuft IN alpine:3.23 und prueft lib-user.sh gegen U1-U3 und A4.1-A4.4.
# /lib-user.sh ist eingehaengt.
set -u
PASS=0; FAIL=0

apk add --no-cache shadow su-exec >/dev/null 2>&1 || { echo "apk fehlgeschlagen"; exit 2; }

APP_USER=appuser
APP_ROOT=/app
export APP_USER APP_ROOT

# Ausgangszustand wie im Image: appuser 1000:1000
addgroup -g 1000 appuser
adduser -G appuser -u 1000 -D appuser
mkdir -p /home/appuser/php-config /run/php-fpm
chown -R appuser:appuser /home/appuser /run/php-fpm

check() { # name, ist, soll
  if [ "$2" = "$3" ]; then echo "  OK   $1"; PASS=$((PASS+1))
  else echo "  FAIL $1 — ist='$2' soll='$3'"; FAIL=$((FAIL+1)); fi
}
contains() { # name, haystack, needle
  case "$2" in *"$3"*) echo "  OK   $1"; PASS=$((PASS+1)) ;;
               *) echo "  FAIL $1 — '$3' nicht in Ausgabe:"; echo "$2" | sed 's/^/         /'; FAIL=$((FAIL+1)) ;;
  esac
}

# Ruft align_runtime_user in einer Subshell auf und gibt Ergebnis + Meldungen aus.
align() {
  ( log_info() { printf 'INFO %s\n' "$1"; }
    log_warn() { printf 'WARN %s\n' "$1"; }
    die()      { printf 'DIE %s\n'  "$1"; exit 1; }
    . /lib-user.sh
    align_runtime_user || exit 1
    printf 'RESULT uid=%s gid=%s runtime_user=%s\n' \
      "$(id -u "$APP_USER")" "$(id -g "$APP_USER")" "$RUNTIME_USER"
  ) 2>&1
}

reset_ids() {
  usermod  -u 1000 appuser 2>/dev/null
  groupmod -g 1000 appuser 2>/dev/null
  usermod  -g 1000 appuser 2>/dev/null
  chown -R 1000:1000 /home/appuser /run/php-fpm
  rm -rf /app; mkdir -p /app
}

echo "=== Fall 1: /app gehoert 1234:1234 (beide IDs frei) — Normalfall ==="
reset_ids; chown 1234:1234 /app
O=$(align)
contains "IDs angeglichen" "$O" "RESULT uid=1234 gid=1234 runtime_user=appuser"
contains "A4.3: Eigentum nachgezogen" "$O" "Eigentum nachgezogen"
check    "U3: /home/appuser gehoert neuer UID" "$(stat -c '%u:%g' /home/appuser)" "1234:1234"
check    "U3: APP_OWNED_PATHS unberuehrt ohne Angabe" "$(stat -c '%u:%g' /run/php-fpm)" "1000:1000"

echo "=== Fall 1b: mit APP_OWNED_PATHS=/run/php-fpm (fpm-Target, A3.2/A4.3) ==="
reset_ids; chown 1234:1234 /app
O=$(APP_OWNED_PATHS=/run/php-fpm align)
check "U3: /run/php-fpm nachgezogen" "$(stat -c '%u:%g' /run/php-fpm)" "1234:1234"

echo "=== Fall 2: /app gehoert 1234:20 — GID 20 ist von 'dialout' belegt (U1) ==="
reset_ids; chown 1234:20 /app
O=$(align)
contains "U1: kein stilles Verschlucken, Gruppe wird wiederverwendet" "$O" "GID 20 ist von Gruppe 'dialout' belegt"
contains "IDs angeglichen"  "$O" "RESULT uid=1234 gid=20"
check    "appuser ist in GID 20" "$(id -g appuser)" "20"
check    "U3: /home/appuser auf 1234:20" "$(stat -c '%u:%g' /home/appuser)" "1234:20"

echo "=== Fall 2b: /app gehoert 1234:100 — GID 100 ist von 'users' belegt (U1) ==="
reset_ids; chown 1234:100 /app
O=$(align)
contains "U1: Gruppe 'users' wiederverwendet" "$O" "GID 100 ist von Gruppe 'users' belegt"
check    "appuser ist in GID 100" "$(id -g appuser)" "100"

echo "=== Fall 3: /app gehoert 0:0 — frisches Named Volume (U2) ==="
reset_ids; chown 0:0 /app
O=$(align)
contains "U2: Fall wird behandelt, nicht uebersprungen" "$O" "gehoerte root und ist leer"
check    "/app gehoert jetzt appuser" "$(stat -c '%u:%g' /app)" "1000:1000"
contains "laeuft als appuser" "$O" "runtime_user=appuser"

echo "=== Fall 3b: /app gehoert 0:0 und ist NICHT leer ==="
reset_ids; chown 0:0 /app; touch /app/root-datei; chown 0:0 /app/root-datei
O=$(align)
contains "sichtbare Warnung statt stiller Uebernahme" "$O" "WARN /app gehoerte root und ist nicht leer"
check    "Verzeichnis uebertragen" "$(stat -c '%u:%g' /app)" "1000:1000"
check    "Inhalt bewusst NICHT rekursiv geaendert" "$(stat -c '%u:%g' /app/root-datei)" "0:0"

echo "=== Fall 4: Ziel-UID belegt — 'bin' hat UID 1 (A4.1 Wiederverwendung) ==="
reset_ids; chown 1:1 /app
O=$(align)
contains "sichtbarer Hinweis"  "$O" "UID 1 ist von Benutzer 'bin' belegt"
contains "laeuft numerisch unter der Ziel-Kennung" "$O" "runtime_user=1:1"
check    "appuser NICHT umnummeriert" "$(id -u appuser)" "1000"

echo "=== Fall 5: Container von aussen mit --user gestartet (A4.4) ==="
reset_ids; chown 1234:1234 /app
O=$(su-exec 4711:4711 sh -c '
  log_info() { printf "INFO %s\n" "$1"; }
  log_warn() { printf "WARN %s\n" "$1"; }
  die()      { printf "DIE %s\n"  "$1"; exit 1; }
  . /lib-user.sh
  align_runtime_user
  printf "RESULT runtime_user=[%s]\n" "$RUNTIME_USER"' 2>&1)
contains "keine Anpassung"        "$O" "von aussen vorgegeben"
contains "kein Privilegienwechsel" "$O" "RESULT runtime_user=[]"
check    "appuser unveraendert"   "$(id -u appuser)" "1000"

echo "=== Fall 6: /app existiert nicht ==="
reset_ids; rm -rf /app
O=$(align)
contains "kein Fehler" "$O" "existiert nicht"
contains "laeuft als appuser" "$O" "runtime_user=appuser"

echo "=== Fall 7: /app gehoert schon appuser — keine Aktion ==="
reset_ids; mkdir -p /app; chown 1000:1000 /app
O=$(align)
contains "kein chown noetig" "$O" "runtime_user=appuser"
check "keine Nachziehmeldung" "$(echo "$O" | grep -c 'Eigentum nachgezogen')" "0"

echo
echo "===================================="
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
