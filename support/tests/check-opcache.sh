#!/bin/bash
# ---------------------------------------------------------------------------
# check-opcache.sh <fpm-image> — OPcache, JIT und die Revalidierung (AK15)
# ---------------------------------------------------------------------------
# Zwei Teile:
#
#   1. Statisch: OPcache geladen und aktiv, JIT an, wenn Xdebug aus ist, und
#      JIT aus, wenn Xdebug an ist (AK14/L-A). Der Bestand prueft nur die erste
#      Haelfte — und musste dafuer in JEDEM Aufruf XDEBUG_MODE=off setzen (L-B).
#      Hier reicht APP_ENV=test bzw. prod: das Profil erledigt das.
#
#   2. AK15: im dev-Profil bemerkt FPM Code-Aenderungen ohne Neustart, im
#      prod-Profil nicht. Das ist der Nachweis fuer L-C, bisher nur von Hand
#      erbracht (P5).
#
# BEFUND B11 IST HIER VERBINDLICH. OPcache cacht per Default keine Datei, die in
# den letzten 2 Sekunden geaendert wurde (opcache.file_update_protection). Ein
# erster AK15-Versuch in P5 schien deshalb zu zeigen, dass auch prod Aenderungen
# bemerkt — tatsaechlich war schlicht NIE etwas gecacht (num_cached_scripts=0).
# Der Test wartet die Frist deshalb ab UND prueft num_cached_scripts/hits mit:
# ohne diese zweite Haelfte misst er nichts und meldet trotzdem gruen.
#
# Warum FPM und nicht CLI: ein CLI-Aufruf ist ein eigener Prozess mit eigenem
# SHM. Der Unterschied zwischen validate_timestamps 0 und 1 ist ueber getrennte
# Prozesse gar nicht beobachtbar. Nur der FPM-Master haelt den Cache.
set -eu

IMAGE=${1:?Aufruf: check-opcache.sh <fpm-image>}
CONTAINER=check-opcache-$$
PASS=0; FAIL=0

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

# ---------------------------------------------------------------------------
# Teil 1 — statische Einstellungen je Profil
# ---------------------------------------------------------------------------
# DURCH den Entrypoint messen, nicht daran vorbei: mit `--entrypoint php` liefe
# lib-phpini.sh nie und der Test laese die Image-Defaults statt der Profile.
# Der Entrypoint protokolliert nach stderr, daher 2>/dev/null.
php_in() { # <app_env> <php-code>
  docker run --rm -e APP_ENV="$1" "$IMAGE" php -r "$2" 2>/dev/null
}
ini() { php_in "$1" "echo ini_get('$2');"; }

# Ob JIT wirklich laeuft, sagt nur die Laufzeit — ini_get('opcache.jit') meldet
# je nach Abschaltweg 'off', '0' oder einen Leerstring.
jit_enabled() { php_in "$1" 'echo opcache_get_status(false)["jit"]["enabled"] ? "ja" : "nein";'; }

echo ">>> OPcache und JIT in $IMAGE"

check "opcache.enable (prod)"      "$(ini prod opcache.enable)"      "1"
check "opcache.enable_cli (prod)"  "$(ini prod opcache.enable_cli)"  "1"
check "validate_timestamps (prod)" "$(ini prod opcache.validate_timestamps)" "0"
check "validate_timestamps (dev)"  "$(ini dev  opcache.validate_timestamps)" "1"

# JIT laeuft genau dann, wenn keine Extension zend_execute_ex() uebernimmt.
check "JIT laeuft in prod"                    "$(jit_enabled prod)" "ja"
check "JIT aus in dev (Xdebug aktiv, L-A)"    "$(jit_enabled dev)"  "nein"
check "JIT aus in test (PCOV aktiv, B18)"     "$(jit_enabled test)" "nein"

# AK14 — die Warnung selbst darf in KEINEM Profil erscheinen. Genau hier fiel
# B18 auf: test warnte bei jedem Aufruf, weil die JIT-Automatik nur Xdebug
# kannte und nicht PCOV.
for profile in dev test prod; do
  if docker run --rm -e APP_ENV="$profile" "$IMAGE" php -r 'exit(0);' 2>&1 | grep -qi 'JIT is incompatible'; then
    bad "AK14 — JIT-Warnung im Profil $profile"
  else
    ok "AK14 — keine JIT-Warnung im Profil $profile"
  fi
done

# ---------------------------------------------------------------------------
# Teil 2 — AK15: bemerkt FPM Code-Aenderungen?
# ---------------------------------------------------------------------------
# Ablauf je Profil: Skript schreiben, B11-Frist abwarten, zweimal abrufen (das
# fuellt den Cache), Skript aendern, Frist erneut abwarten, erneut abrufen.
UPDATE_PROTECTION_S=3   # opcache.file_update_protection ist 2 s — mit Reserve

fcgi() { # <pfad> -> Rumpf der Antwort
  docker exec \
    -e SCRIPT_NAME="$1" -e SCRIPT_FILENAME="$1" -e REQUEST_METHOD=GET \
    "$CONTAINER" cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | tr -d '\r' | tail -1
}

write_script() { # <fassung>
  docker exec "$CONTAINER" sh -c "cat > /app/ak15.php <<'PHP'
<?php
\$s = opcache_get_status(false);
echo 'FASSUNG-$1',
     ' cached=', \$s['opcache_statistics']['num_cached_scripts'],
     ' hits=',   \$s['opcache_statistics']['hits'];
PHP"
}

run_ak15() { # <app_env> <erwartet-nach-aenderung>
  local profile=$1 expect=$2 r1 r2 r3
  cleanup
  docker run -d --name "$CONTAINER" -e APP_ENV="$profile" "$IMAGE" >/dev/null

  for _ in $(seq 1 30); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" = healthy ] && break
    sleep 1
  done

  write_script 1
  sleep "$UPDATE_PROTECTION_S"
  r1=$(fcgi /app/ak15.php)
  r2=$(fcgi /app/ak15.php)

  write_script 2
  sleep "$UPDATE_PROTECTION_S"
  r3=$(fcgi /app/ak15.php)

  echo "     $profile: 1='$r1'  2='$r2'  nach Aenderung='$r3'"

  # B11, erste Haelfte: ohne gefuellten Cache misst der Vergleich nichts.
  case "$r2" in
    *"cached=0"*|"") bad "$profile — es war nichts gecacht, der Test misst nichts (B11)" ; return ;;
  esac
  case "$r2" in
    *"hits=0"*) bad "$profile — keine Cache-Treffer, der Test misst nichts (B11)" ; return ;;
  esac
  ok "$profile — Cache ist gefuellt und trifft (B11-Gegenprobe)"

  case "$r3" in
    "FASSUNG-$expect"*) ok "$profile — liefert nach der Aenderung FASSUNG-$expect" ;;
    *)                  bad "$profile — erwartet FASSUNG-$expect, bekam '$r3'" ;;
  esac
}

echo ">>> AK15 — Revalidierung im laufenden FPM"
run_ak15 dev  2   # dev bemerkt die Aenderung   (validate_timestamps=1)
run_ak15 prod 1   # prod bemerkt sie nicht      (validate_timestamps=0)

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
