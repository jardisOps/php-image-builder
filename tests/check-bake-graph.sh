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

# --no-print-directory: GNU Make 4.x passes -w down to a sub-make, which then
# writes "make: Entering directory ..." to STDOUT, right in front of the JSON.
# Make 3.81 (macOS default) does not, so the failure only appears on Linux.
#
# stderr is deliberately NOT discarded: a `2>/dev/null` here once hid the
# reason for exactly that failure and left three bare JSON tracebacks behind.
DEF=$(cd "$REPO_ROOT" && make --no-print-directory bake-print)

# Everything below parses $DEF anew, eight times over. Without this guard, any
# non-JSON output produces a wall of identical tracebacks and "got ''" lines,
# none of which names the cause.
case "$DEF" in
  '{'*) ;;
  *)    bad "'make bake-print' returned no JSON. First line: $(printf '%s\n' "$DEF" | head -1)"
        echo; echo "  passed: $PASS   failed: $FAIL"; exit 1 ;;
esac

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

# --- the push invocation, resolved but not executed ---------------------------
# Everything above checks `bake-print`, which uses neither the platform flag nor
# the attestation flags. The push line therefore went unchecked until it ran for
# real — and it failed on `--attest`, a `buildx build` flag that `bake` does not
# have, before a single layer was built. `push-print` carries the identical
# flags with --print, so the same mistake now fails here instead of mid-publish.
echo
echo ">>> Push invocation (resolved, pushes nothing)"

# stderr stays on the terminal and is NOT captured: bake writes its progress
# there, and folding it into the JSON would make every run look broken. The
# reason for a failure therefore remains readable above this line.
if PUSH_DEF=$(cd "$REPO_ROOT" && make --no-print-directory push-print); then
  case "$PUSH_DEF" in
    '{'*) ok "the push flags parse" ;;
    *)    bad "'make push-print' returned no JSON. First line: $(printf '%s\n' "$PUSH_DEF" | head -1)" ;;
  esac
else
  bad "'make push-print' failed — the message stands above this line"
fi

case "$PUSH_DEF" in
  '{'*)
    # sorted(...) and NOT the brace set notation, same reason as above: the
    # expression passes through the shell, which tears {a,b} apart as brace
    # expansion. Both sides then come back empty and compare equal — the check
    # reports green while measuring nothing. Cost one round to relearn.
    pask() { echo "$PUSH_DEF" | python3 -c "
import json,sys
d = json.load(sys.stdin)
pub = sorted(n for n in d['target'] if not n.startswith('base-'))
print($1)
"; }

    expected=$(pask "len(pub)")
    case "$expected" in
      '' | *[!0-9]* | 0) bad "could not count the published targets (got '$expected') — the two checks below would measure nothing" ;;
      *)
        ok "published targets counted ($expected)"

        check "every published target is attested (sbom + provenance)" \
              "$(pask "sum(1 for n in pub if sorted(a['type'] for a in d['target'][n].get('attest',[])) == sorted(['provenance','sbom']))")" \
              "$expected"

        check "every published target builds both architectures" \
              "$(pask "sum(1 for n in pub if sorted(p.strip() for s in d['target'][n].get('platforms',[]) for p in s.split(',')) == sorted(['linux/amd64','linux/arm64']))")" \
              "$expected"
        ;;
    esac
    ;;
esac

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
