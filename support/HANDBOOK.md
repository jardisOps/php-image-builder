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
- [Properties worth knowing about the images](#properties-worth-knowing-about-the-images)

---

## Usage

A root `Makefile` includes the modules from `support/makefiles/`. Every target
carries its own help text; `make help` lists all of them with a one-line
description — this section only adds what that line does not say.

### Building

A value on the `make` command line beats `.env`:

```sh
make build PHP_VERSION=8.5
make build BAKE_TARGETS=fpm            # one target only; base is pulled in automatically
make build BUILD_PLATFORM=linux/amd64  # a single platform instead of the host architecture
make build CACHE_BACKEND=none          # auto | gha | registry | local | none
```

The `gha` backend takes three more switches, all of them only relevant in CI:
`CACHE_SCOPE` (the namespace written and read), `CACHE_READ_SCOPES` (further
namespaces read but never written) and `CACHE_MODE` (`rw` or `w`, write
only). What they are for is in [CI and publishing](#ci-and-publishing).

(The leading-variable form, `PHP_VERSION=8.5 make build`, does **not** work —
for a plain environment variable the included `.env` file wins.)

**`make init` must never run outside an approved push** — it points the git
remote at `GITHUB_ORG`/`GITHUB_REPO` from `.env`; see [CI and
publishing](#ci-and-publishing).

### Publishing

> `make push` / `push-all` publish to Docker Hub and run only after explicit
> approval — see [Who is allowed to
> publish](../README.md#who-is-allowed-to-publish).

### Testing

`make test-all` bundles everything; the stages can be run individually
(→ [The test run](#the-test-run)).

### Demo stack targets

`make demo-up` / `demo-down` / `demo-logs` / `demo-config` — one-line
descriptions via `make help`; the full walkthrough is in [Demo
stack](#demo-stack) below.

### Cleanup targets

One-line descriptions via `make help`; the nuances worth knowing —
`clean-dangling` is machine-wide, `clean-system` needs `CONFIRM=ja` — are in
[Cleaning up](#cleaning-up) below.

### SSH keys

`make ssh-generate-ed25519`, `ssh-generate-rsa`, `ssh-show-keys`, `ssh-add-key`,
`ssh-start-agent` — interactive wrappers around `ssh-keygen` and `ssh-add`. They
have nothing to do with building images and are kept only because existing usage
relies on them.

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
`make build PHP_VERSION=8.5` reliably overrides it.

Every key is grouped and commented directly in `.env` — repository/registry,
base versions, PECL versions, database clients, container user, `APP_ENV` plus
its eight empty override slots (see below), profile-independent PHP settings,
the FPM pool, and the demo stack. Read `.env` itself for the current list; a
table here would drift with every added key.

The extension list is **not** in `.env` and not in a Dockerfile, but in
`src/shared/php-extensions.env` — once for all targets.

`make info` always shows what actually applies.

### No Dockerfile carries a version default

No `ARG` in this repository has a default value. If a value is missing, the build
fails visibly instead of quietly building something other than what `.env`
declares. The failure mode this prevents is a `COMPOSER_VERSION` baked into a
Dockerfile while `.env` maintains a different one — the build stays green and
nobody sees which of the two won.

The price is three hadolint warnings on every build, `InvalidDefaultArgInFrom`,
one each for `PHP_VERSION`, `ALPINE_VERSION`, and `COMPOSER_VERSION` in the
`FROM` lines — precisely the requirement, since a default there could override
`.env`. They cannot be silenced without bringing the defect back and are
**not** an error.

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
(`/app`), and drops privileges via `su-exec`. Every branch of that alignment is
handled explicitly — this is the part that silently misbehaves on Linux when it
is not:

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
contradict each other. A configuration that reports `HTTPS=on` to PHP under all
circumstances is correct behind a TLS-terminating Traefik and wrong in every
other stack — hence one switch, filled per deployment.

The template also carries `try_files` in the `.php` fallback location (so the
`/upload.jpg/x.php` path never reaches php-fpm) and security headers for static
files as well.

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
compose file references `headgent/phpfpm:<ver>` the way a project would write it;
nothing is published under that name yet.

---

## The test run

```sh
make test-all                     # PHP_VERSION from .env
make test-all PHP_VERSION=8.5     # check a different version
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
- **`clean-images` also hits `headgent/*` images that this repository did not
  build.** The targets go by the references in `.env`, and those name the
  published series. Nothing is published under it at the moment, so whatever a
  machine still holds under that name is a local copy — and `clean-images`
  removes it without a way back.

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

`.github/workflows/ci.yml` is the single workflow. Triggers: push to `main`,
pull requests, manual dispatch, and a monthly schedule on the 1st at 02:00 UTC
(with a keepalive job against GitHub's 60-day shutdown). The monthly run is what
keeps the base-image patch level current; cron cannot express "every four weeks"
without the interval jumping between 28 and 3 days.

| Job | Contents |
|---|---|
| `lint` | `make test-static` (`test-lint` + `test-bake`, version-independent) |
| `build-test` | matrix 8.3 / 8.4 / 8.5, each `make test-image-suite`, then Trivy |
| `publish` | multi-arch build and push with SBOM and provenance attestation — schedule and `workflow_dispatch` only |

**A publishing run cannot be cancelled by a commit.** The concurrency group
carries the trigger, and only `push` and `pull_request` cancel what is already
running. Otherwise a commit landing on `main` during the monthly run would
interrupt a `--push` halfway through its manifest — `cancel-in-progress` is a
property of the arriving run, not of the one being cancelled.

`test-static` and `test-image-suite` (`support/makefiles/test.mk`) split
`make test-all` into its version-independent and per-version halves so the
former doesn't rerun in every matrix job. Locally, `make test-all` still runs
all thirteen stages in one go.

**Trivy blocks** on CRITICAL/HIGH **with an available fix** (`ignore-unfixed`).
Such a finding means our image is behind the patch level — so the gate is
actionable. Findings **without** a fix sit in the official base image and cannot
be fixed by us; they would keep the pipeline permanently red and are therefore
reported in full in the job summary instead of blocking.

It scans the **test** image, not the pushed one. That is a second object built
from the same source — amd64 only, no attestations, its own name — whose
filesystem layers match the amd64 half of what `publish` pushes. For a scanner,
which reads packages and versions, the two are the same. The arm64 half is
scanned by nothing: CI builds it, but never boots or scans it.

### The layer cache

Both building jobs use BuildKit's GitHub Actions cache. It needs
`ACTIONS_RUNTIME_TOKEN` and the cache service URL, and the runner hands those
to JavaScript actions only — **never to a `run:` step**. Without them buildx
does not complain, it discards `--cache-from`/`--cache-to` silently. That is
why an `actions/github-script` step lifts the variables into the job
environment before every `make` call that builds. Without that step the cache
setting is decoration: measured in run 30236711245, not a single cached step
and every extension recompiled.

| Job | writes | reads |
|---|---|---|
| `build-test` | `test-<ver>` | `test-<ver>` |
| `publish` | `publish-<ver>` | `publish-<ver>` **and** `test-<ver>` |

Separate write namespaces, because a cache key is immutable once written and
the second writer of a shared one loses its entry. That would hit whichever job
finishes last, and in `publish` those are the arm64 layers — the expensive
ones. Reading `test-<ver>` is what saves `publish` the second amd64 build.

**The scheduled run writes but does not read** (`CACHE_MODE=w`). It exists to
pick up patched base layers; reading the stored cache would hand it exactly the
state it is meant to replace, and it would republish it under a new date tag.

Do not expect the cache to halve the publish job. Measured in the same run,
`publish (8.4)`, 47 minutes in total: the extension build takes **240 s on
amd64 and 2774 s on arm64** under emulation. Both architectures run in
parallel, so the clock follows arm64 — and no arm64 layer can ever come out of
`build-test`, which builds amd64 only. Within a run the cache saves about four
minutes. It earns its keep across runs, where a `publish` whose sources have
not changed skips the arm64 compile as well. Getting at those 46 minutes for
real means a native arm64 runner, one job per architecture and a merged
manifest — a rebuild of the push path, deliberately not done here.

> ### Publishing
>
> See [Who is allowed to publish](../README.md#who-is-allowed-to-publish) in
> the README for both conditions (`PUBLISH_ENABLED`, and schedule or
> `workflow_dispatch` — never a commit).
>
> What is published today: `:<ver>` and the immutable `:<ver>-<date>` twin for
> 8.3 / 8.4 / 8.5, plus `:latest` on the highest version, for both images and
> both architectures. The working paper behind that tag set,
> `docs/TAG-STRATEGIE.md`, is not part of the repository.

---

## Operating conditions and known quirks

**Three hadolint warnings on every build are intended** — see [No Dockerfile
carries a version default](#no-dockerfile-carries-a-version-default).

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

## Properties worth knowing about the images

Nothing here is a defect; they are consequences of the design that a consumer
can run into without warning.

| Property | Reason |
|---|---|
| **`php-cgi` and `phpdbg` are absent** from `headgent/phpcli` | `base` builds on `php:<ver>-fpm-alpine`, a measured 16.7 MB smaller than the cli image and carrying a byte-identical PHP CLI. Workers, queue consumers, cron, Composer and CI need neither — whoever uses `phpdbg` has to know |
| **The matrix is 8.3 / 8.4 / 8.5** | one series, `:latest` follows the last entry |
| **`APP_ENV` ships as `dev`** | production has to say `APP_ENV=prod` explicitly; otherwise Xdebug is active. `prod` with active Xdebug aborts startup rather than starting quietly |
| **The Unix group is `appuser` in both images**, not `appgroup` | one name across both targets; anything addressing the group by name has to match. The numeric GID is unaffected |
| **`pcntl` is in the `fpm` image as well** | costs nothing at runtime, and leaving it out was a usage limit rather than a safeguard |
| **`INSTALL_DB_CLIENTS` applies to both targets** | one switch, not one per image |
| **`STOPSIGNAL` in the cli image is `SIGTERM`** | the fpm base image passes down `SIGQUIT`, which a pcntl worker loop does not listen for |
| **`EXPOSE 9000` also appears in the cli image** | inherited metadata without effect; Docker has no "unexpose" |
| **There is no `headgent/nginx`** | the replacement is the template in this repository plus the unmodified official image |
