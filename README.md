# php-image-builder

A repository that builds Headgent's PHP runtime images: **`headgent/phpcli`** and
**`headgent/phpfpm`**, for PHP **8.3 / 8.4 / 8.5** on Alpine, for `linux/amd64`
and `linux/arm64`, from **one** source of configuration and in **one**
`docker buildx bake` run.

It replaces the two separate repositories `jardisOps/phpcli` and
`jardisOps/phpfpm`, whose entrypoints were roughly 80 % identical code and whose
configuration had diverged in sixteen places. The published image names stay the
same — consumers do not have to change anything.

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
> template, the thirteen test stages, CI, and the migration from the previous
> images.

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

The environment beats `.env`:

```sh
PHP_VERSION=8.5 make build
make build BAKE_TARGETS=fpm            # one target only; base is pulled in automatically
make build BUILD_PLATFORM=linux/amd64  # a single platform instead of the host architecture
```

## Configuration

**The `.env` in the repository root is the only source.** It feeds build
arguments and runtime defaults alike; no value is maintained in two places. A
value always travels the same path:

```
.env → Makefile (export) → support/docker-bake.hcl (build-arg) → Dockerfile (ARG → ENV) → entrypoint (INI)
```

`support/docker-bake.hcl` does **not** read `.env` itself — every value reaches
it through the environment exported by the Makefile. That is why
`PHP_VERSION=8.5 make build` reliably works; in the previous repositories such a
call had no effect.

Two things deliberately live elsewhere: the extension list in
`src/shared/php-extensions.env` (once for all targets) and the `APP_ENV` profile
table in `src/shared/entrypoint/lib-phpini.sh`. `make info` always shows what
actually applies.

**No `ARG` in this repository carries a default.** If a value is missing, the
build fails visibly instead of quietly building something other than what `.env`
declares. The price is three `InvalidDefaultArgInFrom` warnings from hadolint on
every build — they are intended and are **not** an error.

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

This repository has **no GitHub remote**, has never been pushed, and the CI's
`publish` job only runs when the repository variable `PUBLISH_ENABLED` is set to
`true` — it does not exist. No `docker login`, no `--push`, no CI trigger.
`make push` and `make push-all` are written and have never been run.

The block stays until the tag strategy is approved. `headgent/phpcli` is a
published series with consumers — counted: **26 active references, all on
`headgent/phpcli:8.3`**. The first push out of this repository must not swap that
tag underneath running projects.

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
