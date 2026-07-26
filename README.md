# php-image-builder

Ein Repo, das die PHP-Laufzeit-Images von Headgent baut: **`headgent/phpcli`** und
**`headgent/phpfpm`**, für PHP **8.3 / 8.4 / 8.5** auf Alpine, für `linux/amd64`
und `linux/arm64`, aus **einer** Konfigurationsquelle und in **einem**
`docker buildx bake`-Lauf.

Es löst die beiden getrennten Repos `jardisOps/phpcli` und `jardisOps/phpfpm` ab,
deren Entrypoints zu rund 80 % identischer Code waren und deren Konfiguration in
sechzehn Punkten auseinandergelaufen war. Die publizierten Image-Namen bleiben
unverändert — Konsumenten müssen nichts umstellen.

| Target | Publiziert als | Basis | Zweck |
|---|---|---|---|
| `base` | — (**nicht** publiziert) | `php:<ver>-fpm-alpine<alpine>` | PHP-Version, Extensions, Composer, Benutzer, Entrypoint-Kern — genau einmal beschrieben |
| `cli` | `headgent/phpcli` | `base` | Worker, Queue-Consumer, Cron, Composer, CI- und Build-Kontext |
| `fpm` | `headgent/phpfpm` | `base` | php-fpm-only, Sidecar hinter einem eigenen Webserver |

**nginx ist kein Build-Target.** Statt eines eigenen Images liefert dieses Repo
die vollständig parametrisierte Server-Konfiguration als versioniertes Asset,
das mit dem **unveränderten** offiziellen `nginx`-Image läuft
(→ [nginx-Vorlage](#nginx-vorlage-statt-nginx-image)).

---

## Inhalt

- [Voraussetzungen](#voraussetzungen)
- [Schnellstart](#schnellstart)
- [Bedienung](#bedienung)
- [Konfiguration](#konfiguration)
- [`APP_ENV` — ein Schalter für die Umgebung](#app_env--ein-schalter-für-die-umgebung)
- [UID/GID zur Laufzeit](#uidgid-zur-laufzeit)
- [nginx-Vorlage statt nginx-Image](#nginx-vorlage-statt-nginx-image)
- [Demo-Stack](#demo-stack)
- [Der Prüflauf](#der-prüflauf)
- [Aufräumen](#aufräumen)
- [Aufbau des Repos](#aufbau-des-repos)
- [CI und Veröffentlichung](#ci-und-veröffentlichung)
- [Betriebsbedingungen und bekannte Eigenheiten](#betriebsbedingungen-und-bekannte-eigenheiten)
- [Umstieg vom Bestand](#umstieg-vom-bestand)
- [Dokumentation](#dokumentation)

---

## Voraussetzungen

- Docker mit **Buildx** (bake wird gebraucht, nicht `docker build`)
- GNU Make
- Für den vollständigen Prüflauf: ein Docker-Daemon, der `--privileged`-Container
  zulässt (die UID-Prüfung auf Linux fährt einen `docker:28-dind`-Host hoch) und
  mehrere Gigabyte freien Plattenplatz
- Kein PHP auf dem Host nötig

## Schnellstart

```sh
make help          # alle Targets mit Hilfetext
make info          # die aufgelöste Build-Konfiguration
make build         # cli + fpm für PHP_VERSION aus der .env, lokal geladen
make test-all      # der vollständige Prüflauf (dreizehn Stufen)
make demo-up       # Demo-Stack: mariadb + fpm + offizielles nginx
```

---

## Bedienung

Ein Root-`Makefile` bindet die Module aus `support/makefiles/` ein. Jedes Target
trägt seinen Hilfetext bei sich; `make help` liest sie aus.

### Bauen

| Target | Wirkung |
|---|---|
| `make build` | `cli` + `fpm` für die eine `PHP_VERSION` aus der `.env`, `--load` in den lokalen Daemon |
| `make build-all` | dasselbe für die **ganze** Matrix (8.3 / 8.4 / 8.5) in einem Lauf |
| `make bake-print` | die aufgelöste Bake-Definition, baut nichts |
| `make buildx-builder-create` | den Multiarch-Builder anlegen bzw. aktivieren |
| `make builder-reset` | Builder löschen und neu anlegen |
| `make build-cache-delete` | alle gecachten Layer verwerfen (`buildx prune -a`) |
| `make init` | setzt den Git-Remote auf `GITHUB_ORG`/`GITHUB_REPO` aus der `.env` — **noch nie gelaufen**, siehe [CI und Veröffentlichung](#ci-und-veröffentlichung) |

Nützliche Übersteuerungen — die Umgebung schlägt die `.env`:

```sh
PHP_VERSION=8.5 make build
make build BAKE_TARGETS=fpm            # nur ein Target; base kommt automatisch mit
make build BUILD_PLATFORM=linux/amd64  # eine Plattform statt der Host-Architektur
make build CACHE_BACKEND=none          # auto | gha | registry | local | none
```

### Veröffentlichen

| Target | Wirkung |
|---|---|
| `make push` | Multi-Arch-Build **und** Push für eine PHP-Version, mit SBOM- und Provenance-Attestation |
| `make push-all` | dasselbe für die ganze Matrix |

> **Diese beiden Targets sind geschrieben, aber noch nie ausgeführt worden.**
> Der erste Push ist der einzige Vorgang dieses Repos mit Außenwirkung und
> ausdrücklich gesperrt — siehe [CI und Veröffentlichung](#ci-und-veröffentlichung).

### Prüfen

`make test-all` fasst alles zusammen; die Stufen sind einzeln aufrufbar
(→ [Der Prüflauf](#der-prüflauf)).

### Demo-Stack

| Target | Wirkung |
|---|---|
| `make demo-up` | Stack starten und auf `healthy` warten |
| `make demo-down` | Container, Netz und Volumes entfernen |
| `make demo-logs` | Logs folgen |
| `make demo-config` | aufgelöste Stack-Definition, startet nichts |

### Aufräumen

Ein Bauwerkzeug erzeugt Müll — Test-Images unter zwei Namen mal drei Versionen,
baumelnde Layer aus jedem abgebrochenen Lauf, den buildx-Cache. Was die Targets
anfassen und was bewusst nicht, steht unter [Aufräumen](#aufräumen).

| Target | Wirkung |
|---|---|
| `make disk-usage` | zeigt, was Docker belegt und was davon aus diesem Repo stammt — **löscht nichts** |
| `make clean` | der Regelfall: Demo-Reste, Test-Images, baumelnde Layer |
| `make clean-test-images` | nur die Test-Images des Prüflaufs, alle Versionen |
| `make clean-images` | die lokal gebauten `headgent/*`-Images, alle Versionen |
| `make clean-dangling` | baumelnde Layer (`<none>`) |
| `make clean-cache` | den buildx-Cache leeren |
| `make clean-demo` | Container, Netz und Volumes des Demo-Stacks |
| `make clean-all` | alles aus diesem Repo: `clean` plus `headgent/*` plus Cache |
| `make clean-system` | **global**, verlangt `CONFIRM=ja` — siehe unten |

### SSH-Schlüssel

`make ssh-generate-ed25519`, `ssh-generate-rsa`, `ssh-show-keys`, `ssh-add-key`,
`ssh-start-agent` — unverändert aus den Bestands-Repos übernommene, interaktive
Wrapper um `ssh-keygen` und `ssh-add`. Sie haben mit dem Bauen der Images nichts
zu tun und stehen nur hier, weil sie es in den Vorgänger-Repos auch taten.

---

## Konfiguration

**Die `.env` im Repo-Root ist die einzige Quelle.** Sie speist Build-Argumente
und Laufzeit-Defaults gleichermaßen; kein Wert ist an zwei Stellen gepflegt.

Der Weg eines Wertes ist immer derselbe:

```
.env  →  Makefile (export)  →  docker-bake.hcl (build-arg)  →  Dockerfile (ARG → ENV)  →  Entrypoint (INI)
```

`docker-bake.hcl` liest die `.env` **nicht** selbst — es bekommt jeden Wert über
die vom Makefile exportierte Umgebung. Deshalb wirkt `PHP_VERSION=8.5 make build`
zuverlässig; im Bestand war ein solcher Aufruf wirkungslos.

Gruppen in der `.env`:

| Gruppe | Schlüssel (Auszug) |
|---|---|
| Repository und Registry | `GITHUB_ORG`, `GITHUB_REPO`, `DOCKER_HUB`, `IMAGE_NAME_CLI`, `IMAGE_NAME_FPM`, `MAINTAINER_EMAIL` |
| Basis-Versionen | `PHP_VERSION`, `ALPINE_VERSION`, `COMPOSER_VERSION`, `NGINX_VERSION`, `MARIADB_VERSION` |
| PECL-Versionen | `APCU_VERSION`, `REDIS_VERSION`, `XDEBUG_VERSION`, `PCOV_VERSION`, `AMQP_VERSION`, `RDKAFKA_VERSION` |
| Datenbank-Clients | `INSTALL_DB_CLIENTS` (leer, oder `mysql,postgres,sqlite`) |
| Container-Benutzer | `PUID`, `PGID`, `APP_ROOT` |
| Umgebung | `APP_ENV` sowie acht **leere Override-Slots** (siehe unten) |
| PHP, profilunabhängig | `PHP_MEMORY_LIMIT`, `PHP_TIMEZONE`, `PHP_LOG_ERRORS`, `PHP_MAX_EXECUTION_TIME_CLI`, `PHP_MAX_EXECUTION_TIME_WEB`, `APCU_SHM_SIZE`, `OPCACHE_*`, `XDEBUG_*` |
| FPM-Pool | `FPM_PM`, `FPM_PM_MAX_CHILDREN`, `FPM_PM_START_SERVERS`, `FPM_PM_MIN_SPARE_SERVERS`, `FPM_PM_MAX_SPARE_SERVERS`, `FPM_PM_MAX_REQUESTS` |
| Demo-Stack | `DEMO_DB_*`, `DEMO_HTTP_PORT` |

Die Extension-Liste steht **nicht** in der `.env` und nicht im Dockerfile,
sondern in `src/shared/php-extensions.env` — einmal für alle Targets.

`make info` zeigt jederzeit, was tatsächlich gilt.

### Kein Dockerfile trägt einen Versions-Default

Kein `ARG` in diesem Repo hat einen Vorgabewert. Fehlt ein Wert, bricht der Build
sichtbar ab, statt still etwas anderes zu bauen, als die `.env` pflegt. Genau das
war im Bestand ein latenter Defekt: `phpcli` hatte `COMPOSER_VERSION=2.9.3`
hartkodiert, während die `.env` 2.9.5 pflegte.

Der Preis dafür sind drei hadolint-Warnungen bei jedem Build — siehe
[Betriebsbedingungen](#betriebsbedingungen-und-bekannte-eigenheiten).

---

## `APP_ENV` — ein Schalter für die Umgebung

Xdebug, PCOV und OPcache/JIT sind in **allen** Images fest eingebaut. Ein
Umgebungswechsel braucht deshalb keinen Rebuild, sondern nur eine Variable:
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

¹ In `dev` und `test` schaltet die JIT-Automatik den Wert zur Laufzeit auf `off`,
weil dort Xdebug bzw. PCOV aktiv ist (siehe unten).

### Vorrangregel

**Eine explizit gesetzte Einzelvariable schlägt das Profil.** Die Feinsteuerung
bleibt also vollständig erhalten:

```sh
docker run -e APP_ENV=dev -e XDEBUG_MODE=off  headgent/phpcli:8.3 php -v
docker run -e APP_ENV=test -e PCOV_ENABLED=0  headgent/phpcli:8.3 php -v
```

Deshalb führt die `.env` die acht profilgesteuerten Variablen als **leere**
Slots. Ein dort eingetragener Wert würde als „explizit gesetzt" gelten und das
Profil dauerhaft überstimmen — wer das will, trägt ihn ein; wer es nicht will,
lässt den Slot leer.

### Vier Sicherungen im Entrypoint

| Sicherung | Verhalten |
|---|---|
| **PCOV/Xdebug schließen sich aus** | Ist PCOV eingeschaltet und Xdebug aktiv, gewinnt PCOV; `XDEBUG_MODE` geht auf `off`, gemeldet im Log |
| **JIT-Automatik** | Übernimmt Xdebug **oder** PCOV `zend_execute_ex()`, wird `opcache.jit` ausdrücklich abgeschaltet. Sonst schaltet PHP JIT selbst ab und warnt bei *jedem* Aufruf |
| **Produktions-Wächter** | `APP_ENV=prod` mit aktivem Xdebug bricht den Start **ab**, mit klarer Meldung. Keine stille Übernahme |
| **Validierung** | Jeder Wert wird geprüft (Modus-Namen, Byte-Größen, Zahlen, `On`/`Off`). Ein Tippfehler bricht den Start ab, statt in der INI zu landen |

Die erzeugte Laufzeit-INI liegt als `99-runtime-config.ini` in `conf.d` und lädt
damit garantiert nach allen Image-INIs. Sie wird bei jedem Start neu geschrieben
— Änderungen daran sind flüchtig.

---

## UID/GID zur Laufzeit

Der Container startet als root, gleicht `appuser` an den Eigentümer von
`APP_ROOT` (`/app`) an und gibt die Rechte per `su-exec` ab. Das ist der Punkt,
an dem die Bestands-Images auf Linux fehlschlugen; hier ist er strukturell neu
gebaut:

- Eine **belegte Ziel-GID/UID** führt zur Wiederverwendung der vorhandenen
  Kennung oder zu einem sichtbaren Fehler — nie zum stillen Verschlucken.
  (Alpine belegt unter anderem GID 20 und GID 100, beides häufige Host-GIDs.)
- Ein **root-eigenes `/app`** — der Normalfall bei einem frischen Named Volume —
  wird ausdrücklich behandelt statt übersprungen.
- Nach einer Änderung sind **alle vom Image angelegten Pfade nachgezogen**.
- Wird der Container von außen mit `--user <uid>:<gid>` gestartet, unternimmt der
  Entrypoint **keine** Anpassung; das Image funktioniert auch mit einer ihm
  unbekannten Kennung. Die Laufzeit-INI weicht dann über `PHP_INI_SCAN_DIR` in
  ein beschreibbares Verzeichnis aus.

Nachgewiesen wird das auf einem echten Linux-Host (nicht über die
macOS-Dateibrücke, die den Fehler verdeckt): `make test-uid-linux` fährt dafür
einen `docker:28-dind`-Container hoch und prüft dreizehn Zusicherungen gegen
einen echten Linux-Bind-Mount.

Beim `fpm`-Target läuft der Master bewusst als root und wechselt die Worker über
die `user =`-Direktive der Pool-Konfiguration selbst — der Weg über `su-exec`
funktioniert dort nachweislich nicht.

---

## nginx-Vorlage statt nginx-Image

`compose/nginx/templates/default.conf.template` läuft mit dem **unveränderten**
offiziellen `nginx`-Image über dessen eingebaute Substitution
(`/etc/nginx/templates`) — ohne eigenen Entrypoint, ohne eigenen Build.

`envsubst` kennt keine Default-Schreibweise. Deshalb liegen die Vorgabewerte in
`compose/nginx/nginx-defaults.env`; ohne diese Datei startet nginx nicht.

| Variable | Default | Bedeutung |
|---|---|---|
| `HOST` | `localhost` | `server_name` |
| `APP_ROOT` | `/app` | Wurzel des Projekts im Container |
| `DOCUMENT_ROOT` | `/public` | Unterverzeichnis mit dem Front-Controller |
| `INDEX_FILE` | `index.php` | Front-Controller |
| `FASTCGI_UPSTREAM` | `app` | Hostname des php-fpm-Dienstes |
| `PHP_PORT` | `9000` | FastCGI-Port |
| `CLIENT_MAX_BODY_SIZE` | `100m` | maximale Request-Größe |
| `FASTCGI_READ_TIMEOUT` | `600` | Sekunden |
| `FASTCGI_SEND_TIMEOUT` | `600` | Sekunden |
| `FASTCGI_CONNECT_TIMEOUT` | `300` | Sekunden |
| `REQUEST_SCHEME` | `http` | `http` oder `https` — **ein** Schalter |

`REQUEST_SCHEME` ist bewusst ein einzelner Schalter: Er setzt `HTTPS` und
`REQUEST_SCHEME` in den fastcgi-Parametern gemeinsam. Zwei getrennte Werte
könnten sich widersprechen, und die Bestandsfassung meldete PHP unter allen
Umständen `HTTPS=on` — hinter einem TLS-terminierenden Traefik richtig, in jedem
anderen Stack falsch.

Enthalten ist außerdem die Härtung, die dem Bestand fehlte: `try_files` in der
`.php`-Fallback-Location (der `/upload.jpg/x.php`-Pfad erreicht php-fpm nicht
mehr) und Security-Header auch für statische Dateien.

---

## Demo-Stack

`compose/demo-stack.yml` zeigt den Weg, den ein Projekt gehen soll: **unser**
`fpm`-Image plus zwei unveränderte offizielle Images.

```sh
make demo-up      # mariadb + fpm + nginx, wartet bis alle drei healthy sind
# → http://localhost:8088
make demo-down
```

Alle drei Dienste haben Health-Checks, die Datenbank liegt im `tmpfs`, und die
nginx-Variablen aus der Tabelle oben sind exemplarisch befüllt. Der Host-Port ist
über `DEMO_HTTP_PORT` in der `.env` einstellbar.

Bis zum ersten Push fährt `make demo-up` die lokal gebauten Test-Images. Die
Compose-Datei verweist auf `headgent/phpfpm:<ver>`, wie ein Projekt es schreiben
würde — unter diesem Namen liegt in der Registry aber noch der Bestand.

---

## Der Prüflauf

```sh
make test-all                     # PHP_VERSION aus der .env
PHP_VERSION=8.5 make test-all     # eine andere Version prüfen
```

Dreizehn Stufen, sortiert nach Laufzeit — was ohne Image auskommt, läuft zuerst:

| Stufe | Umfang |
|---|---|
| `test-lint` | hadolint über drei Dockerfiles, shellcheck über sechzehn Shell-Dateien |
| `test-bake` | acht Fälle gegen die aufgelöste Bake-Definition: `base`-Abhängigkeit, Tag-Satz, `base` wird nicht publiziert |
| `test-phpini` | 34 Fälle gegen die Profil-Bibliothek, ohne Container |
| `test-user` | 27 Fälle gegen die UID/GID-Bibliothek, in `alpine:3.23` |
| `test-boot` | `cli` startet, `fpm` wird `healthy` |
| `test-labels` | sieben Fälle je Image: die OCI-Labels, über `FROM base` vererbt |
| `test-extensions` | 21 Extensions in `cli` **und** `fpm` |
| `test-app-env` | 15 Fälle: Profile, Vorrangregel, Produktions-Wächter, Validierung — am gebauten Image |
| `test-uid` | fünf Fälle gegen echte Docker-Volumes |
| `test-uid-linux` | 13 Fälle gegen einen echten Linux-Bind-Mount in `docker:28-dind` — **braucht `--privileged`** |
| `test-opcache` | 14 Fälle, darunter die Revalidierung im laufenden FPM |
| `test-nginx` | 55 Fälle gegen das unveränderte offizielle nginx-Image, in zwei Instanzen: nur Defaults / alles überschrieben |
| `test-demo` | 21 Fälle gegen den laufenden Demo-Stack, inklusive rückstandsfreiem Abbau |

Die Test-Images entstehen unter dem Präfix `php-image-builder-test/` und
überschreiben lokale `headgent/*`-Images **nicht**.

**Eine Leitlinie aus der Entstehung dieses Repos:** Sieben Prüffälle haben hier
schon einmal grün gemeldet, ohne irgendetwas zu messen — ein Test, der im ersten
Anlauf grün ist, ist erst mit einer Gegenprobe gegen den bekannt defekten Zustand
glaubwürdig. Die Fälle sind in `docs/PROGRESS.md` als B11, B16, B19, B20, B21,
B27 und B31 dokumentiert.

---

## Aufräumen

`make disk-usage` zeigt zuerst, worum es überhaupt geht: was Docker insgesamt
belegt, welche Images aus diesem Repo stammen, und wie viele baumelnde Layer
herumliegen. Es löscht nichts.

Danach genügt in aller Regel:

```sh
make clean          # Demo-Reste, Test-Images, baumelnde Layer
make clean-all      # zusätzlich die headgent/*-Images und den buildx-Cache
```

**Die Regel, an die sich diese Targets halten:** angefasst wird, was *dieses
Repo* erzeugt hat. Die Referenzen kommen aus der `.env`, nicht aus einem Glob
über alles Lokale — fremde Images, Volumes und Container eines
Entwicklungsrechners gehen dieses Repo nichts an.

Zwei Einschränkungen, die ehrlicher benannt als beschönigt gehören:

- **`clean-dangling` ist zwangsläufig rechnerweit.** Ein baumelnder Layer trägt
  keinen Namen, also lässt sich nicht feststellen, aus wessen Build er stammt.
  Die Operation ist die übliche und ungefährliche — ein Layer ohne Tag wird von
  keinem Image mehr referenziert —, aber sie ist nicht auf dieses Repo begrenzt.
- **`clean-images` trifft auch den Bestand.** Unter `headgent/phpcli` und
  `headgent/phpfpm` liegen bis zum ersten Push die aus der Registry gezogenen
  Bestands-Images. Sie sind wiederbeschaffbar, aber sie sind weg.

Für den Vorschlaghammer gibt es ein eigenes Target, und es ist verriegelt:

```sh
make clean-system              # zeigt nur, was es kosten würde, und bricht ab
make clean-system CONFIRM=ja   # entfernt JEDES ungenutzte Image, Netz und Volume
```

`clean-system` greift ausdrücklich über dieses Repo hinaus und trifft auch die
Artefakte fremder Projekte. Ein versehentlich getipptes `make clean-system` soll
nicht der Moment sein, in dem sie verschwinden — deshalb passiert ohne
`CONFIRM=ja` nichts außer einer Anzeige. Umgebende Leerzeichen sind egal, alles
andere als genau `ja` bricht ab (`Ja`, `JA`, `yes` blockieren).

Keines dieser Targets hängt an `test-all`. Sie löschen genau die Artefakte,
gegen die der Prüflauf prüft — sie gehören daneben, nicht hinein.

---

## Aufbau des Repos

```
php-image-builder/
├── .env                          # einzige Konfigurationsquelle
├── docker-bake.hcl               # Matrix: base → cli/fpm über contexts
├── Makefile                      # bindet support/makefiles/ ein
├── .hadolint.yaml .dockerignore
├── support/
│   ├── makefiles/
│   │   ├── docker.helper.mk      # Namen, Versionsmatrix, Cache-Backend, Builder
│   │   ├── docker.build.local.mk # bake --load
│   │   ├── docker.build.push.mk  # bake --push (nie ausgeführt)
│   │   ├── test.mk               # die dreizehn Prüfstufen
│   │   ├── demo.mk               # Demo-Stack
│   │   ├── clean.mk              # Aufräumen, auf dieses Repo begrenzt
│   │   └── ssh.mk                # SSH-Schlüssel (aus dem Bestand)
│   └── tests/                    # elf Prüfskripte
├── src/
│   ├── shared/
│   │   ├── php-extensions.env    # die Extension-Liste, einmal
│   │   ├── php-ini/              # statische INI-Anteile
│   │   └── entrypoint/
│   │       ├── entrypoint.sh     # gemeinsamer Kern (POSIX sh)
│   │       ├── lib-user.sh       # UID/GID-Angleichung
│   │       └── lib-phpini.sh     # APP_ENV-Profile und Laufzeit-INI
│   ├── base/Dockerfile
│   ├── cli/Dockerfile            # vier wirksame Zeilen auf FROM base
│   └── fpm/
│       ├── Dockerfile
│       └── fpm-pool.sh           # Pool-Konfiguration, target-spezifisch
├── compose/
│   ├── demo-stack.yml
│   ├── demo-app/                 # die Beispielanwendung des Stacks
│   └── nginx/
│       ├── nginx-defaults.env    # die Defaults, die envsubst nicht kann
│       └── templates/default.conf.template
├── .github/workflows/ci.yml
└── docs/                         # PRD, PLAN, PROGRESS, HANDOVER
```

Ein Target-Dockerfile enthält nur, was aus seinem Einsatzzweck folgt. Bei `cli`
sind das vier Zeilen: `max_execution_time=0`, `STOPSIGNAL SIGTERM`, ein
Healthcheck auf `php`/`composer` und das `CMD`. Alles andere steht in `base`.

---

## CI und Veröffentlichung

`.github/workflows/ci.yml` ersetzt die beiden bisherigen Workflows. Trigger:
Push auf `main`, Pull Requests, manuelle Auslösung und ein Zeitplan alle drei
Tage (mit Keepalive-Job gegen GitHubs 60-Tage-Abschaltung).

| Job | Inhalt |
|---|---|
| `lint` | `make test-lint`, `make test-bake` |
| `build-test` | Matrix 8.3 / 8.4 / 8.5, je `make test-all`, danach Trivy |
| `publish` | Multi-Arch-Build und Push mit SBOM- und Provenance-Attestation |

**Trivy blockiert** bei CRITICAL/HIGH **mit verfügbarem Fix** (`ignore-unfixed`).
Ein solcher Befund heißt, dass unser Image hinter dem Patchstand zurück ist — das
Gate ist also handlungsfähig. Befunde **ohne** Fix stecken im offiziellen
Basis-Image und sind von uns nicht behebbar; sie würden die Pipeline dauerhaft
rot legen und werden deshalb vollständig in die Job-Summary berichtet, statt zu
blockieren.

> ### Der Push ist gesperrt
>
> Dieses Repo hat **kein GitHub-Remote**, ist nie gepusht worden, und der
> `publish`-Job läuft nur, wenn die Repository-Variable `PUBLISH_ENABLED` auf
> `true` steht — sie existiert nicht. Kein `docker login`, kein `--push`, keine
> CI-Auslösung.
>
> Die Sperre bleibt, bis eine **Tag-Strategie** vorliegt und freigegeben ist.
> `headgent/phpcli` und `headgent/phpfpm` sind publizierte Reihen mit
> Konsumenten; der erste Push aus diesem Repo darf `:latest` und `:<ver>` nicht
> unter den laufenden Projekten austauschen. Der Vorschlag steht in
> `docs/PROGRESS.md`: zunächst nur ein Nebentag `:<ver>-next`, bis in einem
> echten Projekt gegengeprüft.

---

## Betriebsbedingungen und bekannte Eigenheiten

**Drei hadolint-Warnungen bei jedem Build sind gewollt.**
`InvalidDefaultArgInFrom` erscheint dreimal, weil `PHP_VERSION`,
`ALPINE_VERSION` und `COMPOSER_VERSION` in den `FROM`-Zeilen keinen Default haben
— genau das ist die Anforderung. Ein Default würde die `.env` überstimmen können.
Die Warnungen sind nicht abstellbar, ohne den Defekt zurückzuholen, und sie sind
**kein** Fehler.

**`make build-all` braucht Plattenplatz.** bake übersetzt die drei PHP-Versionen
**gleichzeitig**. Auf einer vollen Docker-VM endet das mit „No space left on
device". Das ist kein Designfehler, sondern eine Betriebsbedingung — im
Zweifelsfall `make build` je Version oder vorher `make build-cache-delete`.

**`make test-all` setzt `--privileged` voraus.** Die Stufe `test-uid-linux` fährt
einen `docker:28-dind`-Container hoch. Ohne diese Möglichkeit lassen sich die
übrigen zwölf Stufen einzeln aufrufen.

**Der Demo-Stack liegt auf Port 8088**, nicht auf 8080 — der ist auf
Entwicklungsrechnern häufig belegt. Der Prüflauf nutzt zusätzlich 18080.

**`nginx -t` allein prüft die Vorlage nicht.** nginx löst den Upstream-Namen
beim Laden der Konfiguration auf; ohne laufenden `fpm`-Dienst scheitert der Test
an der Namensauflösung, nicht an der Vorlage. Deshalb prüft `test-nginx` gegen
einen echten Stack.

**Zwei NOTICEs beim Start mit `--user`** stammen aus der `www.conf` des
offiziellen Basis-Images und sind rein informativ.

---

## Umstieg vom Bestand

Was Konsumenten der bisherigen Images merken werden, sobald der erste Push
freigegeben ist:

| Änderung | Wirkung |
|---|---|
| **`php-cgi` und `phpdbg` fehlen** in `headgent/phpcli` | Folge der Entscheidung, `base` auf `php:<ver>-fpm-alpine` zu stellen: dieses Image ist gemessen 16,7 MB **kleiner** als das cli-Image und trägt einen byte-gleichen PHP-CLI. Für Worker, Queue-Consumer, Cron, Composer und CI wird beides nicht gebraucht — wer `phpdbg` einsetzt, muss es wissen |
| **PHP 8.2 wird nicht mehr gebaut**, 8.5 kommt hinzu | Matrix ist 8.3 / 8.4 / 8.5 |
| **`APP_ENV` steuert die Umgebung** | Das Image bringt `APP_ENV=dev` mit. Produktionsbetrieb heißt jetzt ausdrücklich `APP_ENV=prod` — sonst ist Xdebug aktiv, und im `fpm`-Image war es das bisher nicht |
| **Die Unix-Gruppe heißt in beiden Images `appuser`** | `headgent/phpcli` nannte sie bisher `appgroup` |
| **`pcntl` ist jetzt auch im `fpm`-Image** | kostet zur Laufzeit nichts |
| **`INSTALL_DB_CLIENTS` gilt jetzt für beide Targets** | war bisher nur in `phpcli` vorhanden |
| **`headgent/nginx` wird nicht mehr gebaut** | Ersatz ist die Vorlage in diesem Repo plus das offizielle Image. Das bestehende Image bleibt in der Registry liegen, ohne Pflegezusage — es hat keine Konsumenten |
| **`headgent/phpfpm` startet wieder** | Alle drei publizierten Versionen des Bestands-Images sind startunfähig: der `chown` auf `/proc/self/fd/{1,2}` liefert Exit 0 und wirkt nicht, FPM scheitert danach am `error_log` |
| **`STOPSIGNAL` im cli-Image ist `SIGTERM`** | statt des vom fpm-Basisimage geerbten `SIGQUIT`, auf das eine pcntl-Worker-Schleife nicht hört |

`EXPOSE 9000` steht auch im cli-Image — eine geerbte Metadatenzeile ohne Wirkung,
Docker kennt kein „unexpose".

---

## Dokumentation

| Datei | Inhalt |
|---|---|
| `docs/PRD.md` | Anforderungen, Entscheidungen, Nicht-Ziele, Akzeptanzkriterien und der verifizierte Ist-Zustand des Bestands mit Fundstellen |
| `docs/PLAN.md` | Bauform, Zielstruktur, Phasen |
| `docs/PROGRESS.md` | **maßgeblich** — was jede Phase geliefert und nachgewiesen hat, jede Umsetzungsentscheidung mit Begründung, alle Befunde |
| `docs/HANDOVER.md` | Einstieg und Stand |

## Lizenz

Siehe [LICENSE](LICENSE).
