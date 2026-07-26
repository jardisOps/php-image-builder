#!/bin/bash
# ---------------------------------------------------------------------------
# check-uid-image.sh <cli-image> — UID/GID-Angleichung am gebauten Image (AK4)
# ---------------------------------------------------------------------------
# Abgrenzung zu check-user-alignment.sh: jenes prueft lib-user.sh in Isolation
# (27 Faelle, in alpine:3.23, mit im Container erzeugten Verzeichnissen). Hier
# laeuft dieselbe Logik im ECHTEN Image gegen ECHTE Docker-Volumes.
#
# Warum das auch auf macOS traegt: ein Named Volume liegt in der Linux-VM und
# traegt dort echte Unix-Eigentuemer. Ein Helfer-Container setzt sie, unser
# Image sieht sie wie auf einem Linux-Host. Damit sind alle DREI von PLAN.md
# geforderten Bedingungen hier pruefbar:
#
#   Host-UID != 1000     Volume gehoert 1234:1234
#   belegte Ziel-GID     Volume gehoert 1234:20 — GID 20 ist in Alpine "dialout"
#                        und damit belegt. Genau hier scheiterte der Bestand
#                        still (U1): groupmod schlug fehl, `2>/dev/null || true`
#                        verschluckte es, der Fehler tauchte spaeter als
#                        unerklaerliches "Permission denied" auf.
#   root-eigenes Volume  frisches Volume, wie Docker es anlegt (U2)
#
# NICHT abgedeckt: der Bind-Mount von einem echten Linux-Host. Den fuehrt seit
# P11 check-uid-linux-host.sh in einem docker-in-docker-Linux-Host — dort ist
# die Quelle der Eigentuemerangabe eine andere, der Mechanismus derselbe.
# Beide Skripte bleiben nebeneinander: dieses laeuft ohne --privileged und
# faengt denselben Fehler frueher.
set -eu

IMAGE=${1:?Aufruf: check-uid-image.sh <cli-image>}
VOLUME=check-uid-$$
PASS=0; FAIL=0

cleanup() { docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

# Legt das Volume neu an und setzt den Eigentuemer. Leer = so lassen, wie Docker
# es anlegt (root:root).
# Die Markierungsdatei ist NICHT Beiwerk, sondern noetig: mountet man ein LEERES
# Named Volume auf einen Pfad, den das Image kennt, kopiert Docker den
# Image-Inhalt samt Eigentuemern hinein — und setzt damit genau die Ownership
# zurueck, die dieser Test vorgeben will. Ein nicht-leeres Volume laesst Docker
# unangetastet. Ohne diesen Griff meldete der Test dreimal 1000:1000 und haette
# eine Anpassung "belegt", die gar nicht stattgefunden hat.
prepare_volume() { # [owner]
  docker volume rm -f "$VOLUME" >/dev/null 2>&1 || true
  docker volume create "$VOLUME" >/dev/null
  docker run --rm -v "$VOLUME:/app" alpine:3.23 \
    sh -c 'touch /app/.keep'"${1:+ && chown -R $1 /app}"
}

# Startet das Image auf dem Volume und meldet Eigentuemer und Schreibbarkeit.
# DURCH den Entrypoint, nicht daran vorbei: `--entrypoint sh` haette lib-user.sh
# uebersprungen — also genau die Angleichung, die hier geprueft wird.
probe() { # [extra docker-args ...]
  docker run --rm -v "$VOLUME:/app" "$@" "$IMAGE" sh -c '
    touch /app/probe 2>/dev/null && w=schreibbar || w=NICHT-schreibbar
    printf "%s %s\n" "$(stat -c %u:%g /app)" "$w"
  ' 2>/dev/null
}

expect() { # <name> <ist> <soll>
  if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi
}

echo ">>> UID/GID-Angleichung in $IMAGE"

echo "  A4.1 — Host-UID != 1000"
prepare_volume 1234:1234
expect "/app gehoert danach dem Laufzeitbenutzer und ist beschreibbar" \
  "$(probe)" "1234:1234 schreibbar"

echo "  A4.1/U1 — belegte Ziel-GID (20 = dialout)"
prepare_volume 1234:20
expect "Gruppe wird wiederverwendet statt still zu scheitern" \
  "$(probe)" "1234:20 schreibbar"

echo "  A4.2/U2 — frisches Named Volume (root:root)"
prepare_volume
expect "root-eigenes Volume wird behandelt, nicht uebersprungen" \
  "$(probe)" "1000:1000 schreibbar"

# A4.4 — von aussen vorgegebene Kennung: keine Anpassung, kein
# Privilegienwechsel, und das Image funktioniert trotzdem mit einer im Image
# unbekannten UID.
echo "  A4.4 — Start mit --user 4711:4711"
prepare_volume 4711:4711
expect "laeuft unveraendert unter der vorgegebenen Kennung" \
  "$(probe --user 4711:4711)" "4711:4711 schreibbar"

if docker run --rm --user 4711:4711 -e APP_ENV=test --entrypoint php "$IMAGE" \
     -r 'exit(0);' >/dev/null 2>&1; then
  ok "PHP laeuft unter unbekannter UID (INI weicht ins Ausweichverzeichnis aus)"
else
  bad "PHP scheitert unter unbekannter UID"
fi

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
