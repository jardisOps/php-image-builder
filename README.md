# php-image-builder

A repository that builds Headgent's PHP runtime images: **`headgent/phpcli`** and
**`headgent/phpfpm`**, for PHP **8.3 / 8.4 / 8.5** on Alpine, for `linux/amd64`
and `linux/arm64`, from **one** source of configuration and in **one**
`docker buildx bake` run.

Both images share one `base` target, one entrypoint core and one `.env`, so no
value and no piece of shell exists twice.

| Target | Published as | Base | Purpose |
|---|---|---|---|
| `base` | — (**not** published) | `php:<ver>-fpm-alpine<alpine>` | PHP version, extensions, Composer, user, entrypoint core — described exactly once |
| `cli` | `headgent/phpcli` | `base` | workers, queue consumers, cron, Composer, CI and build contexts |
| `fpm` | `headgent/phpfpm` | `base` | php-fpm only, sidecar behind a separate web server |

**nginx is not a build target.** Instead of its own image, this repository ships
the fully parameterised server configuration as a versioned asset
(`tests/nginx/`) that runs with the **unmodified** official `nginx` image.

> **The detailed version lives in the [handbook](support/HANDBOOK.md)** — every
> target, all `.env` groups, the `APP_ENV` profiles, runtime UID/GID, the nginx
> template, the thirteen test stages and CI.

---

## Requirements

- Docker with **Buildx** (bake is required, not `docker build`)
- GNU Make
- For the full test run: a Docker daemon that allows `--privileged` containers
  (the Linux UID check starts a `docker:28-dind` host) and several gigabytes of
  free disk space
- No PHP needed on the host

## Quick start

```sh
make help          # every target with its help text
make info          # the resolved build configuration
make build         # cli + fpm for PHP_VERSION from .env, loaded locally
make test-all      # the full test run (thirteen stages)
make demo-up       # demo stack: mariadb + fpm + official nginx
```

## Usage

`make help` lists every target with its help text. The most important ones:

| Target | Effect |
|---|---|
| `make build` / `build-all` | one PHP version from `.env` / the whole matrix |
| `make bake-print` | the resolved bake definition, builds nothing |
| `make test-all` | the test run, thirteen stages — stages can be run individually |
| `make demo-up` / `demo-down` | demo stack on `http://localhost:8088` |
| `make disk-usage` | what Docker occupies and how much of it comes from this repo — **deletes nothing** |
| `make clean` / `clean-all` | clean up; `clean-system` is global and guarded by `CONFIRM=ja` |
| `make push` / `push-all` | **blocked**, see below |
| `make push-print` | the resolved push definition — same flags as `push`, but `--print`. Pushes nothing, needs no login |

A value on the `make` command line beats `.env`:

```sh
make build PHP_VERSION=8.5
make build BAKE_TARGETS=fpm            # one target only; base is pulled in automatically
make build BUILD_PLATFORM=linux/amd64  # a single platform instead of the host architecture
```

(The leading-variable form, `PHP_VERSION=8.5 make build`, does **not** work —
for a plain environment variable the included `.env` file wins.)

## Configuration

**The `.env` in the repository root is the only source of configuration** —
build arguments and runtime defaults alike, reaching `support/docker-bake.hcl`
only through the Makefile's `export`, never read directly. Full pipeline
diagram and `.env` groups: [Configuration in the
handbook](support/HANDBOOK.md#configuration).

Two things deliberately live elsewhere: the extension list in
`src/shared/php-extensions.env` (once for all targets) and the `APP_ENV` profile
table in `src/shared/entrypoint/lib-phpini.sh`. `make info` always shows what
actually applies.

No `ARG` in this repository carries a default — a missing value fails the build
visibly instead of silently building something other than `.env` declares.
Three intended hadolint warnings are the price: [No Dockerfile carries a
version default](support/HANDBOOK.md#no-dockerfile-carries-a-version-default).

## Repository layout

```
php-image-builder/
├── .env                          # the only source of configuration
├── Makefile                      # includes support/makefiles/
├── src/                          # exclusively what ends up in the image
│   ├── shared/
│   │   ├── php-extensions.env    # the extension list, once
│   │   ├── php-ini/              # static INI fragments
│   │   └── entrypoint/           # core (POSIX sh) + UID/GID + APP_ENV profiles
│   ├── base/Dockerfile
│   ├── cli/Dockerfile            # four effective lines on FROM base
│   └── fpm/                      # Dockerfile + fpm-pool.sh
├── tests/                        # eleven check scripts, runnable individually
│   ├── demo/                     # demo stack and its sample application
│   └── nginx/                    # nginx template and its defaults
├── support/
│   ├── makefiles/                # the make modules
│   ├── docker-bake.hcl           # matrix: base → cli/fpm via contexts
│   ├── hadolint.yaml
│   └── HANDBOOK.md
└── .github/workflows/ci.yml
```

A target Dockerfile contains only what follows from its purpose. For `cli` that
is four lines: `max_execution_time=0`, `STOPSIGNAL SIGTERM`, a health check on
`php`/`composer`, and the `CMD`. Everything else lives in `base`.

## Publishing is blocked

The CI's `publish` job only runs when the repository variable
`PUBLISH_ENABLED` holds exactly `true`. It currently holds `false`, so the job
is skipped. Note what that switch does **not** do: it is not limited to one PHP
version. With it on, every push to `main` that touches a build path publishes
the whole matrix. Narrowing to a single version is a property of the
`workflow_dispatch` input `php_versions`, not of the variable.
No `docker login`, no `--push`. `make push-print` resolves the exact same
command line without executing it — that is where a wrong flag surfaces, rather
than in the middle of a publish run.

The block stays until the tag strategy is approved. Nothing is currently
published under `headgent/phpcli` or `headgent/phpfpm`: the registry entries
were removed on 2026-07-26, so the **26 active references — all on
`headgent/phpcli:8.3`** — can no longer pull. Machines with a filled Docker
cache keep working; a fresh CI runner or `docker compose pull` does not.
The first push out of this repository therefore restores service, and the tag
set it writes decides what those 26 get.

## Known operating conditions

- **`make build-all` needs disk space** — bake builds all three PHP versions
  simultaneously.
- **`make test-all` requires `--privileged`** — `test-uid-linux` starts a
  `docker:28-dind` container. Without that capability the remaining twelve stages
  can still be run individually.
- **The demo stack listens on port 8088**, the test run additionally uses 18080.

The complete list is in the [handbook](support/HANDBOOK.md).

## License

See [LICENSE](LICENSE).
