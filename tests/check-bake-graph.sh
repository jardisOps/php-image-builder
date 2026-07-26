#!/bin/bash
# ---------------------------------------------------------------------------
# check-bake-graph.sh — die aufgeloeste Bake-Definition (A1.2/A1.3/A9.2, AK10)
# ---------------------------------------------------------------------------
# Prueft `docker buildx bake --print`, nicht den Dateitext: erst die aufgeloeste
# Definition zeigt, was wirklich gebaut wuerde. Baut nichts und braucht kein
# Image — laeuft deshalb in Sekunden und faellt frueh durch.
#
# Belegt drei Zusagen, die sonst nur in P6 einmal von Hand gezeigt wurden:
#
#   A9.2/AK10  jedes publizierte Ziel zieht `base` seiner eigenen PHP-Version
#              ueber contexts. Damit baut eine Aenderung an base ALLE
#              abhaengigen Targets neu — es gibt keinen zweiten Weg an base
#              vorbei.
#   A1.2       base wird nicht publiziert: es steht nicht in der Default-Gruppe
#              und traegt keinen Tag.
#   A1.3       EIN Versionsstring treibt alle Tags: je Ziel :<ver> und
#              :<ver>-<datum>, und :latest genau einmal je Image.
#
# Aufruf ohne Argumente; die Definition kommt aus `make bake-print`, damit die
# Werte denselben Weg nehmen wie beim echten Build (Makefile -> Umgebung ->
# bake, Befund B1).
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

PASS=0; FAIL=0
ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — erwartet '$3', ist '$2'"; fi; }

echo ">>> Bake-Definition (aufgeloest, ohne Build)"

DEF=$(cd "$REPO_ROOT" && make bake-print 2>/dev/null)

# jq waere die naheliegende Wahl, ist aber nicht ueberall installiert und waere
# eine neue Voraussetzung fuer den Prueflauf. python3 liegt auf jedem Runner und
# auf jedem Entwicklungsrechner dieses Projekts.
frage() { # <python-ausdruck ueber d>
  echo "$DEF" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print($1)
"
}

# --- A1.2: base ist Vorstufe, kein Artefakt --------------------------------
check "Default-Gruppe baut genau cli und fpm" \
      "$(frage "','.join(sorted(d['group']['default']['targets']))")" "cli,fpm"

check "kein base-Ziel traegt einen Tag" \
      "$(frage "sum(len(t.get('tags',[])) for n,t in d['target'].items() if n.startswith('base-'))")" "0"

# --- A9.2/AK10: jedes publizierte Ziel haengt an SEINEM base ----------------
# Der Kern der Zusage. Faellt ein Ziel aus dieser Kette, wuerde eine
# base-Aenderung es nicht mehr neu bauen — und niemand saehe es.
fehler=$(frage "';'.join(
    n for n,t in d['target'].items()
    if (n.startswith('cli-') or n.startswith('fpm-'))
    and t.get('contexts',{}).get('base') != 'target:base-' + n.split('-',1)[1]
)")
zahl=$(frage "sum(1 for n in d['target'] if n.startswith('cli-') or n.startswith('fpm-'))")
if [ -z "$fehler" ]; then
  ok "alle $zahl publizierten Ziele ziehen target:base-<eigene-version> (A9.2)"
else
  bad "diese Ziele haengen nicht an ihrem base: $fehler"
fi

# Gegenprobe zur Zeile darueber: sie ist nur etwas wert, wenn ueberhaupt Ziele
# geprueft wurden. Bei einer leeren Matrix waere die Liste leer und die
# Zusicherung trotzdem gruen — die Fallstrick-Klasse B11/B19/B21.
if [ "$zahl" -ge 2 ]; then
  ok "es wurden wirklich Ziele geprueft ($zahl)"
else
  bad "die Matrix ist leer oder unvollstaendig ($zahl Ziele) — die Zusicherung darueber misst nichts"
fi

# --- A1.3: ein Versionsstring treibt alle Tags ------------------------------
# Je Ziel genau :<ver> und :<ver>-<datum>; :latest kommt zusaetzlich und genau
# einmal je Image-Namen.
fehler=$(frage "';'.join(
    n for n,t in d['target'].items()
    if (n.startswith('cli-') or n.startswith('fpm-'))
    and len([x for x in t.get('tags',[]) if not x.endswith(':latest')]) != 2
)")
if [ -z "$fehler" ]; then
  ok "jedes publizierte Ziel traegt :<ver> UND :<ver>-<datum> (A1.3)"
else
  bad "diese Ziele tragen nicht genau zwei Versions-Tags: $fehler"
fi

check "genau ein :latest je publiziertem Image" \
      "$(frage "len([x for t in d['target'].values() for x in t.get('tags',[]) if x.endswith(':latest')])")" "2"

# Alle Datums-Tags eines Laufs muessen dasselbe Datum tragen — sonst koennte ein
# Projekt phpcli und phpfpm nicht als Kombination pinnen (A1.3).
#
# set(...) und NICHT die Mengen-Schreibweise mit geschweiften Klammern: der
# Ausdruck geht durch die Shell, und die haette {a,b} als Klammer-Expansion
# auseinandergenommen, bevor python ihn je sieht (gemessen 2026-07-26 — der
# erste Lauf zerfiel in drei Syntaxfehler).
datums_tags="[x.rsplit(':',1)[1] for t in d['target'].values() for x in t.get('tags',[])]"
check "es gibt ueberhaupt Datums-Tags zu pruefen" \
      "$(frage "sum(1 for tag in $datums_tags if '-' in tag)")" "6"
check "alle Datums-Tags eines Laufs tragen dasselbe Datum" \
      "$(frage "len(set(tag.rsplit('-',1)[1] for tag in $datums_tags if '-' in tag))")" "1"

echo
echo "  bestanden: $PASS   fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
