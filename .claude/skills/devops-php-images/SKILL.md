---
name: devops-php-images
description: Headgent's published PHP runtime images from devops/php-image-builder — headgent/phpcli (workers, cron, Composer, CI), headgent/phpfpm (fpm sidecar behind a web server) and headgent/phpweb (fpm+nginx combined, s6-supervised, the base for baked deploy images), PHP 8.3/8.4/8.5 on Alpine, amd64+arm64. Use when choosing or configuring a runtime image, wiring APP_ENV profiles, tuning the FPM pool via ENV, pinning image versions, or deciding sidecar vs. combined deploy image. TRIGGER: headgent/phpcli, headgent/phpfpm, headgent/phpweb, php-image-builder, APP_ENV profile, Xdebug im Container, FPM pool, image tag pinning, deploy image.
---

# Headgent PHP runtime images (devops/php-image-builder)

Source repo: `/Users/Rolf/Development/headgent/devops/php-image-builder`
([jardisOps/php-image-builder](https://github.com/jardisOps/php-image-builder)).
Full reference: its `README.md` and `support/HANDBOOK.md`. This skill is the
WAS view — what the images can do for a project.

## The three published series

| Image | Base | Use it for |
|---|---|---|
| `headgent/phpcli` | shared `base` | workers, queue consumers, cron, Composer, CI jobs. `max_execution_time=0`, STOPSIGNAL SIGTERM |
| `headgent/phpfpm` | shared `base` | php-fpm only, sidecar behind nginx/Traefik. FastCGI healthcheck on `/ping`, pool generated from ENV |
| `headgent/phpweb` | `fpm` | fpm **and** nginx in ONE image, s6-supervised — the base for baked deploy images (`FROM headgent/phpweb` + project code). Healthcheck proves the whole nginx→fpm chain; a dead process takes the container down. Decision: `jardis/claude/wissensbasis/deploy-image-kombiniert-phpweb.md` |

PHP 8.3 / 8.4 / 8.5 on Alpine, `linux/amd64` + `linux/arm64`. Tags per series:
`:<ver>` (floating), `:<ver>-<date>` (immutable — pin THIS in projects that need
reproducibility; all images of one run share the date, so combinations pin
cleanly), `:latest` (highest PHP version). `phpweb` is built and tested but not
yet published.

## What every image does at container start

- **APP_ENV switch** (`dev` | `test` | `prod`): one variable sets a consistent
  profile of Xdebug, PCOV, OPcache, JIT and error display. Any explicitly set
  variable beats the profile (empty override slots in the project `.env`).
- **UID/GID auto-alignment:** the entrypoint aligns the container user with the
  owner of `/app`, so bind mounts work without chown rituals.
- **ENV-driven PHP config:** memory limit, timezone, error logging, APCu,
  OPcache sizing — all runtime ENV, no INI file editing.
- **FPM pool from ENV** (fpm/web): `FPM_PM*` variables generate the pool at
  start; `/ping`→pong and `/status` are always on.

## nginx: one template, two consumption modes

The parameterised vhost template ships in `src/shared/nginx/` (template +
`nginx-defaults.env`). Sidecar mode mounts it into the **unmodified** official
nginx image (envsubst does the rest — this is what jardis-app-template does);
`phpweb` bakes and renders the same template internally with
`FASTCGI_UPSTREAM=127.0.0.1`. There is deliberately no standalone
`headgent/nginx` image.

## Extending

Runtime needs are solved in THIS repo, never worked around in consuming
projects (their house rule: no Dockerfile in the app template). Extensions land
in `src/shared/php-extensions.env`; target-specific start logic goes into
`/usr/local/lib/entrypoint.d/`. Publishing is gated: repository variable
`PUBLISH_ENABLED` plus schedule/manual trigger — a commit never publishes.
