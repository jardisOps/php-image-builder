#!/bin/bash
# ---------------------------------------------------------------------------
# check-uid-linux-host.sh <cli-image> [dind-image] — AK4/A4.5, letzte Haelfte
# ---------------------------------------------------------------------------
# Der Nachweis, den PLAN.md fuer P11 auf einem Linux-Runner vorsah: die
# UID/GID-Angleichung gegen einen ECHTEN BIND-MOUNT von einem ECHTEN
# Linux-Dateisystem.
#
# Warum das auf dem Entwicklungsrechner nicht direkt geht: unter Docker Desktop
# laeuft ein Bind-Mount von macOS ueber die Dateibruecke der VM, die alle
# Eigentuemer auf die Container-Kennung umschreibt. Der Linux-UID-Fehler ist
# dort prinzipiell unsichtbar — genau deshalb fiel er im Bestand nie auf.
#
# Der Ausweg ist kein Ersatz, sondern die Sache selbst: ein `docker:*-dind`-
# Container IST ein Linux-Host mit einem echten Linux-Dateisystem und einem
# eigenen Docker-Daemon. Ein Verzeichnis darin traegt echte Unix-Eigentuemer,
# und ein Bind-Mount aus diesem Dateisystem in unser Image geht durch keine
# Bruecke. Der Nachweis ist damit gleichwertig zu dem auf einem GitHub-Runner
# und in einem Punkt strenger: die Fremd-UID ist frei waehlbar (4711) statt vom
# Runner vorgegeben (1001).
#
# Abgrenzung zu den beiden anderen UID-Pruefungen:
#   check-user-alignment.sh  lib-user.sh in Isolation, ohne unser Image
#   check-uid-image.sh       echtes Image, echte Docker-NAMED-VOLUMES
#   diese Datei              echtes Image, echter BIND-MOUNT vom Linux-Host
#
# B20 gilt hier NICHT und das ist der Punkt: die Ownership-Ruecksetzung beim
# ersten Mount trifft nur leere Named Volumes. Ein Bind-Mount uebernimmt Docker
# unveraendert — deshalb prueft dieses Skript vor jedem Lauf ausdruecklich nach,
# dass die vorgegebene Eigentuemerangabe noch steht.
set -eu

IMAGE=${1:?Aufruf: check-uid-linux-host.sh <cli-image> [dind-image]}
DIND_IMAGE=${2:-docker:28-dind}

DIND=check-uid-linux-$$
PASS=0; FAIL=0

cleanup() { docker rm -f "$DIND" >/dev/null 2>&1 || true; }
trap cleanup EXIT

ok()     { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()    { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
expect() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

# Alles im Linux-Host ausfuehren.
host() { docker exec "$DIND" sh -c "$1"; }

echo ">>> UID/GID gegen einen echten Linux-Bind-Mount — $IMAGE"
echo "  Linux-Host: $DIND_IMAGE"

# ---------------------------------------------------------------------------
# Linux-Host hochfahren
# ---------------------------------------------------------------------------
# DOCKER_TLS_CERTDIR leer: der innere Daemon wird nur ueber den lokalen Socket
# angesprochen, nie ueber das Netz. Ohne diese Zeile erzeugt das Image bei jedem
# Start ein TLS-Zertifikat und lauscht auf 2376 — beides hier ohne Zweck.
docker run -d --privileged --name "$DIND" -e DOCKER_TLS_CERTDIR= "$DIND_IMAGE" >/dev/null

bereit=nein
for _ in $(seq 1 60); do
  if docker exec "$DIND" docker info >/dev/null 2>&1; then bereit=ja; break; fi
  [ "$(docker inspect -f '{{.State.Running}}' "$DIND" 2>/dev/null)" = true ] || break
  sleep 1
done
if [ "$bereit" != ja ]; then
  bad "der innere Docker-Daemon wurde nicht bereit — Abbruch"
  docker logs "$DIND" 2>&1 | tail -20
  echo; echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
  exit 1
fi
ok "Linux-Host laeuft, eigener Docker-Daemon ist bereit"

expect "es ist wirklich Linux" "$(host 'uname -s')" "Linux"

# Unser Image in den inneren Daemon bringen. Ueber save/load und nicht ueber eine
# Registry: es soll nichts nach aussen gehen (N6) und exakt dasselbe Artefakt
# geprueft werden, das lokal gebaut wurde.
docker save "$IMAGE" | docker exec -i "$DIND" docker load >/dev/null
if host "docker image inspect '$IMAGE' >/dev/null 2>&1"; then
  ok "Testimage liegt im Linux-Host (per save/load, keine Registry beteiligt)"
else
  bad "Testimage kam im Linux-Host nicht an — Abbruch"
  echo; echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
  exit 1
fi

# ---------------------------------------------------------------------------
# Ein Verzeichnis auf dem Linux-Dateisystem, mit vorgegebenem Eigentuemer
# ---------------------------------------------------------------------------
# vorbereiten legt neu an und setzt den Eigentuemer; leer = so lassen (root:root).
vorbereiten() { # <pfad> [owner]
  host "rm -rf '$1' && mkdir -p '$1'"
  if [ -n "${2:-}" ]; then
    host "chown $2 '$1'"
  fi
}

# Die Gegenprobe gegen die Fallstrick-Klasse B20: erst nachsehen, ob die
# vorgegebene Eigentuemerangabe ueberhaupt noch steht. Stuende sie nicht, pruefte
# alles Weitere einen Zustand, den niemand gesetzt hat.
owner_auf_dem_host() { host "stat -c '%u:%g' '$1'"; }

# Startet unser Image auf dem Bind-Mount — DURCH den Entrypoint, nicht daran
# vorbei (B19: --entrypoint uebergeht lib-user.sh, also genau das Gepruefte).
#
# Gemeldet wird die PROZESSKENNUNG zuerst, dann der Eigentuemer des
# Verzeichnisses. Diese Reihenfolge ist der ganze Punkt: der Verzeichnis-
# eigentuemer ist in fast allen Faellen die EINGABE des Prueffalls und aendert
# sich nicht — eine Zusicherung darauf misst nichts. Ob die Angleichung
# stattgefunden hat, sagt allein `id -u`/`id -g` des Prozesses.
#
# Belegt am 2026-07-26: eine erste Fassung dieses Skripts prueft nur den
# Verzeichniseigentuemer und meldete deshalb auch fuer das defekte
# Bestands-Image gruen (Befund B31). Reihe mit B11, B16, B19, B20, B21, B27.
probe() { # <pfad> [zusaetzliche docker-args ...]
  _p=$1; shift
  host "docker run --rm -v '$_p:/app' $* '$IMAGE' sh -c '
    touch /app/probe 2>/dev/null && w=schreibbar || w=NICHT-schreibbar
    printf \"%s %s %s\n\" \"\$(id -u):\$(id -g)\" \"\$(stat -c %u:%g /app)\" \"\$w\"
  ' 2>/dev/null"
}

# <erwartet> hat die Form "<prozess-uid:gid> <verzeichnis-uid:gid> <schreibbar>"
fall() { # <ueberschrift> <pfad> <owner|""> <erwartet>
  echo "  $1"
  vorbereiten "$2" "$3"
  expect "    Vorgabe steht auf dem Linux-Dateisystem" \
    "$(owner_auf_dem_host "$2")" "${3:-0:0}"
  expect "    Prozesskennung / Verzeichnis / Schreibrecht" "$(probe "$2")" "$4"
}

fall "A4.1 — Host-UID != 1000 (Bind-Mount, 4711:4711)" /srv/app-fremd  4711:4711 "4711:4711 4711:4711 schreibbar"
fall "A4.1/U1 — belegte Ziel-GID (20 = dialout)"        /srv/app-gid20  1234:20   "1234:20 1234:20 schreibbar"
fall "A4.2/U2 — root-eigenes Verzeichnis, leer"         /srv/app-root   ""        "1000:1000 1000:1000 schreibbar"

# Der Beleg, den nur ein Bind-Mount liefern kann: die Datei, die der Container
# geschrieben hat, liegt danach auf dem LINUX-DATEISYSTEM und traegt dort die
# angeglichene Kennung. Bei einem Named Volume waere das nicht dasselbe, und
# ueber die macOS-Dateibruecke waere die Angabe umgeschrieben.
expect "    geschriebene Datei traegt auf dem Host die angeglichene Kennung" \
  "$(host "stat -c '%u:%g' /srv/app-fremd/probe")" "4711:4711"

# A4.2, zweite Haelfte: ein root-eigenes Verzeichnis mit Inhalt. Uebertragen wird
# bewusst nur das Verzeichnis selbst — ein rekursives chown wuerde auf einem
# absichtlich root-eigenen Baum fremde Daten umschreiben.
echo "  A4.2 — root-eigenes Verzeichnis MIT Inhalt"
vorbereiten /srv/app-voll ""
host "install -m 644 /dev/null /srv/app-voll/fremd.txt"
expect "    Prozesskennung / Verzeichnis / Schreibrecht" \
  "$(probe /srv/app-voll)" "1000:1000 1000:1000 schreibbar"
expect "    vorhandener Inhalt bleibt root" \
  "$(host "stat -c '%u:%g' /srv/app-voll/fremd.txt")" "0:0"

# A4.4 — von aussen vorgegebene Kennung: keine Anpassung.
echo "  A4.4 — Start mit --user 4711:4711"
vorbereiten /srv/app-user 4711:4711
expect "    laeuft unveraendert unter der vorgegebenen Kennung" \
  "$(probe /srv/app-user --user 4711:4711)" "4711:4711 4711:4711 schreibbar"

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
