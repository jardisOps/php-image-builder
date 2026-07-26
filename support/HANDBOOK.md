# Handbook — php-image-builder

The detailed companion to the [README](../README.md): every target, every
configuration group, the runtime mechanics, the test run, and the operating
conditions.

- [Usage](#usage)
- [Configuration](#configuration)
- [`APP_ENV` — one switch for the environment](#app_env--one-switch-for-the-environment)
- [Runtime UID/GID](#runtime-uidgid)
- [nginx template instead of an nginx image](#nginx-template-instead-of-an-nginx-image)
- [Demo stack](#demo-stack)
- [The test run](#the-test-run)
- [Cleaning up](#cleaning-up)
- [CI and publishing](#ci-and-publishing)
- [Operating conditions and known quirks](#operating-conditions-and-known-quirks)
- [Migrating from the previous images](#migrating-from-the-previous-images)

---

## Usage

A root `Makefile` includes the modules from `support/makefiles/`. Every target
carries its own help text; `make help` reads them out.

### Building

| Target | Effect |
|---|---|
| `make build` | `cli` + `fpm` for the single `PHP_VERSION` from `.env`, `--load` into the local daemon |
| `make build-all` | the same for the **entire** matrix (8.3 / 8.4 / 8.5) in one run |
| `make bake-print` | the resolved bake definition, builds nothing |
| `make buildx-builder-create` | create or activate the multiarch builder |
| `make builder-reset` | delete the builder and create it again |
| `make build-cache-delete` | discard all cached layers (`buildx prune -a`) |
| `make init` | points the git remote at `GITHUB_ORG`/`GITHUB_REPO` from `.env` — **never run**, see [CI and publishing](#ci-and-publishing) |

Useful overrides — the environment beats `.env`:

```sh
PHP_VERSION=8.5 make build
make build BAKE_TARGETS=fpm            # one target only; base is pulled in automatically
make build BUILD_PLATFORM=linux/amd64  # a single platform instead of the host architecture
make build CACHE_BACKEND=none          # auto | gha | registry | local | none
```

### Publishing

| Target | Effect |
|---|---|
| `make push` | multi-arch build **and** push for one PHP version, with SBOM and provenance attestation |
| `make push-all` | the same for the whole matrix |

> **Both targets are written but have never been executed.** The first push is
> the only operation in this repository with outside effect and is explicitly
> blocked — see [CI and publishing](#ci-and-publishing).

### Testing

`make test-all` bundles everything; the stages can be run individually
(→ [The test run](#the-test-run)).

### Demo stack

| Target | Effect |
|---|---|
| `make demo-up` | start the stack and wait until it is healthy |
| `make demo-down` | remove containers, network, and volumes |
| `make demo-logs` | follow the logs |
| `make demo-config` | the resolved stack definition, starts nothing |

### Cleaning up

| Target | Effect |
|---|---|
| `make disk-usage` | shows what Docker occupies and how much comes from this repo — **deletes nothing** |
| `make clean` | the common case: demo leftovers, test images, dangling layers |
| `make clean-test-images` | only the test images of the test run, all versions |
| `make clean-images` | the locally built `headgent/*` images, all versions |
| `make clean-dangling` | dangling layers (`<none>`) |
| `make clean-cache` | empty the buildx cache |
| `make clean-demo` | containers, network, and volumes of the demo stack |
| `make clean-all` | everything from this repo: `clean` plus `headgent/*` plus cache |
| `make clean-system` | **global**, requires `CONFIRM=ja` — see [Cleaning up](#cleaning-up) |

### SSH keys

`make ssh-generate-ed25519`, `ssh-generate-rsa`, `ssh-show-keys`, `ssh-add-key`,
`ssh-start-agent` — interactive wrappers around `ssh-keygen` and `ssh-add`, taken
over unchanged from the previous repositories. They have nothing to do with
building images and only exist here because they existed there too.

---

## Configuration

**The `.env` in the repository root is the only source.** It feeds build
arguments and runtime defaults alike; no value is maintained in two places.

A value always travels the same path:

```
.env  →  Makefile (export)  →  support/docker-bake.hcl (build-arg)  →  Dockerfile (ARG → ENV)  →  entrypoint (INI)
```

`support/docker-bake.hcl` does **not** read `.env` itself — every value reaches
it through the environment exported by the Makefile. That is why
`PHP_VERSION=8.5 make build` reliably works; in the previous repositories such a
call had no effect.

Groups in `.env`:

| Group | Keys (excerpt) |
|---|---|
| Repository and registry | `GITHUB_ORG`, `GITHUB_REPO`, `DOCKER_HUB`, `IMAGE_NAME_CLI`, `IMAGE_NAME_FPM`, `MAINTAINER_EMAIL` |
| Base versions | `PHP_VERSION`, `ALPINE_VERSION`, `COMPOSER_VERSION`, `NGINX_VERSION`, `MARIADB_VERSION` |
| PECL versions | `APCU_VERSION`, `REDIS_VERSION`, `XDEBUG_VERSION`, `PCOV_VERSION`, `AMQP_VERSION`, `RDKAFKA_VERSION` |
| Database clients | `INSTALL_DB_CLIENTS` (empty, or `mysql,postgres,sqlite`) |
| Container user | `PUID`, `PGID`, `APP_ROOT` |
| Environment | `APP_ENV` plus eight **empty override slots** (see below) |
| PHP, profile-independent | `PHP_MEMORY_LIMIT`, `PHP_TIMEZONE`, `PHP_LOG_ERRORS`, `PHP_MAX_EXECUTION_TIME_CLI`, `PHP_MAX_EXECUTION_TIME_WEB`, `APCU_SHM_SIZE`, `OPCACHE_*`, `XDEBUG_*` |
| FPM pool | `FPM_PM`, `FPM_PM_MAX_CHILDREN`, `FPM_PM_START_SERVERS`, `FPM_PM_MIN_SPARE_SERVERS`, `FPM_PM_MAX_SPARE_SERVERS`, `FPM_PM_MAX_REQUESTS` |
| Demo stack | `DEMO_DB_*`, `DEMO_HTTP_PORT` |

The extension list is **not** in `.env` and not in a Dockerfile, but in
`src/shared/php-extensions.env` — once for all targets.

`make info` always shows what actually applies.

### No Dockerfile carries a version default

No `ARG` in this repository has a default value. If a value is missing, the build
fails visibly instead of quietly building something other than what `.env`
declares. That was a latent defect in the previous setup: `phpcli` hard-coded
`COMPOSER_VERSION=2.9.3` while `.env` maintained 2.9.5.

The price is three hadolint warnings on every build — see
[operating conditions](#operating-conditions-and-known-quirks).

---

## `APP_ENV` — one switch for the environment

Xdebug, PCOV, and OPcache/JIT are built into **all** images. Switching
environments therefore needs no rebuild, only one variable:
`APP_ENV=dev|test|prod`.

|  | `dev` | `test` | `prod` |
|---|---|---|---|
| `XDEBUG_MODE` | `debug` | `off` | `off` |
| `PCOV_ENABLED` | `0` | `1` | `0` |
| `OPCACHE_ENABLE` | `1` | `1` | `1` |
| `OPCACHE_VALIDATE_TIMESTAMPS` | `1` | `1` | `0` |
| `OPCACHE_REVALIDATE_FREQ` | `0` | `0` | `0` |
| `OPCACHE_JIT` | `1254`¹ | `1254`¹ | `1254` |
| `PHP_DISPLAY_ERRORS` | `On` | `On` | `Off` |
| `PHP_ERROR_REPORTING` | `E_ALL` | `E_ALL` | `E_ALL & ~E_DEPRECATED` |

¹ In `dev` and `test` the JIT automatism turns the value to `off` at runtime,
because Xdebug or PCOV is active there (see below).

### Precedence rule

**An explicitly set individual variable beats the profile.** Fine-grained control
is therefore fully preserved:

```sh
docker run -e APP_ENV=dev -e XDEBUG_MODE=off  headgent/phpcli:8.3 php -v
docker run -e APP_ENV=test -e PCOV_ENABLED=0  headgent/phpcli:8.3 php -v
```

That is why `.env` carries the eight profile-driven variables as **empty** slots.
A value entered there would count as "explicitly set" and would override the
profile permanently — whoever wants that fills the slot in, whoever does not
leaves it empty.

### Four safeguards in the entrypoint

| Safeguard | Behaviour |
|---|---|
| **PCOV and Xdebug are mutually exclusive** | If PCOV is enabled and Xdebug active, PCOV wins; `XDEBUG_MODE` goes to `off`, reported in the log |
| **JIT automatism** | If Xdebug **or** PCOV takes over `zend_execute_ex()`, `opcache.jit` is explicitly disabled. Otherwise PHP disables JIT itself and warns on *every* invocation |
| **Production guard** | `APP_ENV=prod` with active Xdebug **aborts** startup with a clear message. No silent takeover |
| **Validation** | Every value is checked (mode names, byte sizes, numbers, `On`/`Off`). A typo aborts startup instead of ending up in the INI |

The generated runtime INI is written as `99-runtime-config.ini` in `conf.d` and
therefore loads after all image INIs. It is rewritten on every start — changes to
it are ephemeral.

---

## Runtime UID/GID

The container starts as root, aligns `appuser` with the owner of `APP_ROOT`
(`/app`), and drops privileges via `su-exec`. This is where the previous images
failed on Linux; here it is rebuilt structurally:

- An **occupied target GID/UID** leads either to reusing the existing identity or
  to a visible error — never to silent swallowing. (Alpine occupies GID 20 and
  GID 100 among others, both common host GIDs.)
- A **root-owned `/app`** — the normal case with a fresh named volume — is
  handled explicitly instead of skipped.
- After a change, **all paths created by the image are updated** accordingly.
- If the container is started from outside with `--user <uid>:<gid>`, the
  entrypoint makes **no** adjustment; the image also works with an identity
  unknown to it. The runtime INI then falls back to a writable directory via
  `PHP_INI_SCAN_DIR`.

This is proven on a real Linux host (not through the macOS file bridge, which
masks the defect): `make test-uid-linux` starts a `docker:28-dind` container and
checks thirteen assertions against a real Linux bind mount.

For the `fpm` target the master deliberately runs as root and switches the
workers itself via the pool configuration's `user =` directive — the `su-exec`
route provably does not work there.

---

## nginx template instead of an nginx image

`tests/nginx/templates/default.conf.template` runs with the **unmodified**
official `nginx` image through its built-in substitution (`/etc/nginx/templates`)
— no custom entrypoint, no custom build.

`envsubst` has no notion of defaults. The default values therefore live in
`tests/nginx/nginx-defaults.env`; without that file nginx does not start.

| Variable | Default | Meaning |
|---|---|---|
| `HOST` | `localhost` | `server_name` |
| `APP_ROOT` | `/app` | root of the project inside the container |
| `DOCUMENT_ROOT` | `/public` | subdirectory holding the front controller |
| `INDEX_FILE` | `index.php` | front controller |
| `FASTCGI_UPSTREAM` | `app` | hostname of the php-fpm service |
| `PHP_PORT` | `9000` | FastCGI port |
| `CLIENT_MAX_BODY_SIZE` | `100m` | maximum request size |
| `FASTCGI_READ_TIMEOUT` | `600` | seconds |
| `FASTCGI_SEND_TIMEOUT` | `600` | seconds |
| `FASTCGI_CONNECT_TIMEOUT` | `300` | seconds |
| `REQUEST_SCHEME` | `http` | `http` or `https` — **one** switch |

`REQUEST_SCHEME` is deliberately a single switch: it sets `HTTPS` and
`REQUEST_SCHEME` in the fastcgi parameters together. Two separate values could
contradict each other, and the previous version reported `HTTPS=on` to PHP under
all circumstances — correct behind a TLS-terminating Traefik, wrong in every
other stack.

It also contains the hardening the previous version lacked: `try_files` in the
`.php` fallback location (the `/upload.jpg/x.php` path no longer reaches php-fpm)
and security headers for static files as well.

---

## Demo stack

`tests/demo/demo-stack.yml` shows the path a project should take: **our** `fpm`
image plus two unmodified official images.

```sh
make demo-up      # mariadb + fpm + nginx, waits until all three are healthy
# → http://localhost:8088
make demo-down
```

All three services have health checks, the database lives in `tmpfs`, and the
nginx variables from the table above are filled in as an example. The host port
is configurable via `DEMO_HTTP_PORT` in `.env`.

Until the first push, `make demo-up` runs the locally built test images. The
compose file references `headgent/phpfpm:<ver>` the way a project would write it
— but under that name the registry still holds the previous images.

---

## The test run

```sh
make test-all                     # PHP_VERSION from .env
PHP_VERSION=8.5 make test-all     # check a different version
```

Thirteen stages, ordered by runtime — whatever needs no image runs first:

| Stage | Scope |
|---|---|
| `test-lint` | hadolint over three Dockerfiles, shellcheck over sixteen shell files |
| `test-bake` | eight cases against the resolved bake definition: `base` dependency, tag set, `base` is not published |
| `test-phpini` | 34 cases against the profile library, without a container |
| `test-user` | 27 cases against the UID/GID library, in `alpine:3.23` |
| `test-boot` | `cli` starts, `fpm` becomes healthy |
| `test-labels` | seven cases per image: the OCI labels, inherited via `FROM base` |
| `test-extensions` | 21 extensions in `cli` **and** `fpm` |
| `test-app-env` | 15 cases: profiles, precedence rule, production guard, validation — on the built image |
| `test-uid` | five cases against real Docker volumes |
| `test-uid-linux` | 13 cases against a real Linux bind mount in `docker:28-dind` — **requires `--privileged`** |
| `test-opcache` | 14 cases, including revalidation in a running FPM |
| `test-nginx` | 55 cases against the unmodified official nginx image, in two instances: defaults only / everything overridden |
| `test-demo` | 21 cases against the running demo stack, including residue-free teardown |

The scripts live in `tests/` and also run individually, without make. Test images
are created under the prefix `php-image-builder-test/` and do **not** overwrite
local `headgent/*` images.

### Green on the first attempt means a counter-check is due

Eight checks in this repository once reported green without measuring anything.
Every time it only surfaced through the counter-check against the known-broken
state. A new check therefore needs proof that it turns **red** against the broken
state.

| The trap | |
|---|---|
| OPcache | does not cache files younger than 2 s — without waiting and without `num_cached_scripts`/`hits` the test measures nothing |
| FPM process title | under emulation a worker carries no `pool www` title — check via user or `/ping` |
| `--entrypoint php` | bypasses the entrypoint; there is then no runtime INI and you measure extension defaults |
| Empty named volume | inherits the ownership of the image directory on first mount and overwrites the test's setup |
| busybox `wget --post-file` | sets POST but sends no body |
| `docker compose up --wait` | reports a service **without** a health check as ready immediately |
| Wrong probe | one check measured the directory owner — that is, the *input* of the case — instead of the process identity |
| `--filter ancestor=<tag>` | matches the image **ID**: a message attributed a container to the wrong tag. A status output can report something other than what it determined |

---

## Cleaning up

`make disk-usage` first shows what this is even about: what Docker occupies in
total, which images come from this repository, and how many dangling layers are
lying around. It deletes nothing.

After that, this is usually enough:

```sh
make clean          # demo leftovers, test images, dangling layers
make clean-all      # additionally the headgent/* images and the buildx cache
```

**The rule these targets follow:** they touch what *this repository* created. The
references come from `.env`, not from a glob over everything local — foreign
images, volumes, and containers on a development machine are none of this
repository's business.

Two limitations that deserve to be named rather than glossed over:

- **`clean-dangling` is inevitably machine-wide.** A dangling layer carries no
  name, so there is no way to tell whose build it came from. The operation is the
  usual and harmless one — a layer without a tag is referenced by no image — but
  it is not scoped to this repository.
- **`clean-images` also hits the previous images.** Until the first push,
  `headgent/phpcli` and `headgent/phpfpm` hold the images pulled from the
  registry. They are recoverable, but they are gone.

There is a separate target for the sledgehammer, and it is guarded:

```sh
make clean-system              # only shows what it would cost, then aborts
make clean-system CONFIRM=ja   # removes EVERY unused image, network, and volume
```

`clean-system` explicitly reaches beyond this repository and also hits artefacts
of other projects. An accidentally typed `make clean-system` should not be the
moment they disappear — without `CONFIRM=ja` nothing happens except a report.
Surrounding whitespace is ignored, anything other than exactly `ja` aborts (`Ja`,
`JA`, `yes` all block).

None of these targets hangs off `test-all`. They delete exactly the artefacts the
test run checks against — they belong beside it, not inside it.

---

## CI and publishing

`.github/workflows/ci.yml` replaces the two previous workflows. Triggers: push to
`main`, pull requests, manual dispatch, and a schedule every three days (with a
keepalive job against GitHub's 60-day shutdown).

| Job | Contents |
|---|---|
| `lint` | `make test-lint`, `make test-bake` |
| `build-test` | matrix 8.3 / 8.4 / 8.5, each `make test-all`, then Trivy |
| `publish` | multi-arch build and push with SBOM and provenance attestation |

**Trivy blocks** on CRITICAL/HIGH **with an available fix** (`ignore-unfixed`).
Such a finding means our image is behind the patch level — so the gate is
actionable. Findings **without** a fix sit in the official base image and cannot
be fixed by us; they would keep the pipeline permanently red and are therefore
reported in full in the job summary instead of blocking.

> ### Publishing is blocked
>
> This repository has **no GitHub remote**, has never been pushed, and the
> `publish` job only runs when the repository variable `PUBLISH_ENABLED` is set
> to `true` — it does not exist. No `docker login`, no `--push`, no CI trigger.
>
> The block stays until the **tag strategy** is approved. `headgent/phpcli` is a
> published series with consumers — counted: **26 active references, all on
> `headgent/phpcli:8.3`**. The first push out of this repository must not swap
> that tag underneath running projects.
>
> The plan is two channels (`next` and `stable`): the first push goes exclusively
> to `:<ver>-next` and `:<ver>-<date>`, promotion happens later via a registry
> retag of the verified digest rather than a second build. The full decision
> document lives as a working paper in `docs/TAG-STRATEGIE.md` and is not part of
> the repository.

---

## Operating conditions and known quirks

**Three hadolint warnings on every build are intended.**
`InvalidDefaultArgInFrom` appears three times because `PHP_VERSION`,
`ALPINE_VERSION`, and `COMPOSER_VERSION` have no default in the `FROM` lines —
which is precisely the requirement. A default could override `.env`. The warnings
cannot be silenced without bringing the defect back, and they are **not** an
error.

**`make build-all` needs disk space.** bake builds all three PHP versions
**simultaneously**. On a full Docker VM that ends in "No space left on device".
That is not a design flaw but an operating condition — if in doubt run
`make build` per version, or `make build-cache-delete` beforehand.

**`make test-all` requires `--privileged`.** The `test-uid-linux` stage starts a
`docker:28-dind` container. Without that capability the remaining twelve stages
can still be run individually.

**The demo stack listens on port 8088**, not 8080 — that one is frequently taken
on development machines. The test run additionally uses 18080.

**`nginx -t` alone does not validate the template.** nginx resolves the upstream
name when loading the configuration; without a running `fpm` service the test
fails on name resolution rather than on the template. That is why `test-nginx`
checks against a real stack.

**Two NOTICEs when starting with `--user`** come from the `www.conf` of the
official base image and are purely informational.

---

## Migrating from the previous images

What consumers of the previous images will notice once the first push is
approved:

| Change | Effect |
|---|---|
| **`php-cgi` and `phpdbg` are gone** from `headgent/phpcli` | consequence of basing `base` on `php:<ver>-fpm-alpine`: that image is a measured 16.7 MB **smaller** than the cli image and carries a byte-identical PHP CLI. Workers, queue consumers, cron, Composer, and CI need neither — whoever uses `phpdbg` has to know |
| **PHP 8.2 is no longer built**, 8.5 is added | the matrix is 8.3 / 8.4 / 8.5 |
| **`APP_ENV` controls the environment** | the image ships with `APP_ENV=dev`. Production now explicitly means `APP_ENV=prod` — otherwise Xdebug is active, which it was not in the previous `fpm` image |
| **The Unix group is called `appuser` in both images** | `headgent/phpcli` previously called it `appgroup` |
| **`pcntl` is now in the `fpm` image too** | costs nothing at runtime |
| **`INSTALL_DB_CLIENTS` now applies to both targets** | it previously existed only in `phpcli` |
| **`headgent/nginx` is no longer built** | the replacement is the template in this repository plus the official image. The existing image stays in the registry without a maintenance promise — it has no consumers |
| **`headgent/phpfpm` starts again** | all three published versions of the previous image fail to start: the `chown` on `/proc/self/fd/{1,2}` returns exit 0 without effect, and FPM then fails on `error_log` |
| **`STOPSIGNAL` in the cli image is `SIGTERM`** | instead of the `SIGQUIT` inherited from the fpm base image, which a pcntl worker loop does not listen for |

`EXPOSE 9000` is also present in the cli image — an inherited metadata line
without effect; Docker has no "unexpose".
