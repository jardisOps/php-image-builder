# ---------------------------------------------------------------------------
# cli — published as headgent/phpcli
# ---------------------------------------------------------------------------
# Purpose: worker, queue consumer, cron, CI, and build context.
#
# Everything substantive lives in base: PHP version, extensions, Composer,
# runtime libraries, appuser, entrypoint core, INI load order, WORKDIR. Here
# there is only what follows from the purpose — the three values an image can
# only carry once, and which must be opposite between worker and request
# operation (max_execution_time, STOPSIGNAL, HEALTHCHECK). This is exactly
# why cli and fpm remain two separate artifacts.
#
# `FROM base` is resolved by support/docker-bake.hcl via
# contexts = { base = "target:base" } — base itself is not published.
#
# DL3006 ("always tag the version explicitly") is a false positive here:
# `base` is a named build context, not a registry image — there is nothing to
# tag. hadolint doesn't know the bake concept. The ignore stays inline rather
# than in support/hadolint.yaml, so a real untagged FROM in a future
# Dockerfile still gets flagged.
# ---------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM base

# The one required value base does not set: it follows the process type, not
# the environment. A long-running worker or queue consumer must not have a
# time limit — 0 means unlimited. The key carries the _CLI suffix so .env can
# maintain both values side by side; in the image it is set back to the plain
# PHP setting name.
ARG PHP_MAX_EXECUTION_TIME_CLI
ENV PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME_CLI}

# Corrects the SIGQUIT inherited from the fpm base image. SIGQUIT is FPM's
# signal for a graceful shutdown; a PHP worker does not recognize it as such
# and would be hard-killed instead. SIGTERM is the signal pcntl-based worker
# loops listen for.
STOPSIGNAL SIGTERM

# Checks what defines this image: a working PHP interpreter and a usable
# Composer. Deliberately not the fpm target's FastCGI ping — no FPM listens
# here, and the container would be permanently unhealthy.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD sh -c "php --version >/dev/null && composer --version >/dev/null"

# Inherited and deliberately left as is: EXPOSE 9000 from the fpm base image.
# Docker has no "unexpose"; the line is pure metadata and opens nothing.
CMD ["php","--version"]
