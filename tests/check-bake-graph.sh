#!/bin/bash
# ---------------------------------------------------------------------------
# check-bake-graph.sh — the resolved bake definition
# ---------------------------------------------------------------------------
# Checks `docker buildx bake --print`, not the file text: only the resolved
# definition shows what would actually be built. Builds nothing and needs no
# image, so it runs in seconds and fails fast.
#
# Proves three guarantees that were otherwise only shown once by hand: every
# published target pulls `base` for its own PHP version via contexts, so a
# change to base rebuilds ALL dependent targets; base itself is never
# published (not in the default group, carries no tag); one version string
# drives every tag (:<ver> and :<ver>-<date> per target, :latest exactly once
# per image).
#
# Called without arguments; the definition comes from `make bake-print` so
# the values take the same path as a real build (Makefile -> environment ->
# bake).
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

PASS=0; FAIL=0
ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

echo ">>> Bake definition (resolved, no build)"

DEF=$(cd "$REPO_ROOT" && make bake-print 2>/dev/null)

# jq would be the obvious choice but isn't installed everywhere and would add
# a new prerequisite for the test run. python3 is on every runner and every
# development machine for this project.
ask() { # <python expression over d>
  echo "$DEF" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print($1)
"
}

# --- base is a precursor, not an artifact -----------------------------------
check "default group builds exactly cli and fpm" \
      "$(ask "','.join(sorted(d['group']['default']['targets']))")" "cli,fpm"

check "no base target carries a tag" \
      "$(ask "sum(len(t.get('tags',[])) for n,t in d['target'].items() if n.startswith('base-'))")" "0"

# --- every published target hangs off ITS OWN base --------------------------
# The core guarantee. If a target fell out of this chain, a base change
# would no longer rebuild it — and nobody would notice.
errors=$(ask "';'.join(
    n for n,t in d['target'].items()
    if (n.startswith('cli-') or n.startswith('fpm-'))
    and t.get('contexts',{}).get('base') != 'target:base-' + n.split('-',1)[1]
)")
count=$(ask "sum(1 for n in d['target'] if n.startswith('cli-') or n.startswith('fpm-'))")
if [ -z "$errors" ]; then
  ok "all $count published targets pull target:base-<own-version>"
else
  bad "these targets don't hang off their own base: $errors"
fi

# Control check for the line above: it's only worth anything if targets were
# actually checked. With an empty matrix the list would be empty and the
# guarantee would still report green — measuring nothing.
if [ "$count" -ge 2 ]; then
  ok "targets were really checked ($count)"
else
  bad "the matrix is empty or incomplete ($count targets) — the guarantee above measures nothing"
fi

# --- one version string drives every tag ------------------------------------
# Per target exactly :<ver> and :<ver>-<date>; :latest comes in addition and
# exactly once per image name.
errors=$(ask "';'.join(
    n for n,t in d['target'].items()
    if (n.startswith('cli-') or n.startswith('fpm-'))
    and len([x for x in t.get('tags',[]) if not x.endswith(':latest')]) != 2
)")
if [ -z "$errors" ]; then
  ok "every published target carries :<ver> AND :<ver>-<date>"
else
  bad "these targets don't carry exactly two version tags: $errors"
fi

check "exactly one :latest per published image" \
      "$(ask "len([x for t in d['target'].values() for x in t.get('tags',[]) if x.endswith(':latest')])")" "2"

# All date tags of one run must carry the same date — otherwise a project
# couldn't pin phpcli and phpfpm as a combination.
#
# set(...) and NOT the brace set notation: the expression goes through the
# shell, which would tear {a,b} apart as brace expansion before python ever
# sees it (measured once — the first run fell apart into three syntax
# errors).
date_tags="[x.rsplit(':',1)[1] for t in d['target'].values() for x in t.get('tags',[])]"
check "there are date tags to check at all" \
      "$(ask "sum(1 for tag in $date_tags if '-' in tag)")" "6"
check "all date tags of one run carry the same date" \
      "$(ask "len(set(tag.rsplit('-',1)[1] for tag in $date_tags if '-' in tag))")" "1"

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
