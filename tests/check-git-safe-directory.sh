#!/bin/bash
# ---------------------------------------------------------------------------
# check-git-safe-directory.sh <image> — git trusts the APP_ROOT mount
# ---------------------------------------------------------------------------
# A bind mount can appear root-owned while appuser runs git/Composer, which
# makes git fail with "dubious ownership". Checked in two ways: the system
# config lists APP_ROOT, and git actually works on a root-owned repository
# when called as appuser (the control proves the failure is real otherwise).
set -eu

IMAGE=${1:?Usage: check-git-safe-directory.sh <image>}
PASS=0; FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo ">>> git safe.directory in $IMAGE"

# Entrypoint bypassed on purpose: only the image's own git config is measured.
LISTED=$(docker run --rm --entrypoint sh "$IMAGE" -c 'git config --system --get-all safe.directory') || LISTED=''
if printf '%s\n' "$LISTED" | grep -qx '/app'; then
  ok "system safe.directory lists /app"
else
  bad "system safe.directory lacks /app — got '$LISTED'"
fi

# Functional: root-owned repo at /app, git run as appuser (uid 1000).
SCRIPT='git init -q /app && chown -R 0:0 /app && su-exec appuser git -C /app status --porcelain >/dev/null'
if docker run --rm --entrypoint sh "$IMAGE" -c "$SCRIPT" 2>/dev/null; then
  ok "appuser runs git in a root-owned /app"
else
  bad "git as appuser fails in a root-owned /app"
fi

# Control: for a path NOT listed, the same situation must still be refused.
CONTROL='git init -q /tmp/other && chown -R 0:0 /tmp/other && ! su-exec appuser git -C /tmp/other status >/dev/null 2>&1'
if docker run --rm --entrypoint sh "$IMAGE" -c "$CONTROL"; then
  ok "control: an unlisted root-owned repo is still refused"
else
  bad "control: an unlisted root-owned repo was NOT refused — the check measures nothing"
fi

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
