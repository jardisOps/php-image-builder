#!/bin/bash
# ---------------------------------------------------------------------------
# check-oci-labels.sh <image> <erwartete-version> — OCI-Labels (A7.4/H4, AK8)
# ---------------------------------------------------------------------------
# Geprueft wird am GEBAUTEN Image, nicht am Dockerfile: die vier Labels stehen
# allein in src/base/Dockerfile und muessen ueber `FROM base` in cli und fpm
# ankommen. Genau diese Vererbung ist die Annahme, die den Verzicht auf
# Doppelpflege traegt — wird sie falsch, faellt es nur hier auf.
#
# Die Revision wird UNABHAENGIG ermittelt (`git rev-parse HEAD` in diesem
# Skript), nicht aus derselben Make-Variablen gelesen, die sie ins Image
# gebracht hat. Sonst pruefte der Test eine Zuweisung gegen sich selbst und
# meldete auch dann gruen, wenn beide Seiten gemeinsam falsch waeren — die
# Fallstrick-Klasse B11/B19/B21.
set -eu

IMAGE=${1:?Aufruf: check-oci-labels.sh <image> <erwartete-version>}
ERWARTETE_VERSION=${2:?Aufruf: check-oci-labels.sh <image> <erwartete-version>}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

PASS=0; FAIL=0
ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

label() { # <label-name>
  docker inspect -f "{{index .Config.Labels \"$1\"}}" "$IMAGE"
}

echo ">>> OCI-Labels — $IMAGE"

# Kontrolle vorweg: ein nicht vergebenes Label liefert den Leerstring. Damit
# steht fest, dass die nicht-leeren Werte unten wirklich aus dem Image kommen
# und `docker inspect` nicht ohnehin irgendetwas zurueckgibt — sonst waeren
# alle Zusicherungen darunter wertlos.
#
# `<no value>` waere die andere denkbare Antwort des Go-Templates; dieses Docker
# gibt den Leerstring (gemessen 2026-07-26). Der Test folgt dem gemessenen
# Verhalten und nicht der Erwartung.
check "Kontrolle: unvergebenes Label liefert leer" \
      "$(label org.opencontainers.image.gibt-es-nicht)" ""

# Kein Regress: der LABEL-Block aus P11 steht neben `maintainer`, nicht an
# seiner Stelle.
if [ -n "$(label maintainer)" ]; then
  ok "maintainer weiterhin gesetzt ($(label maintainer))"
else
  bad "maintainer ist verschwunden — der neue LABEL-Block hat ihn verdraengt"
fi

# source — die Zieladresse aus E8. Geprueft wird die Form, nicht der Text: der
# konkrete Wert kommt aus GITHUB_ORG/GITHUB_REPO der .env und waere hier eine
# Zweitpflege (A2.1).
src=$(label org.opencontainers.image.source)
if echo "$src" | grep -qE '^https://[a-zA-Z0-9./_-]+$'; then
  ok "source ist eine https-URL ($src)"
else
  bad "source ist keine brauchbare URL — ist '$src'"
fi

# version — muss den unveraenderlichen Tag benennen, den das Artefakt traegt
# (A1.3: <php>-<datum>). Der erwartete Wert kommt vom Aufrufer aus derselben
# Ableitung, die auch den Tag bildet.
check "version benennt den unveraenderlichen Tag" \
      "$(label org.opencontainers.image.version)" "$ERWARTETE_VERSION"

# revision — unabhaengig ermittelt, siehe Dateikopf.
rev_erwartet=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo unknown)
rev_image=$(label org.opencontainers.image.revision)
check "revision deckt sich mit dem Arbeitsbaum" "$rev_image" "$rev_erwartet"
if [ -z "$rev_image" ] || [ "$rev_image" = unknown ]; then
  bad "revision ist leer oder 'unknown' — kein echter Commit-Hash"
else
  ok "revision ist ein echter Commit-Hash, kein Platzhalter"
fi

# created — RFC 3339 in UTC, wie es die OCI-Spezifikation verlangt.
created=$(label org.opencontainers.image.created)
if echo "$created" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "created ist ein RFC-3339-Zeitstempel in UTC ($created)"
else
  bad "created ist kein RFC-3339-Zeitstempel — ist '$created'"
fi

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
