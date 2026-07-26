#!/bin/bash
# ---------------------------------------------------------------------------
# check-oci-labels.sh <image> <expected-version> — OCI labels
# ---------------------------------------------------------------------------
# Checked against the BUILT image, not the Dockerfile: the four labels live
# only in src/base/Dockerfile and must arrive in cli and fpm via `FROM base`.
# That inheritance is exactly the assumption behind skipping double
# maintenance — if it breaks, only this check would notice.
#
# The revision is determined INDEPENDENTLY (`git rev-parse HEAD` in this
# script), not read from the same make variable that put it into the image.
# Otherwise the test would check an assignment against itself and would
# report green even if both sides were wrong together.
set -eu

IMAGE=${1:?Usage: check-oci-labels.sh <image> <expected-version>}
EXPECTED_VERSION=${2:?Usage: check-oci-labels.sh <image> <expected-version>}

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

PASS=0; FAIL=0
ok()    { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()   { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 — expected '$3', got '$2'"; fi; }

label() { # <label name>
  docker inspect -f "{{index .Config.Labels \"$1\"}}" "$IMAGE"
}

echo ">>> OCI labels — $IMAGE"

# Control check up front: an unassigned label returns the empty string. This
# establishes that the non-empty values below really come from the image and
# that `docker inspect` isn't just returning something regardless — otherwise
# every assertion below would be worthless.
#
# `<no value>` would be the other conceivable answer from the Go template;
# this Docker returns the empty string (as measured). The test follows the
# observed behavior, not the expectation.
check "control: an unassigned label returns empty" \
      "$(label org.opencontainers.image.no-such-label)" ""

# No regression: the LABEL block sits next to `maintainer`, not in its place.
if [ -n "$(label maintainer)" ]; then
  ok "maintainer is still set ($(label maintainer))"
else
  bad "maintainer has disappeared — the new LABEL block displaced it"
fi

# source — the target address. Checked for shape, not exact text: the actual
# value comes from GITHUB_ORG/GITHUB_REPO in the .env and would be a second
# maintenance point here.
src=$(label org.opencontainers.image.source)
if echo "$src" | grep -qE '^https://[a-zA-Z0-9./_-]+$'; then
  ok "source is an https URL ($src)"
else
  bad "source is not a usable URL — is '$src'"
fi

# version — must name the immutable tag the artifact carries (<php>-<date>).
# The expected value comes from the caller, from the same derivation that
# also builds the tag.
check "version names the immutable tag" \
      "$(label org.opencontainers.image.version)" "$EXPECTED_VERSION"

# revision — determined independently, see file header.
rev_erwartet=$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo unknown)
rev_image=$(label org.opencontainers.image.revision)
check "revision matches the working tree" "$rev_image" "$rev_erwartet"
if [ -z "$rev_image" ] || [ "$rev_image" = unknown ]; then
  bad "revision is empty or 'unknown' — not a real commit hash"
else
  ok "revision is a real commit hash, not a placeholder"
fi

# created — RFC 3339 in UTC, as required by the OCI spec.
created=$(label org.opencontainers.image.created)
if echo "$created" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "created is an RFC 3339 timestamp in UTC ($created)"
else
  bad "created is not an RFC 3339 timestamp — is '$created'"
fi

echo
echo "  passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
