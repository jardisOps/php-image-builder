# Fortschritt — Konsolidierung des PHP-Docker-Image-Builders

## Bezug
- Handover: `docs/HANDOVER.md`
- PRD:      `docs/PRD.md`  (bestätigt)
- Plan:     `docs/PLAN.md` (freigegeben)

**Zielort (geändert 2026-07-25 auf Anordnung des Users):**
`/Users/Rolf/Development/headgent/devops/docker/php-image-builder/`
Projekt- und künftiger Repo-Name: **`php-image-builder`** (löst den Arbeitsnamen
`docker-php-builder` aus E8 ab). Diese Dokumente liegen seither unter `docs/` im
Repo und sind mitversioniert. Bestandscode unverändert unter
`devops/image/phpcli/` und `devops/image/phpfpm/`, Vorläuferdokumente unter
`devops/image/`.

## Phasen
- [x] **P1  Repo-Gerüst + konsolidierte `.env`** — abgeschlossen 2026-07-25
- [x] **P2  Gemeinsamer Entrypoint-Kern (UID/GID-Fix + APP_ENV)** — abgeschlossen 2026-07-25
- [x] **P3  `base`-Target** — abgeschlossen 2026-07-25
- [x] **P4  `cli`-Target** — abgeschlossen 2026-07-25
- [x] **P5  `fpm`-Target** — abgeschlossen 2026-07-25
- [x] **P6  `docker-bake.hcl` + Make-Targets** — abgeschlossen 2026-07-25
- [~] ~~P7  `frankenphp`-Target~~ — **entfallen 2026-07-25 (E11)**
- [x] **P8  Tests** — abgeschlossen 2026-07-25
- [x] **P9  nginx-Config als Asset** — abgeschlossen 2026-07-25
- [ ] P10 Demo-Stack
- [ ] P11 CI-Pipeline + Härtung
- [ ] P12 Doku + Abschluss

---

## P1 — abgeschlossen

### Geliefert

| Datei | Herkunft |
|---|---|
| `.env` | Zusammenführung `phpcli/src/.env` + `phpfpm/.env`, 52 Schlüssel |
| `Makefile` | Bauform beider Repos; `##@`/`##`-Hilfesystem und awk-Block unverändert, `info` im phpfpm-Stil, `help` getrennt (phpcli-Trennung) |
| `support/makefiles/docker.helper.mk` | phpfpm-Helper + `CACHE_BACKEND`-System aus `phpcli/support/makefile/docker.mk` |
| `.gitignore` | `phpcli/.gitignore`, unverändert |
| `LICENSE` | `phpfpm/LICENSE`, unverändert (MIT, Headgent GmbH) |
| `.github/CODEOWNERS` | `phpfpm/.github/CODEOWNERS`, unverändert |
| `.hadolint.yaml` | `phpfpm/.hadolint.yaml`; Kommentartext auf base/cli/fpm/frankenphp umgestellt, beide Ignores (DL3018, DL4006) samt Begründung erhalten |
| `.dockerignore` | neu (A7.5); Build-Kontext ist das Repo-Root, weil alle Targets `src/shared/` brauchen |

Verzeichnisstruktur nach `PLAN.md` angelegt, `git init -b main` ausgeführt.

### Akzeptanz — nachgewiesen

- `make info` zeigt **alle 52** `.env`-Schlüssel, `stderr` ist leer (keine
  `--warn-undefined-variables`-Warnung).
- Kein Schlüssel doppelt gepflegt (per `uniq -d` geprüft).
- **D2 aufgehoben:** nur noch `REDIS_VERSION`; `REDIS_PECL_VERSION` existiert nicht mehr.
- **D12 aufgehoben:** ein Verzeichnis `support/makefiles/` (Plural).
- **D5, D4, D7** aufgehoben: `INSTALL_DB_CLIENTS` und `XDEBUG_IDEKEY` gelten für alle
  Targets, Gruppenname `appuser` ist in der `.env` als einheitlich dokumentiert.
- **D16 vorbereitet, nicht abgeschlossen:** die `.env` pflegt `COMPOSER_VERSION=2.9.5`
  an genau einer Stelle. Der Nachweis, dass *kein Dockerfile* einen eigenen Default
  trägt (A2.4), fällt zwingend in P3–P5 — heute existiert noch kein Dockerfile.
- **`make help`** listet alle Targets in den `##@`-Sektionen.

### Umsetzungsentscheidungen (innerhalb von PRD/Plan)

1. **Profilgesteuerte Werte sind leere Override-Slots.** `XDEBUG_MODE`,
   `PCOV_ENABLED`, `OPCACHE_ENABLE`, `OPCACHE_VALIDATE_TIMESTAMPS`,
   `OPCACHE_REVALIDATE_FREQ`, `OPCACHE_JIT`, `PHP_DISPLAY_ERRORS`,
   `PHP_ERROR_REPORTING` stehen ohne Wert in der `.env`. Zwingend aus A10.2: stünde
   dort ein Wert, wäre er „explizit gesetzt" und würde das `APP_ENV`-Profil immer
   schlagen — das Profil bliebe wirkungslos. Die Werte leben ab P2 in der
   Profiltabelle. `make info` zeigt je Slot `<Profil>` oder `<wert> [Override]`.
2. **`PHP_MAX_EXECUTION_TIME` wird zu zwei Schlüsseln** `_CLI=0` und `_WEB=30`
   (begründetes Delta nach A2.5/E6, hebt D10 als bewussten Unterschied auf). Der
   Grund ist der Prozesstyp, nicht das Target — deshalb `_WEB` für fpm *und*
   frankenphp.
3. **`PHP_IMAGE_NAME` wird zu `IMAGE_NAME_CLI/_FPM/_FRANKENPHP`**; die vollen
   Registry-Referenzen entstehen abgeleitet in `docker.helper.mk`. Image-Namen
   unverändert (E2).
4. **`PHP_VERSIONS` bleibt im Makefile** (`docker.helper.mk`), `PHP_LATEST` wird per
   `$(lastword ...)` abgeleitet statt gepflegt — Plan-Optimierung 4 wörtlich.
5. **`IMAGE_DATE` ist der Versionsstring aus A1.3** und bindet alle Artefakte eines
   Laufs (`phpcli:8.4-20260725` + `phpfpm:8.4-20260725`). Es bleibt in
   `docker.helper.mk` und nicht in der `.env`, weil es abgeleitet ist; ein
   hartkodiertes Datum in der `.env` würde verrotten.
6. **Zwei Schlüssel gestrichen:** `VERSION=1.0.0` (per grep verifiziert: in
   `phpfpm` nirgends verwendet) und `PROJECT_ROOT` (gehörte zur
   `docker-compose.yml`-Bauweise, die laut Plan-Optimierung 2 durch `bake` ersetzt
   wird; kommt im Demo-Stack P10 bei Bedarf zurück). `WEBSERVER_VERSION` heißt jetzt
   `NGINX_VERSION` und dient nur noch dem Demo-Stack, da nginx kein Build-Target
   mehr ist (E9).
7. **Die Umgebung schlägt die `.env`.** Siehe Befund B1.

### Befunde aus P1

**B1 — Bestandsdefekt: dokumentierte Umgebungs-Overrides sind wirkungslos.**
In Make gewinnt ein `include`-Wert immer über eine Umgebungsvariable. Damit ist der
in `phpcli/support/makefile/docker.mk:12` dokumentierte Aufruf
`PHP_VERSION=8.3 make build` in **beiden** Bestands-Repos ohne Wirkung — dieselbe
Fehlerklasse „still wirkungslos" wie U1 und D16. Behoben: das neue `Makefile` sichert
vor dem `include` alle `.env`-Schlüssel, deren Herkunft `environment` ist, und stellt
sie danach wieder her. Gezielt auf `.env`-Schlüssel begrenzt — anders als `make -e`,
das auch Make-eigene Variablen wie `SHELL` treffen würde. Ohne diesen Griff wäre die
Vorrangregel A10.2 im Make-Pfad nicht herstellbar. Geprüft: Umgebung,
Kommandozeile, Werte mit Leerzeichen und `&`/`~`, sowie unverändertes Verhalten
ohne Override.

**B2 — FrankenPHP-Version belegt statt geraten** (Recherche 2026-07-25):
- Aktuell **1.12.6**, Release 2026-07-21. Upstream-Projekt liegt inzwischen unter
  `github.com/php/frankenphp`; die Docker-Images bleiben unter `dunglas/frankenphp`.
- Tag-Schema `dunglas/frankenphp:<ver>-php<php-ver>-<os>`, `os` ∈ `alpine`,
  `bookworm`, `trixie`; PHP 8.2–8.5. Für 8.2/8.3/8.4 liegen alle drei Varianten vor.
- `install-php-extensions` ist im Image enthalten, unterstützt Versions-Pinning
  (`redis-6.3.0`) und alle sechs PECL-Extensions unserer Reihe sowie Alpine. Damit ist
  A5.3/A2.2 mit denselben gepinnten Versionen erreichbar.
- **Worker-Mode ist eine reine ENV-Umschaltung** (`FRANKENPHP_CONFIG="worker ..."`),
  Nicht-Setzen = klassischer Modus. A5.2 ist damit erfüllt, solange das Image das
  mitgelieferte Caddyfile nicht umgeht.
- Nicht-root braucht `setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp`
  und `chown` auf `/config/caddy` + `/data/caddy`.

---

## P2 — abgeschlossen

### Geliefert

| Datei | Inhalt |
|---|---|
| `src/shared/entrypoint/entrypoint.sh` | Orchestrator, 36 Codezeilen: Benutzer angleichen → PHP-Konfiguration → Target-Ergänzungen → Übergabe. Kennt kein Target namentlich |
| `src/shared/entrypoint/lib-user.sh` | UID/GID-Angleichung (A4), struktureller Neubau nach E7, 77 Codezeilen |
| `src/shared/entrypoint/lib-phpini.sh` | `APP_ENV`-Profile, Validierung, JIT-Automatik, INI-Erzeugung (A10), 196 Codezeilen |
| `support/tests/check-phpini.sh` | 33 Prüffälle zur A10-Logik, ohne Container lauffähig |
| `support/tests/check-user-alignment.sh` | 27 Prüffälle zur UID/GID-Logik, läuft in `alpine:3.23` |

**POSIX-`sh` statt `bash`** (beide Bestands-Entrypoints nutzten `#!/bin/bash`, ohne
bash-Spezifika zu verwenden): derselbe Kern läuft damit auch in einem Image ohne
bash — relevant für die FrankenPHP-Alpine-Variante (N3).

**Target-Ergänzungen statt Kopien (A3.2):** `entrypoint.sh` sourct
`/usr/local/lib/entrypoint.d/*.sh`. Das fpm-Target legt dort in P5 seine
Pool-Erzeugung ab; der Kern bleibt unverändert. Ebenso `APP_OWNED_PATHS`, über das
ein Target zusätzliche Pfade für das Eigentums-Nachziehen (A4.3) anmeldet —
nachgewiesen in Fall 1b.

### Akzeptanz — nachgewiesen

Die drei Prüfungen sind reproduzierbar; sie müssen in allen weiteren Phasen grün
bleiben (P8 bindet sie in `test.mk` ein). Aus dem Repo-Root:

```sh
# shellcheck (lokal nicht installiert — containerisiert, ohne Eingriff ins System)
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --external-sources --source-path=src/shared/entrypoint src/shared/entrypoint/*.sh

# APP_ENV-Profile, Vorrangregel, Validierung (33 Fälle, braucht keinen Container)
bash support/tests/check-phpini.sh

# UID/GID-Angleichung (27 Fälle, braucht Linux -> alpine-Container)
docker run --rm --platform linux/amd64 \
  -v "$PWD/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
  -v "$PWD/support/tests/check-user-alignment.sh:/check.sh:ro" \
  alpine:3.23 sh /check.sh
```

- **shellcheck sauber**, Exit 0, mit `--external-sources` über alle drei Dateien.
- **33/33 Prüffälle** zur A10-Logik grün: alle drei Profile, Vorrangregel,
  Mehrfach-Xdebug-Modi, PCOV-Konflikt, 7 Validierungsabbrüche.
- **27/27 Prüffälle** zur UID/GID-Logik grün — **auf Linux**, in `alpine:3.23`:

| Fall | Nachweis |
|---|---|
| `/app` gehört 1234:1234 | IDs angeglichen, Eigentum nachgezogen (U3) |
| `/app` gehört 1234:**20** (`dialout`) | Gruppe wird sichtbar **wiederverwendet** statt still zu scheitern (**U1**) |
| `/app` gehört 1234:**100** (`users`) | ebenso (**U1**) |
| `/app` gehört **0:0**, leer | Fall wird behandelt statt übersprungen (**U2**) |
| `/app` gehört 0:0, **nicht leer** | sichtbare Warnung; Inhalte bewusst nicht rekursiv umgeschrieben |
| Ziel-UID **belegt** (`bin`, UID 1) | Prozess läuft numerisch unter der Zielkennung, `appuser` bleibt unangetastet (A4.1) |
| Start mit `--user 4711:4711` | keine Anpassung, kein Privilegienwechsel (**A4.4**) |
| `/app` fehlt / gehört schon `appuser` | kein Fehler, keine unnötige Aktion |

Damit sind **U1, U2 und U3 belegt behoben** und die drei Bedingungen aus AK4
(Host-UID ≠ 1000, belegte Ziel-GID, root-eigenes Volume) erfüllt. **Einschränkung:**
geprüft mit im Container erzeugten Verzeichnissen. Ein echtes Docker-Named-Volume
und ein Bind-Mount von einem Linux-Host bleiben für P8/P11 — der Mechanismus ist
derselbe, die Quelle der Eigentümerangabe nicht.

### Umsetzungsentscheidungen

1. **Profiltabelle** umgesetzt wie unten im Abschnitt „Profiltabelle" aufgeführt.
   Profilabhängig sind nur `XDEBUG_MODE`, `PCOV_ENABLED`,
   `OPCACHE_VALIDATE_TIMESTAMPS`, `PHP_DISPLAY_ERRORS`, `PHP_ERROR_REPORTING`;
   `OPCACHE_ENABLE=1`, `OPCACHE_REVALIDATE_FREQ=0` und `OPCACHE_JIT=1254` sind in
   allen Umgebungen gleich und stehen deshalb vor dem `case`.
2. **Keine Notwert-Ebene** (Freigabe Rolf, 2026-07-25): ein fehlender Image-Wert
   bricht den Start ab, statt hinter einem Ersatzwert unentdeckt zu bleiben.
3. **`${VAR:=wert}` statt Lookup-Tabelle** (Freigabe Rolf, 2026-07-25, angeregt durch
   `Sprengnetter/docker/src/runtime/php-entrypoint.sh:12-51`): dieses Sprachmittel
   *ist* die Vorrangregel A10.2. Ersetzt `profile_value`/`resolve_profile_keys`/
   `value_of`/`set_and_export`. Ergebnis: **kein `eval` mehr** in allen drei Dateien,
   shellcheck-Fehlalarme im strengsten Modus von 8 auf 4 halbiert, Profilunterschiede
   sichtbar im `case`. Der Umfang bleibt dabei praktisch gleich (197 → 196
   Codezeilen) — der Gewinn liegt in der Lesbarkeit, nicht in der Zeilenzahl.
   Verhaltensgleichheit belegt: dieselben 33 Prüffälle laufen vor und nach dem Umbau
   grün.
4. **Die JIT-Automatik schlägt auch einen expliziten Override.** Einzige bewusste
   Ausnahme von A10.2: ist Xdebug aktiv, wird `OPCACHE_JIT` auf `off` gesetzt, selbst
   wenn der Wert explizit gesetzt wurde — er wäre technisch wirkungslos und brächte
   genau die Warnung zurück, die A10.3 beseitigt (L-A). Der Vorgang wird gemeldet,
   nicht verschwiegen.
5. **A4.4 braucht einen Ausweichpfad für die INI:** läuft der Container unter einer im
   Image unbekannten Kennung, ist `/home/appuser/php-config` nicht beschreibbar. Dann
   weicht die INI nach `$TMPDIR/php-config` aus, eingebunden über
   `PHP_INI_SCAN_DIR="/usr/local/etc/php/conf.d:$INI_DIR"` — das Default-`conf.d` muss
   dabei ausdrücklich mit aufgeführt werden, sonst gingen die Extension-INIs verloren.

### Befund B3 — Quervergleich mit `Sprengnetter/docker`

Auf Hinweis des Users geprüft (2026-07-25), ob das Linux-UID-Problem dort schon
gelöst ist. Ergebnis:

- **Der UID-Block ist zeichengleich** mit dem der beiden Bestands-Repos
  (`src/runtime/php-entrypoint.sh:56-62`) — U1, U2 und U3 sind dort unverändert
  enthalten, inklusive `2>/dev/null || true`.
- Was das Problem dort entschärft, ist **`PUID=1001` als Build-Arg**
  (`.env.example:27`): das Image wird für **eine bekannte Zielumgebung** gebaut
  (ECS/AWS, keine Bind-Mounts mit fremder Host-UID). Für diesen Zweck ist das
  richtig und deutlich schlanker. Für `headgent/phpcli`/`phpfpm` trägt es nicht:
  publizierte Allzweck-Images treffen UID 501 (macOS), 1000 (Linux) und 1001 (CI).
- **Zwei Ideen von dort sind besser als der headgent-Bestand.** Die erste
  (`${VAR:=}`) ist in P2 übernommen, siehe Punkt 3. Die zweite betrifft P5, siehe N4.

---

## P3 — abgeschlossen

### N1 entschieden (Freigabe Rolf, 2026-07-25): Variante (a)

`base` setzt auf **`php:<ver>-fpm-alpine<alpine>`** auf, auch für das CLI-Target.
Die Entscheidung fiel auf Grundlage einer Messung, die in der Vorlage noch fehlte
und die das damalige Hauptargument gegen (a) umkehrt:

| | `php:8.3-cli-alpine3.23` | `php:8.3-fpm-alpine3.23` |
|---|---|---|
| Größe | 96,1 MB | **79,4 MB** |
| `/usr/local/bin/php` | 16 795 248 B | 16 795 248 B (byte-gleich) |
| `php-fpm` | — | ✅ |
| `php-cgi`, `phpdbg` | ✅ (je ~16 MB) | — |
| WORKDIR / CMD | `/` · `php -a` | `/var/www/html` · `php-fpm` |
| EXPOSE / StopSignal | — · default | `9000` · `SIGQUIT` |

Das fpm-Image ist **16,7 MB kleiner** und trägt einen byte-gleichen PHP-CLI. Der
in der Vorlage vermutete „Ballast" liegt umgekehrt im cli-Image (`php-cgi`,
`phpdbg`). Damit entfällt das einzige Gegenargument, und das Duplikations-Argument
für (a) — E1/A3.1 ist das Kernziel — steht allein.

**Bewusst in Kauf genommen:** `headgent/phpcli` verliert `php-cgi` und `phpdbg`.
Beide werden für Worker, Queue-Consumer, Cron, Composer und CI nicht gebraucht.
Es ist dennoch ein Delta an einem publizierten Image und in P12 in die
Release-Notiz aufzunehmen.

### Geliefert

| Datei | Inhalt |
|---|---|
| `src/base/Dockerfile` | Drei Stages (composer, build, runtime). Trägt PHP-Version, Extensions, Composer, Laufzeit-Bibliotheken, `appuser`, Entrypoint-Kern, INI-Ladereihenfolge |
| `src/shared/php-extensions.env` | Die eine Extension-Definition (A2.2), gesourct von `base` und ab P7 von `frankenphp` |
| `src/shared/php-ini/50-xdebug-defaults.ini` | Vier Xdebug-Feinjustierungen, gerettet aus `phpcli/src/xdebug.ini` — siehe Befund B4 |

### Akzeptanz — nachgewiesen

Ad-hoc gebaut mit einem Skript, das **alle** im Dockerfile deklarierten ARGs aus
der `.env` speist (kein Wert von Hand) — `docker-bake.hcl` ersetzt das in P6.
Tag `php-image-builder-base:test`, PHP 8.3, linux/arm64, Ergebnis **132 MB**.

- **Baut lokal**, Exit 0.
- **Alle 20 Extensions geladen** plus Zend OPcache, gegen `php-extensions.env`
  Stück für Stück geprüft: `bcmath curl exif gd intl mbstring mysqli pcntl
  pdo_mysql pdo_pgsql soap sockets zip dom apcu redis xdebug pcov amqp rdkafka`.
- **`pcntl` enthalten (E5, hebt D1 auf)** — im fpm-Basisimage, wo es der Bestand
  bewusst wegließ.
- **PECL-Versionen decken sich exakt mit der `.env`**: apcu 5.1.28, redis 6.3.0,
  xdebug 3.5.1, pcov 1.0.12, amqp 2.2.0, rdkafka 6.0.5.
- **Xdebug ist vollständig vorhanden** und lädt als Zend-Extension. Die
  `[Zend Modules]`-Ausgabe (`Xdebug`, `Zend OPcache`) ist **zeichengleich mit
  `headgent/phpcli:8.4` und `headgent/phpfpm:8.4`** — kein Regress; `php -m`
  listet Zend-Extensions schlicht nicht in Ladereihenfolge. Das
  `00-opcache.ini`-Muster ist unverändert übernommen.

**D16/A2.4 belegt behoben** — kein ARG trägt einen Default, beide Gegenproben:

| Gegenprobe | Ergebnis |
|---|---|
| Build ohne `COMPOSER_VERSION`/`PHP_VERSION` | Exit 1, `failed to parse stage name "php:-fpm-alpine"` |
| `php-extensions.env` ohne `RDKAFKA_VERSION` | sichtbarer Abbruch mit dem A2.4-Hinweistext |

**N2 belegt eingelöst**, beide Hälften am gebauten Image:

| Prüfung | Ergebnis |
|---|---|
| Keiner der 8 Override-Slots als `ENV` im Image | ✅ keiner gefunden |
| Die profilunabhängigen Werte als `ENV` im Image | ✅ 15 gesetzt (12 PHP-Werte + `APP_USER`, `APP_ENV`, `APP_ROOT`) |
| `base` ohne `PHP_MAX_EXECUTION_TIME` gestartet | Exit 2, klarer Abbruchtext — der Wert ist target-spezifisch und kommt aus cli/fpm |
| Mit `PHP_MAX_EXECUTION_TIME=0` gestartet | voller Durchlauf, INI erzeugt |

**AK14 im echten Image belegt** (bisher nur im Prüfskript aus P2):

| Fall | Ergebnis |
|---|---|
| `dev`, Xdebug aktiv | `opcache.jit` von `1254` auf `off`, gemeldet — **0 Warnungen** im Output (L-A behoben) |
| `XDEBUG_MODE=off` | `opcache.jit=1254`, Buffer 128M, `opcache_get_status()["jit"]["enabled"] === true` |
| `APP_ENV=prod` + `XDEBUG_MODE=debug` | sichtbarer Abbruch mit Begründung (L-F behoben) |

**Vier Prüfungen grün** (die drei aus P2, eine neu). Aus dem Repo-Root:

```sh
# hadolint (NEU in P3) — gilt für alle Dockerfiles (A7.8, hebt D15 auf)
docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" \
  hadolint/hadolint:latest hadolint --config /.hadolint.yaml - < src/base/Dockerfile

# shellcheck — ERWEITERT um php-extensions.env
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --external-sources --source-path=src/shared/entrypoint \
  src/shared/entrypoint/*.sh src/shared/php-extensions.env

bash support/tests/check-phpini.sh          # 33/33 grün
docker run --rm --platform linux/amd64 \
  -v "$PWD/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
  -v "$PWD/support/tests/check-user-alignment.sh:/check.sh:ro" \
  alpine:3.23 sh /check.sh                  # 27/27 grün
```

**Einschränkung:** gebaut und geprüft für PHP 8.3 auf linux/arm64. Die Matrix
(8.2/8.4, amd64) kommt mit P6, der Linux-Nachweis mit P11. Der Größenvergleich
mit dem Bestand (`headgent/phpcli:8.4` 158 MB, `headgent/phpfpm:8.4` 137 MB) ist
**nicht belastbar**, weil dort PHP 8.4 gebaut ist und `base` noch kein
Target-Endstand ist.

### Umsetzungsentscheidungen

1. **`php-extensions.env` trägt Namen, die `.env` trägt Versionen.** Die Datei
   führt drei Listen: `PHP_EXT_CORE` (parallel baubar), `PHP_EXT_CORE_SERIAL`
   (`dom`, das beide Bestands-Dockerfiles aus demselben Grund in einen eigenen
   `-j1`-Aufruf ziehen) und `PHP_EXT_PECL` in der Schreibweise `name-version`.
   Diese Schreibweise nehmen `pecl install` **und** `install-php-extensions`
   (B2) — deshalb genügt **eine** Liste für `base` und `frankenphp`, ohne
   Übersetzungsschicht.
2. **`PECL_NAMES` wird abgeleitet, nicht zweitgepflegt.** `docker-php-ext-enable`
   will Namen ohne Version. Statt einer zweiten Liste (A2.1-Verstoß) schneidet
   eine Schleife im Dockerfile die Version mit `${ext%-*}` ab.
3. **Keine dritte Prüfschicht für die Image-Werte.** Erwogen und verworfen: eine
   Build-Zeit-Prüfung der 12 profilunabhängigen ARGs. Der Entrypoint prüft sie
   bereits (`require_image_values`, P2), und Dockerfile-Expansion kennt `${VAR:?}`
   gar nicht — es blieb nur eine eigene `RUN`-Prüfzeile, also Doppelung für einen
   Fall, den P8 mit einem Boot-Test ohnehin abdeckt.
4. **Das `if [ -f ... ]` um den OPcache-INI-Umbenenner entfällt.** Die Datei ist
   im offiziellen Image nachweislich vorhanden (verifiziert 2026-07-25). Fiele sie
   je weg, soll der Build sichtbar scheitern, statt still ohne OPcache-Vorrang zu
   bauen — dieselbe Linie wie in P2.
5. **`PHP_MAX_EXECUTION_TIME` steht bewusst nicht in `base`.** Es ist der einzige
   der 13 Pflichtwerte, der dem Einsatzzweck folgt (A2.5, begründetes Delta zu
   D10). Folge: `base` allein ist nicht startfähig — das ist richtig so, es wird
   nicht publiziert. Tests gegen `base` brauchen `--entrypoint php` oder ein
   gesetztes `PHP_MAX_EXECUTION_TIME`.
6. **`bash` bleibt im Image**, obwohl der Entrypoint seit P2 POSIX-`sh` ist:
   `make shell` und die Login-Shell von `appuser` setzen sie voraus. Sie zu
   entfernen wäre eine Verhaltensänderung an publizierten Images ohne Auftrag.
7. **`SC2086` wird inline ignoriert, nicht global.** Zwei Stellen (`$PHP_EXT_*`,
   `$PKGS`) brauchen die Wortaufspaltung — gequotet bekäme
   `docker-php-ext-install` die ganze Liste als ein Argument. Ein Eintrag in
   `.hadolint.yaml` würde die Ausnahme auf alle künftigen Dockerfiles ausdehnen;
   `# hadolint ignore=SC2086` mit Begründung an der Fundstelle nicht.
8. **Der Entrypoint wird in `base` gesetzt, `CMD`/`EXPOSE`/`STOPSIGNAL`/
   `HEALTHCHECK` nicht.** Der Entrypoint ist für alle Targets derselbe, die vier
   anderen folgen dem Einsatzzweck und kommen in P4/P5.

### Befunde aus P3

**B4 — nicht erfasste Drift: vier Xdebug-Einstellungen nur in phpcli.**
`phpcli/src/xdebug.ini:12-15` trägt `xdebug.max_nesting_level=256`,
`var_display_max_depth=3`, `var_display_max_children=128`,
`var_display_max_data=512`. In `phpfpm` gibt es sie nicht; im PRD sind sie
weder in D1–D16 noch in L-A–L-G erfasst. Bei einer reinen Konsolidierung wären
sie still verschwunden. Aufgelöst nach A2.5/E6 zugunsten der reicheren Variante:
als `conf.d/50-xdebug-defaults.ini` in `base`, damit `phpcli` sein Verhalten
behält und `phpfpm` es dazugewinnt. Bewusst **kein** neuer `.env`-Schlüssel — es
ist Ausgabe-Feinjustierung, kein Betriebsparameter. Wirksamkeit im gebauten Image
geprüft (`php -i`: alle vier Werte gesetzt). Die Nummer 50 stellt sicher, dass die
zur Laufzeit erzeugte `99-runtime-config.ini` sie schlagen kann.

**B5 — `phpcli/src/xdebug.ini` überschrieb die generierte Extension-INI.**
Der Bestand kopierte die Datei nach `conf.d/docker-php-ext-xdebug.ini` und
ersetzte damit, was `docker-php-ext-enable xdebug` erzeugt. Das neue `base` tut
das nicht: die generierte INI bleibt unangetastet, die vier Werte kommen in einer
eigenen Datei daneben. Damit geht nichts verloren, falls `docker-php-ext-enable`
künftig mehr als die `zend_extension`-Zeile schreibt.

**B6 — `base` erbt drei FPM-Metadaten, die im cli-Target folgenlos bleiben.**
Aus dem fpm-Basisimage kommen `EXPOSE 9000`, `STOPSIGNAL SIGQUIT` und
`conf.d/docker-fpm.ini` (`fastcgi.logging = Off`) plus `/usr/local/etc/php-fpm.d/*`.
Das `EXPOSE` lässt sich nicht zurücknehmen (Docker kennt kein „unexpose") und
bleibt eine Metadatenzeile ohne Wirkung. `STOPSIGNAL` **muss P4 auf `SIGTERM`
korrigieren** — SIGQUIT ist für FPM richtig, für einen Worker falsch. Die
FPM-INI und die Pool-Dateien wirken nur im FastCGI-SAPI und sind im cli-Image
unbenutzt.

**B7 — BuildKit warnt bei jedem Build dreimal `InvalidDefaultArgInFrom`.**
Das ist die unmittelbare Folge von A2.4: `ARG PHP_VERSION` ohne Default macht
`php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION}` für den Parser vorerst ungültig.
Die Warnung verschwindet nur, wenn man Defaults setzt — genau das ist verboten.
Der Bestand `phpfpm` hat dasselbe Muster aus demselben Grund. Nicht behebbar,
bewusst hingenommen; in P12 in die README aufzunehmen, damit sie niemand als
Fehler liest.

---

## P4 — abgeschlossen

### Vorbemerkung: warum `cli` trotz allem ein eigenes Target bleibt

Auf die Frage des Users geprüft, ob das `cli`-Target entfallen kann, nachdem
`base` (= fpm-Image) bereits einen vollwertigen PHP-CLI enthält. **Technisch ja
— fachlich nein.** `src/cli/Dockerfile` besteht nach P3 nur noch aus vier
wirksamen Zeilen, und drei davon sind Werte, die ein Image nur **einmal** tragen
kann und die zwischen Worker- und Request-Betrieb **entgegengesetzt** sind:

| | cli (Worker) | fpm (Request) |
|---|---|---|
| `max_execution_time` | `0` — ein Limit killt langlaufende Consumer | `30` — begrenzt hängende Requests |
| `STOPSIGNAL` | `SIGTERM` | `SIGQUIT` (FPMs graceful shutdown) |
| `HEALTHCHECK` | `php --version && composer --version` | FastCGI-Ping auf Port 9000 |

Der Healthcheck ist der harte Punkt: würde `headgent/phpcli` aus dem fpm-Target
getaggt, bekäme jeder CLI-Worker den FastCGI-Ping — der schlägt fehl, weil kein
FPM lauscht, und der Container gälte dauerhaft als `unhealthy`. Das würden
Konsumenten sofort merken, was E2 ausschließt („Konsumenten dürfen nichts
merken") und was Nicht-Ziel N4 (keine Migration der Konsumenten-Projekte)
verbietet.

Die Vereinfachung ist bereits eingetreten, nur an anderer Stelle: vorher waren es
zwei vollständige Dockerfiles mit je eigener Extension-Liste, eigenem Entrypoint
und driftenden Werten; jetzt ist `cli` ein Vier-Zeiler auf gemeinsamer Basis. Die
zwei Artefakte kosten praktisch nichts mehr — gleicher `base`-Layer, ein
Metadaten-Layer obendrauf, **0 MB Größenunterschied** (beide 132 MB), Sekunden
Build-Zeit im selben `bake`-Lauf.

Eine Reduktion auf **ein** publiziertes Image bliebe machbar, wäre aber eine
PRD-Änderung (E2, N4, AK3) samt Umstellung der Konsumentenprojekte — auf
ausdrückliche Anweisung, nicht nebenbei.

### Geliefert

| Datei | Inhalt |
|---|---|
| `src/cli/Dockerfile` | `FROM base` plus vier wirksame Zeilen: `PHP_MAX_EXECUTION_TIME`, `STOPSIGNAL`, `HEALTHCHECK`, `CMD` |

### Akzeptanz — nachgewiesen

Gebaut mit demselben Skript wie P3, zusätzlich mit
`--build-context base=docker-image://php-image-builder-base:test` — das bildet
nach, was `bake` über `contexts = { base = "target:base" }` tut (A1.2).

- **`FROM base` löst auf**, Build Exit 0 in unter einer Sekunde (nur
  Metadaten-Layer). Ergebnis **132 MB — identisch mit `base`**.
- **Extensions vollständig**: dieselben 20 plus Zend OPcache.
- **Entrypoint aus P2 läuft durch**, ohne dass eine ENV von außen nötig wäre —
  der P3-Abbruch („`PHP_MAX_EXECUTION_TIME` ist nicht gesetzt") ist damit gezielt
  aufgehoben. Ausgabe: JIT-Automatik meldet sich, `APP_ENV=dev`-Zeile, dann
  `php --version` mit `Zend OPcache v8.3.32` und `Xdebug v3.5.1`.
- `max_execution_time=0` im laufenden Container geprüft.
- `StopSignal=SIGTERM` — **N5/B6 eingelöst**, das geerbte SIGQUIT ist korrigiert.
- **HEALTHCHECK real geprüft**: Container erreicht `healthy` nach 8 s, letzter
  Lauf Exit 0.
- `composer --version` → **2.9.5**, deckungsgleich mit der `.env`.
- **hadolint sauber** für `src/base/Dockerfile` **und** `src/cli/Dockerfile`
  (je Exit 0).

**Zusätzlich erbracht — eine Einschränkung aus P2 ist damit aufgehoben:**
A4.2/U2 wurde erstmals an einem **echten Docker-Named-Volume** geprüft, nicht
nur an einem im Container erzeugten Verzeichnis. Ein frisch angelegtes Volume
kommt als `root:root`; der Container lief anschließend als
`uid=1000(appuser) gid=1000(appuser)`, `/app` gehörte `appuser:appuser` und war
beschreibbar. Offen bleibt aus AK4 nur noch der Bind-Mount von einem Linux-Host
mit fremder UID (P11).

### Umsetzungsentscheidungen

1. **`ARG PHP_MAX_EXECUTION_TIME_CLI` → `ENV PHP_MAX_EXECUTION_TIME`.** Der
   `.env`-Schlüssel trägt das Suffix, damit beide Werte nebeneinander gepflegt
   werden können (P1-Entscheidung 2); im Image heißt er wieder wie die
   PHP-Einstellung, weil `lib-phpini.sh` genau diesen Namen prüft und schreibt.
2. **`DL3006` wird inline ignoriert, nicht global.** hadolint verlangt bei
   `FROM base` ein explizites Tag — ein Fehlalarm, weil `base` ein benannter
   Build-Context ist und kein Registry-Image. Ein Eintrag in `.hadolint.yaml`
   würde ein echtes ungetaggtes `FROM` in einem anderen Dockerfile (etwa
   frankenphp) durchgehen lassen; der Inline-Ignore mit Begründung nicht. Gleiche
   Linie wie P3-Entscheidung 7. **P5 wird denselben Ignore brauchen.**
3. **`WORKDIR` und `LABEL maintainer` werden nicht wiederholt** — beide werden
   von `base` geerbt. Wiederholung wäre Doppelpflege (A2.1).

### Befund aus P4

**B8 — D16 ist im Feld unsichtbar, weil das Makefile den Build-Arg übergibt.**
`headgent/phpcli:8.4` trägt Composer **2.9.5**, nicht den hartkodierten
Dockerfile-Default 2.9.3 — belegt durch `docker run --entrypoint composer
headgent/phpcli:8.4 --version`. Grund:
`phpcli/support/makefile/docker.mk:43` übergibt `--build-arg COMPOSER_VERSION`
explizit, wodurch der Default nie greift. Das deckt sich mit dem PRD, das D16
ausdrücklich als **latenten** Defekt führt: er schlägt erst zu, wenn jemand ohne
Build-Arg baut (direkter `docker build`, CI-Pfad ohne Makefile, oder wenn die
Zeile aus dem Makefile verschwindet). Konsequenz für die Beweisführung: der
Nachweis der Behebung ist die **Build-Gegenprobe** aus P3 (Exit 1 statt stillem
Fallback), nicht ein Versionsunterschied zwischen altem und neuem Image.

---

## P5 — abgeschlossen

### N4 entschieden (2026-07-25): Variante (b) — und zwar zwingend

Die Vorlage führte N4 als Abwägung „Härtung gegen Einfachheit". Beim Verifizieren
stellte sich heraus, dass es **keine Abwägung ist: Variante (a) funktioniert
nicht** — weder im Bestand noch in unserem P2-Kern. Siehe Befund B9.

`fpm` startet damit als root und lässt **FPM selbst** auf die Worker-Kennung
wechseln (`user =` in der Pool-Config). Der Master bleibt root, die Worker laufen
unprivilegiert — das von PHP vorgesehene Betriebsmodell, das auch das offizielle
`php:X-fpm`-Image nutzt (`user = www-data` in `www.conf`).

**Sicherheitseinordnung:** der Master parst die Konfiguration, öffnet Socket und
Logs und verwaltet Worker — er verarbeitet **keine Requests**. Der gesamte
Angriffskontakt liegt in den Workern, und die sind unprivilegiert. Der
Härtungsgewinn von (a) wäre gewesen, einen Prozess ohne Angreiferkontakt
zusätzlich zu entprivilegieren.

### Geliefert

| Datei | Inhalt |
|---|---|
| `src/fpm/Dockerfile` | `FROM base` plus Request-Zeitlimit, `FPM_PM_*`, `fcgi`, Pool-Symlink, FastCGI-Healthcheck |
| `src/fpm/fpm-pool.sh` | Target-Ergänzung (A3.2), landet als `/usr/local/lib/entrypoint.d/10-fpm-pool.sh` |
| `src/shared/entrypoint/entrypoint.sh` | **geändert**: der wirkungslose `chown` auf `/proc/self/fd/{1,2}` ist entfernt (B9) |

### Akzeptanz — nachgewiesen

Alle drei Images bauen und sind **je 132 MB** — `fpm` kostet gegenüber `base`
nichts Messbares.

| Prüfung | Ergebnis |
|---|---|
| Container startet | `running`, `NOTICE: ready to handle connections` |
| Prozessmodell | `root` Master (PID 1), **2 Worker als `appuser`** (= `pm.start_servers=2`) |
| **FPM-Ping antwortet** | Healthcheck `healthy` nach **4 s**, Exit 0 |
| **Pool-Config erzeugt** | vollständig, alle sechs `FPM_PM_*`-Werte aus der `.env` wirksam |
| Echter FastCGI-Request | `FASSUNG-1 uid=1000 jit= vt=1` — ein Worker führt PHP aus, läuft als appuser, die Entrypoint-INI greift |
| A4.4 (`--user 1000:1000`) | läuft; unsere Config lässt `user`/`group` korrekt weg (nur `listen = 9000`) |
| A4.2/U2 (frisches Named Volume) | `running`, `healthy`, `/app` gehört `appuser`, beschreibbar |

**AK15 belegt — mit Gegenprobe.** Das Kriterium („im `dev`-Profil bemerkt auch
das FPM-Target Code-Änderungen ohne Container-Neustart", behebt L-C) war bisher
nirgends nachgewiesen:

| Profil | `validate_timestamps` | Aufruf 1 | Aufruf 2 | nach Dateiänderung | OPcache |
|---|---|---|---|---|---|
| `dev` | `1` | FASSUNG-1 | FASSUNG-1 | **FASSUNG-2** ✅ | 1 Skript, 1 hit |
| `prod` | `0` | FASSUNG-1 | FASSUNG-1 | **FASSUNG-1** ✅ | 1 Skript, 2 hits |

Die prod-Zeile ist die eigentliche Beweiskraft: sie zeigt, dass der Cache
tatsächlich greift und dev die Änderung nicht bloß deshalb sieht, weil gar nichts
gecacht wurde. Zur Fallstricke-Warnung bei künftigen Tests siehe Befund B11.

**Alle Prüfungen grün**, shellcheck jetzt inklusive `fpm-pool.sh`:

```sh
# hadolint — für alle DREI Dockerfiles je Exit 0
for f in src/base/Dockerfile src/cli/Dockerfile src/fpm/Dockerfile; do
  docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" \
    hadolint/hadolint:latest hadolint --config /.hadolint.yaml - < "$f"; done

# shellcheck — ERWEITERT um src/fpm/fpm-pool.sh
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --external-sources --source-path=src/shared/entrypoint \
  src/shared/entrypoint/*.sh src/shared/php-extensions.env src/fpm/fpm-pool.sh

bash support/tests/check-phpini.sh          # 33/33 grün
docker run --rm --platform linux/amd64 \
  -v "$PWD/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
  -v "$PWD/support/tests/check-user-alignment.sh:/check.sh:ro" \
  alpine:3.23 sh /check.sh                  # 27/27 grün
```

### Umsetzungsentscheidungen

1. **Die Worker-Kennung wird aus `RUNTIME_USER` abgeleitet, nicht als „appuser"
   angenommen.** `lib-user.sh` hinterlässt dort das Ergebnis seiner Angleichung,
   und die Ergänzung übersetzt es in die Pool-Direktiven:
   - `appuser` → `user = appuser`, `group = <numerische GID>`. Numerisch, weil
     nach einer Angleichung an eine belegte Ziel-GID die Gruppe `appuser` noch
     mit ihrer alten GID existiert — derselbe Grund wie bei `appuser_owner()`.
   - `1:1000` (Ziel-UID war belegt) → beide Werte numerisch.
   - leer (Start per `--user`, A4.4) → `user`/`group` entfallen ganz, sonst
     verwürfe FPM sie mit einer NOTICE.
2. **`/run/php-fpm` wird nicht mehr angelegt.** Der Bestand legte das Verzeichnis
   an und zog es im chown nach, obwohl der Pool über TCP `listen = 9000` läuft und
   `daemonize = no` gesetzt ist — es liegt dort weder Socket noch PID-Datei. Der
   `APP_OWNED_PATHS`-Mechanismus aus P2 bleibt und wird voraussichtlich in P7
   gebraucht (`/config/caddy`, `/data/caddy`, B2). Sollte P8 oder P10 zeigen, dass
   das Verzeichnis doch nötig ist, kommt es mit einer Zeile zurück.
3. **`www.conf` des offiziellen Images bleibt unangetastet.** Unsere
   `zz-fpm-runtime.conf` wird als letzte gelesen und überschreibt die relevanten
   Werte — im Regelbetrieb nachgewiesen (Worker liefen als `appuser`, nicht als
   `www-data`). Siehe B10 für die Nebenwirkung im `--user`-Fall.
4. **`STOPSIGNAL` wird nicht angefasst.** Das geerbte `SIGQUIT` ist FPMs Signal
   für den graceful shutdown und hier richtig — im Gegensatz zu `cli`, wo P4 es
   auf `SIGTERM` korrigieren musste.

### Befunde aus P5

**B9 — Bestandsdefekt: `headgent/phpfpm` ist startunfähig, in allen drei
Versionen.** Belegt am 2026-07-25 durch Starten der publizierten Images:

| Tag | ohne TTY | mit TTY | mit `-v /app` | mit `--user` |
|---|---|---|---|---|
| `headgent/phpfpm:8.2` | `exited` | `exited` | — | — |
| `headgent/phpfpm:8.3` | `exited` | `exited` | — | — |
| `headgent/phpfpm:8.4` | `exited` | `exited` | `exited` | **`running`** |

```
ERROR: failed to open error_log (/proc/self/fd/2): Permission denied (13)
ERROR: failed to post process the configuration
ERROR: FPM initialization failed
```

**Ursache:** der Griff `chown "$APP_USER:$APP_USER" /proc/self/fd/{1,2}`
(`phpfpm/src/php/entrypoint.sh:98`) liefert **Exit 0** und wirkt trotzdem nicht.
`/proc/self/fd/2` ist ein Symlink auf eine anonyme Pipe (`pipe:[...]`); das
pipefs nimmt die Eigentumsänderung nicht an. Das danebenstehende `|| true`
verschluckt nichts — es gibt gar keinen Fehler. Dieselbe Fehlerklasse „still
wirkungslos" wie U1, D16 und B1. Der Kommentar im Bestand (`:92-96`) behauptet
ausdrücklich das Gegenteil.

**Auch unser P2-Kern war betroffen.** Ich hatte den Griff samt Begründung
übernommen, ohne die Begründung zu prüfen — `docker run
php-image-builder-cli:test php-fpm` zeigte exakt dasselbe Verhalten. Die 27
UID-Prüffälle konnten das nicht fangen: sie prüfen die ID-Angleichung, starten
aber kein FPM. Der Griff ist in P5 aus `entrypoint.sh` entfernt; für `cli` und
`frankenphp` war er ohnehin folgenlos, weil dort niemand ein `error_log` neu
öffnet.

**Kein Ausweg über FPM-Optionen:** `php-fpm --force-stderr` hilft nicht, weil FPM
das `error_log` bereits beim Config-Post-Processing öffnet, vor jeder Logausgabe.
Getestet, scheitert identisch.

**Auswirkung auf laufende Projekte: keine.** Der User hat bestätigt, dass derzeit
nichts gegen `headgent/phpfpm` läuft — was erklärt, warum der Defekt nie auffiel.
Das neue Image behebt ihn.

**B10 — zwei fremde NOTICEs im `--user`-Fall.** Wird der Container per `--user`
gestartet, meldet FPM `'user' directive is ignored when FPM is not running as
root` — zweimal. Die Meldungen stammen **nicht** aus unserer Pool-Config (die
lässt die Direktiven dann korrekt weg, geprüft), sondern aus `www.conf:28-29` des
offiziellen Images, das dort `user = www-data` pflegt. Informativ und korrekt;
`www.conf` wird bewusst nicht angetastet (Umsetzungsentscheidung 3).

**B11 — Testfallstrick: `opcache.file_update_protection`.** Ein erster
AK15-Versuch schien zu zeigen, dass auch `prod` Code-Änderungen bemerkt. Das war
ein Messfehler: OPcache cacht per Default keine Datei, die in den letzten **2
Sekunden** geändert wurde (`opcache.file_update_protection`). Alle Testdateien
lagen darunter, es wurde nie etwas gecacht (`num_cached_scripts=0`, `hits=0`,
`misses=6`) — folglich lieferte auch `prod` immer die neue Fassung. Mit 3 s
Wartezeit nach jedem Schreiben ist das Bild eindeutig (Tabelle oben). **Für P8
verbindlich:** jeder OPcache-Test muss diese Frist abwarten und
`num_cached_scripts`/`hits` mitprüfen, sonst misst er nichts.

---

## Versions-Matrix umgestellt: 8.2 raus, 8.5 rein (Anweisung Rolf, 2026-07-25)

`PHP_VERSIONS` ist jetzt **8.3 / 8.4 / 8.5** (vorher 8.2 / 8.3 / 8.4). `PHP_LATEST`
leitet daraus 8.5 ab und treibt damit den `:latest`-Tag. Die Umstellung hat zwei
echte Baufehler aufgedeckt, die beide **nicht** an PHP 8.5 lagen, sondern an
überflüssigen Bauschritten, die der Bestand mitschleppte.

### Nachweis — base, cli und fpm gegen alle drei Versionen

| | 8.3 | 8.4 | 8.5 |
|---|---|---|---|
| `base` baut | ✅ **130 MB** | ✅ 135 MB | ✅ 145 MB |
| PHP-Fassung | 8.3.32 | 8.4.23 | **8.5.8** |
| alle 20 Extensions | ✅ | ✅ | ✅ |
| Zend OPcache aktiv | ✅ | ✅ | ✅ |
| PECL-Pins aus der `.env` | ✅ alle sechs | ✅ | ✅ |
| conf.d-Reihenfolge | `00-opcache` → `50-xdebug-defaults` → `99-runtime-config` | ebenso | `50-xdebug-defaults` → `99-runtime-config` (OPcache statisch, s.u.) |

`cli` und `fpm` gegen 8.5 gebaut: `PHP 8.5.8 (cli)`, FPM `healthy` mit 2 Workern
als `appuser`. hadolint ×3, shellcheck, 33/33 und 27/27 grün.

Die gepinnten PECL-Versionen tragen **unverändert** bis 8.5 — apcu 5.1.28,
redis 6.3.0, xdebug 3.5.1, pcov 1.0.12, amqp 2.2.0, rdkafka 6.0.5. Eine
versionsabhängige Pin-Struktur ist nicht nötig. Die Notiz in
`phpcli/.claude/CLAUDE.md` („PHP 8.5 support planned once PECL extensions have
stable releases") ist damit überholt.

### B12 — `curl`, `dom` und `mbstring` wurden überflüssig nachgebaut

Alle drei sind im offiziellen `php:X-fpm-alpine` **statisch einkompiliert** —
geprüft für 8.3 und 8.5: `php -m` meldet sie ohne unser Zutun, und keine der drei
erzeugt eine `conf.d`-INI. Beide Bestands-Dockerfiles bauten sie dennoch nach;
das Ergebnis wanderte ungenutzt in den Müll.

Ab **8.5 bricht `dom` den Build**: `ext/dom` bringt dort einen HTML5-Parser mit,
der lexbor voraussetzt (`fatal error: lexbor/html/parser.h: No such file or
directory`). Statt `lexbor-dev` als Build-Abhängigkeit nachzurüsten, entfällt der
überflüssige Bauschritt. `PHP_EXT_CORE` schrumpft von 14 auf **11** Einträge, und
`PHP_EXT_CORE_SERIAL` samt der `-j1`-Sonderbehandlung entfällt **ganz** — `dom`
war ihr einziger Eintrag. Nebeneffekt: das 8.3-Image ist 2 MB kleiner als vorher.

### B13 — `docker-php-ext-enable opcache` war immer schon überflüssig

OPcache ist im offiziellen Image bereits aktiv: bis 8.4 über die mitgelieferte
`docker-php-ext-opcache.ini`, ab 8.5 **statisch einkompiliert** (keine
`opcache.so` mehr, keine INI, `php -m` meldet `Zend OPcache` trotzdem). Bei 8.5
bricht der Aufruf deshalb ab: `error: 'opcache' does not exist`. Der Aufruf ist
ersatzlos gestrichen.

**Folge für den INI-Umbenenner:** `mv docker-php-ext-opcache.ini 00-opcache.ini`
braucht ab 8.5 eine Bedingung, weil die Datei dort nicht existiert. Damit kehrt
das `if [ -f ... ]` zurück, das P3-Entscheidung 4 bewusst entfernt hatte — aber
**nicht** in seiner alten, wortlosen Form: der `else`-Zweig prüft jetzt
ausdrücklich `extension_loaded("Zend OPcache")` und lässt den Build scheitern,
wenn OPcache weder als INI noch statisch da ist. P3-Entscheidung 4 gilt insoweit
korrigiert — die Bedingung war berechtigt, nur ihre Begründung im Bestand war es
nicht.

Dass die Ladereihenfolge bei 8.5 ohne `00-opcache.ini` stimmt, ist kein Zufall:
eine statisch einkompilierte zend_extension ist immer vor jeder dynamisch
geladenen aktiv. Das Problem ist gelöst, nicht verschoben.

### Noch nicht nachgezogen

- ~~**`amd64` ist weiterhin ungeprüft.**~~ — **in P6 nachgeholt**, siehe dort.
- Die apk-Build-Abhängigkeiten `curl-dev` und `oniguruma-dev` werden seit B12
  vermutlich nicht mehr gebraucht (sie dienten curl bzw. mbstring). Sie liegen in
  der Build-Stage und wirken sich nicht auf das Ergebnis aus; ein Rückbau wäre
  Kosmetik und braucht je einen Build-Test. Vorgemerkt für P12.

---

## P6 — abgeschlossen

### Geliefert

| Datei | Inhalt |
|---|---|
| `docker-bake.hcl` | **neu.** Matrix über `PHP_VERSIONS`, drei Targets, 35 Build-Args an genau einer Stelle |
| `support/makefiles/docker.build.local.mk` | **neu.** `build`, `build-all`, `bake-print` — dünne Wrapper um `bake --load` |
| `support/makefiles/docker.build.push.mk` | **neu.** `push`, `push-all` (multi-arch, `--push`, Attestations), `.check-docker-login`. **Geschrieben, nie ausgeführt** (N6) |
| `support/makefiles/docker.helper.mk` | **geändert:** `PLATFORMS_CSV` — `bake` will die Plattformen kommasepariert, gepflegt sind sie leerzeichensepariert |
| `Makefile` | **geändert:** `include` der beiden neuen Module |
| `.gitignore` | **geändert:** `.buildx-cache/` (Ziel von `CACHE_BACKEND=local`, war bisher nur in `.dockerignore`) |

Die vier duplizierten `--build-arg`-Blöcke des Bestands sind damit weg: dieselben
~35 Zeilen standen dort in `phpfpm-build`, `phpfpm-build-all`, `phpfpm-push` und
`phpfpm-push-all` nebeneinander (Plan-Optimierung 1). Jetzt steht jedes Build-Arg
einmal in der HCL; die vier Make-Targets tragen zusammen **keine** einzige.

### Akzeptanz — nachgewiesen

**AK1 / A1.2 — ein Lauf baut alles.** `make build-all` erzeugte in **einem**
`bake`-Aufruf sechs Images unter **14 Tags**, Exit 0:

| | 8.3 | 8.4 | 8.5 |
|---|---|---|---|
| `cli` | 128 MB · 8.3.32 | 134 MB · 8.4.23 | 145 MB · 8.5.8 |
| `fpm` | 128 MB · healthy nach 6 s | 134 MB · healthy nach 6 s | 146 MB · healthy nach 6 s |
| 20 Extensions | ✅ 20/20 | ✅ 20/20 | ✅ 20/20 |
| PECL-Pins aus der `.env` | ✅ | ✅ | ✅ alle sechs unverändert |

`:latest` zeigt auf **8.5.8** (= `PHP_LATEST`), FPM-Worker laufen in allen drei
Fassungen als `appuser` (2 = `pm.start_servers`).

**A1.3 — ein Versionsstring treibt alle Tags.** Jedes publizierte Artefakt trägt
`:<ver>` **und** `:<ver>-$(IMAGE_DATE)`; `:latest` nur die höchste Version:

```
phpcli:8.3  phpcli:8.3-20260725     phpfpm:8.3  phpfpm:8.3-20260725
phpcli:8.4  phpcli:8.4-20260725     phpfpm:8.4  phpfpm:8.4-20260725
phpcli:8.5  phpcli:8.5-20260725     phpfpm:8.5  phpfpm:8.5-20260725
phpcli:latest                       phpfpm:latest
```

Gegenprobe für den reproduzierbaren Re-Tag: `IMAGE_DATE=20991231 make bake-print`
setzt das Datum in **allen** Tags beider Images gleichzeitig um.

**Die drei Vorgaben aus P3–P5 eingelöst**, belegt an `bake --print`:

| Vorgabe | Nachweis |
|---|---|
| `contexts = { base = "target:base" }` (A1.2) | je Version aufgelöst: `cli-8-4` → `target:base-8-4` |
| `base` nicht in der Default-Gruppe | `default` = `["cli","fpm"]`; `base-*` ohne Tag, `output: cacheonly` |
| ARG-Zahlen je Target | `base` **27**, `cli` 1, `fpm` 7 — siehe Befund B14 |

**amd64 erstmals gebaut** — die letzte offene Einschränkung aus P3–P5:

| Prüfung | Ergebnis |
|---|---|
| `make build BUILD_PLATFORM=linux/amd64` | Exit 0 in **6:58** (emuliert auf arm64-Host) |
| Image-Metadaten | `amd64/linux` für cli **und** fpm |
| `uname -m` im Container | `x86_64` |
| Extensions | 20/20, Xdebug 3.5.1, Zend OPcache 8.3.32 |
| fpm | `healthy` nach 6 s, zwei Worker als `appuser` |

**Vier Prüfungen grün** gegen den Endstand (hadolint ×3 Exit 0, shellcheck Exit 0,
33/33, 27/27). Die Aufrufe sind unverändert; `docker-bake.hcl` und die `.mk`-Dateien
fallen unter keinen der vier Prüfer.

**Einschränkung:** `--push` ist **nicht** gelaufen (N6). Geprüft wurde die
erzeugte Kommandozeile per `make -n push` — Plattformen, Attestations und
Tag-Satz stehen korrekt, ausgeführt wurde sie nicht.

### Umsetzungsentscheidungen

1. **`bake` liest die `.env` nicht selbst** (belegt 2026-07-25 an einem
   Minimalbeispiel: eine `.env` im Arbeitsverzeichnis blieb wirkungslos, der
   HCL-Default gewann). Der einzige Weg der Werte ist deshalb der `export` des
   Makefiles — und damit gilt die Vorrangregel A10.2 samt Befund B1
   durchgehend bis ins Build-Arg. `PHP_VERSION=8.5 make build` wirkt.
2. **`args = { X = null }` vererbt *nicht* aus der Umgebung.** Naheliegend, hätte
   die HCL um 35 Zeilen verkürzt — und ist falsch: geprüft mit und ohne gesetzte
   Umgebungsvariable, in beiden Fällen **verschwindet das Arg ganz** aus der
   aufgelösten Definition. Deshalb trägt die Datei 35 ausgeschriebene
   `variable`-Blöcke. Der Fehler wäre stumm gewesen, hätte A2.4 ihn nicht in einen
   sichtbaren Build-Abbruch verwandelt.
3. **Kein `variable` trägt einen Default.** Dieselbe Regel wie in den Dockerfiles
   und aus demselben Grund: ein Default in der HCL wäre **D16 an neuer Stelle**.
   Die Absicherung ist durchgehend — ein leeres `PHP_VERSION` bricht den Build ab,
   ein leerer Laufzeitwert den Containerstart, weil `require_image_values` mit
   `${VAR:?}` arbeitet und das auch bei *leer* greift, nicht nur bei *ungesetzt*.
4. **Eine Matrix-Mechanik für beide Fälle.** `build-all` nimmt `PHP_VERSIONS` wie
   es ist, `build` setzt es auf die eine `PHP_VERSION` der `.env`. Kein zweiter
   Codepfad, keine Fallunterscheidung in der HCL — der Unterschied ist eine Liste.
5. **Die Plattform steht nicht in der HCL.** Sie kommt von außen: lokal über
   `BUILD_PLATFORM` (leer = Host), beim Push über `PLATFORMS_CSV`. Stünde sie in
   der HCL, könnte `--load` nicht mehr funktionieren (Docker lädt keine
   Multi-Plattform-Images), und der amd64-Nachweis oben wäre ohne Registry nicht
   führbar gewesen.
6. **Keine Make-Targets je Image, sondern `BAKE_TARGETS`.** Der Bestand hatte
   `phpfpm-build`/`nginx-build`; mit drei bis vier Targets würde das eine Zeile je
   Target und Betriebsart kosten. `make build BAKE_TARGETS=fpm` leistet dasselbe,
   und **P7 muss an den Make-Modulen nichts ändern** — `frankenphp` wird allein
   durch seinen Eintrag in der HCL bedienbar.
7. **Die Abnahme-Builds liefen unter `DOCKER_HUB=php-image-builder-test`** (bzw.
   `-amd64`). Mit dem echten Namen hätten sie die lokal liegenden
   `headgent/phpcli:8.3|8.4` und `headgent/phpfpm:*` überschrieben — genau die
   Referenzkopien der publizierten Images, deren Unversehrtheit weiter unten
   belegt ist. Nebeneffekt: der Override-Weg aus Entscheidung 1 ist damit noch
   einmal im scharfen Lauf bestätigt.
8. **Das Ad-hoc-Build-Skript aus P3/P4 ist abgelöst** und die damit erzeugten
   Test-Images sind entfernt. `bake` löst `--build-context` nativ auf.

### Befunde aus P6

**B14 — die ARG-Zahl im Handover war falsch: `base` hat 27 ARGs, nicht 21.**
Die Vorgabe aus P5 (`docs/PROMPT-NEUER-KONTEXT.md`, „base 21") ist beim Nachzählen
im Dockerfile nicht haltbar: 3 global vor den `FROM`-Zeilen + 6 in der
Build-Stage + 18 in der Runtime-Stage = **27**, alle verschieden. `cli` 1 und
`fpm` 7 stimmen. Die HCL ist gegen den tatsächlichen Stand gebaut und per
`bake --print` gegengeprüft (27 / 1 / 7). Kein Schaden — die Zahl war nur eine
Merkhilfe, keine Anforderung; sie ist hier richtiggestellt, damit sie niemand als
Sollwert liest.

**B15 — `bake` parallelisiert die Matrix; der Bestand schleifte sequenziell.**
Das ist der Gewinn und zugleich eine neue Betriebsbedingung: `make build-all`
übersetzt die Extensions für **drei PHP-Versionen gleichzeitig**. Der erste Lauf
brach deshalb ab —

```
uchar.cpp:629:1: fatal error: error writing to /tmp/cccOEpFe.s: No space left on device
ERROR: target cli-8-5: failed to solve: ... exit code: 2
```

— nicht an PHP 8.5 und nicht an der HCL, sondern an der zu 100 % vollen
Docker-Desktop-VM (62,7 GB). Nach dem Aufräumen (der User selbst; von mir nur die
eigenen Test-Images und der Cache des `multiarch-builder`) lief derselbe Aufruf
mit 21,4 GB frei fehlerfrei durch. **Für P8/P11 festzuhalten:** ein sequenzieller
Rückbau ist *nicht* nötig und wäre gegen AK1 — aber `build-all` braucht spürbar
Plattenplatz, und ein CI-Runner baut ohnehin eine Version je Matrix-Job. Wer
lokal wenig Platz hat, nimmt `make build` je Version.

**B16 — unter Rosetta-Emulation trägt ein FPM-Worker keinen `pool www`-Titel.**
Beim amd64-Nachweis meldete `ps` zunächst null Worker, obwohl der Healthcheck
`healthy` war. Ursache: die Emulation schreibt die Kommandozeile um —
`{php-fpm} /run/rosetta/rosetta /usr/local/sbin/php-fpm php-fpm` statt
`php-fpm: pool www`. Die zwei Worker liefen korrekt als `appuser`. **Verbindlich
für P8:** ein Test, der auf `pool www` grept, misst auf emulierter Fremdarchitektur
nichts — die Prüfung muss über den Benutzer und den `/ping` gehen, nicht über den
Prozesstitel. Gleiche Fehlerklasse wie B11: ein Test, der stillschweigend nichts
prüft.

---

## P7 — entfallen (E11, Anweisung Rolf 2026-07-25)

N3 (OS-Variante) und O1 (Image-Name) waren wie vereinbart vorgelegt und
**entschieden** — Alpine und `headgent/frankenphp`. Auf die anschließende Frage
des Users, was FrankenPHP im vereinbarten Zuschnitt überhaupt einbringt, fiel die
Entscheidung, das Target **ganz zu streichen**.

### Begründung

Im Zuschnitt ohne Worker-Mode (N7) bringt FrankenPHP genau eine Sache: **ein
Container statt zwei**, samt Wegfall der nginx-Konfiguration. Kein
Geschwindigkeitsgewinn — im klassischen Request-Modus bootet PHP pro Request wie
unter FPM; gemessen wurde nichts, architektonisch ist auch nichts zu erwarten.
Caddys HTTP/2, HTTP/3 und Auto-TLS sind hinter einem vorgelagerten Traefik
redundant.

Dem stünden gegenüber: ein drittes publiziertes Image (~250 MB statt 128),
ZTS-PHP statt NTS, rund 30 duplizierte Dockerfile-Zeilen (weil `frankenphp`
nicht `FROM base` kommt) und je ein Dauerzweig in CI-Matrix, Trivy-Scan und
Push-Lauf.

Ausschlaggebend war der Vergleich mit E9: `headgent/nginx` wurde gestrichen,
**weil es keine Konsumenten hat**. `headgent/frankenphp` hätte mit null
Konsumenten begonnen — dieselbe Lage, nur andersherum entschieden. Der eigentliche
Gewinn läge im Worker-Mode (Bootstrap einmal, dann Request-Loop; passt zum
Koffer-/DomainKernel-Muster), und der ist ausgeschlossen.

### Was vor der Streichung am Image belegt wurde

Damit ein späterer Anlauf nicht bei null beginnt — geprüft am
`dunglas/frankenphp:1.12.6-php8.3-alpine` (2026-07-25), **nicht** recherchiert:

| Punkt | Befund |
|---|---|
| Image | 172 MB (arm64), läuft als **root**, `WORKDIR /app` — zufällig unser `APP_ROOT` |
| Ports | 80, 443 (tcp+udp), 2019 (Caddy-Admin) |
| **Default-Port** | **keiner.** Das Caddyfile bindet `{$SERVER_NAME:localhost}`; mit dem Default macht Caddy **Auto-HTTPS auf 443** mit selbst erzeugtem Zertifikat. Klartext-HTTP erst mit `SERVER_NAME=:80`. Damit ist der in N3 offene Punkt beantwortet |
| Document-Root | `{$SERVER_ROOT:public/}` → `/app/public` |
| Betriebsmodus | `php_server`, `worker`-Zeile auskommentiert → klassischer Request-Modus ist der Auslieferzustand; er entsteht dadurch, dass man `FRANKENPHP_CONFIG` **nicht** setzt |
| PHP | 8.3.32, aber **ZTS** (thread-safe) — unser `base` ist NTS |
| Extensions | ~30 Kern-Extensions; von unseren 20 fehlen **17**. `curl`, `dom`, `mbstring` sind einkompiliert — dasselbe Bild wie B12 |
| Vorhandene Werkzeuge | `install-php-extensions`, `setcap` |
| **Fehlende Werkzeuge** | `composer`, `su-exec`, `shadow` (usermod/groupmod) und `bash` — alle vier hätte unser Entrypoint-Kern gebraucht |

Ein späterer Anlauf beginnt sinnvollerweise beim Worker-Mode, nicht beim
Request-Modus, und braucht dann ohnehin eine neue Nutzenrechnung.

### Zurückgebaut

| Ort | Änderung |
|---|---|
| `docs/PRD.md` | **E11** neu; Abschnitt 2, E3 (Begründung), E4, A2.2, A5 (ganz), A8.4, N6/N7 (+ **N8**), O1, AK5/AK6, AK9 nachgezogen |
| `docs/PLAN.md` | Zielstruktur ohne `src/frankenphp/` und `demo-frankenphp.yml`; P7 gestrichen; **P8 hängt jetzt an P6**, **P10 nur noch an P9** |
| `.env` | `FRANKENPHP_VERSION` und `IMAGE_NAME_FRANKENPHP` entfernt (52 → 50 Schlüssel) |
| `docker.helper.mk`, `Makefile` | `FRANKENPHP_IMAGE` und die zwei `info`-Zeilen entfernt |
| Kommentare | `.dockerignore`, `.hadolint.yaml`, `php-extensions.env`, `entrypoint.sh`, `base`/`cli`/`fpm`-Dockerfile |

`docker-bake.hcl` war **nicht** betroffen — das Target war dort noch nicht
angelegt.

**Bewusst nicht geändert:** die Phasennummern P8–P12 rücken **nicht** nach. Ein
Nachrücken machte jede Querverweisung falsch (B11 und B16 „verbindlich für P8",
AK4 an „P8/P11"). Die Lücke ist billiger als die stille Verschiebung.

**Zwei Entscheidungen bleiben, obwohl ihr Anlass entfallen ist**, beide zum
Nulltarif und im Code begründet: der Entrypoint-Kern bleibt POSIX-`sh` (statt
`bash`), und die Extension-Liste bleibt in `src/shared/php-extensions.env`
ausgelagert.

### Akzeptanz — nachgewiesen

- Außerhalb von `docs/` steht `frankenphp` nur noch in **drei** Kommentaren, die
  die Streichung selbst erklären (`.env`, `php-extensions.env`, `entrypoint.sh`).
- `make info` zeigt zwei Targets, `stderr` ist leer — keine
  `--warn-undefined-variables`-Warnung durch die entfernten Schlüssel.
- `make bake-print` löst unverändert auf: Gruppe `default` = `cli` + `fpm`,
  neun Ziele.
- **Vier Prüfungen grün** (hadolint ×3, shellcheck, 33/33, 27/27).

---

## P8 — abgeschlossen

### Geliefert

| Datei | Inhalt |
|---|---|
| `support/makefiles/test.mk` | **neu.** Neun Targets; `make test-all` ist der eine Einstieg |
| `support/tests/check-extensions.sh` | **neu.** Sollmenge aus `php-extensions.env` abgeleitet, ein Containerstart |
| `support/tests/check-app-env.sh` | **neu.** AK13/AK14/A10.2/A10.5/A10.7 am gebauten Image |
| `support/tests/check-opcache.sh` | **neu.** OPcache/JIT je Profil **und AK15** im laufenden FPM |
| `support/tests/check-uid-image.sh` | **neu.** AK4 gegen echte Docker-Volumes |
| `support/tests/check-phpini.sh` | **geändert:** Pfad abgeleitet (B17), Erwartung im test-Profil korrigiert (B18), shellcheck-Ausnahmen begründet |
| `support/tests/check-user-alignment.sh` | **geändert:** shellcheck-Ausnahme begründet |
| `src/shared/entrypoint/lib-phpini.sh` | **geändert:** JIT-Automatik deckt jetzt auch PCOV ab (**Befund B18**) |
| `Makefile` | **geändert:** `include` von `test.mk` |

### Akzeptanz — nachgewiesen

`make test-all` läuft mit **Exit 0** durch. Damit ist die Handarbeit der Phasen
P2–P6 abgelöst: die „vier Prüfungen" sind jetzt drei Make-Targets, und alles
Weitere kommt dazu.

| Target | Ergebnis |
|---|---|
| `test-lint` | hadolint ×3 Exit 0, shellcheck über **11** Shell-Dateien Exit 0 |
| `test-phpini` | **34/34** (war 33 — eine Zusicherung kam mit B18 dazu) |
| `test-user` | **27/27** |
| `test-boot` | cli startet, fpm wird `healthy` (FastCGI-Ping) |
| `test-extensions` | **21/21** in cli **und** fpm |
| `test-app-env` | **15/15** |
| `test-uid` | **5/5** |
| `test-opcache` | **14/14**, davon 4 für AK15 |

**AK15 ist damit automatisiert** — bisher nur von Hand erbracht (P5). Der Test
belegt beide Richtungen und prüft die B11-Gegenprobe mit: `dev` liefert nach der
Dateiänderung FASSUNG-2, `prod` weiterhin FASSUNG-1, und in **beiden** Fällen ist
nachgewiesen, dass überhaupt etwas gecacht war und getroffen wurde.

**AK4 ist so weit erbracht, wie es ohne Linux-Host geht** — und das ist mehr als
erwartet: alle drei von `PLAN.md` geforderten Bedingungen sind am echten Image
belegt, weil ein Named Volume in der Docker-VM echte Unix-Eigentümer trägt.
Offen bleibt allein der Bind-Mount von einem Linux-Host (P11).

### Umsetzungsentscheidungen

1. **Make orchestriert, Skripte behaupten.** Im Bestand standen die Zusicherungen
   als PHP-Einzeiler mitten im Makefile, mit `\$$`-Maskierung über mehrere Ebenen
   — unlesbar und außerhalb von `make` nicht ausführbar. Die Skripte liegen in
   `support/tests/` (das Muster steht seit P2) und laufen auch einzeln.
2. **Test-Images über dieselbe `docker-bake.hcl`**, nur mit `DOCKER_HUB` auf ein
   Testpräfix. Ein Testlauf überschreibt damit **nie** die lokal liegenden
   `headgent/*`-Images und prüft trotzdem exakt das Artefakt, das gepusht würde.
3. **Eine PHP-Version je Lauf.** `build-all` übersetzt drei Versionen gleichzeitig
   (B15) — das soll ein Testlauf nicht nebenbei auslösen. Die Matrix fährt die CI
   (P11), dort baut ohnehin ein Job je Version.
4. **Die Extension-Sollmenge wird abgeleitet, nicht zweitgepflegt.** Genau diese
   Doppelpflege war im Bestand die Ursache von D1: `phpcli/test.mk` listete
   `pcntl`, `phpfpm/test.mk` nicht. Dazu kommt eine **eigene** Zusicherung für
   `curl`, `dom` und `mbstring`: die werden seit B12 bewusst nicht mehr gebaut,
   müssen aber vorhanden sein — fiele eine im Basis-Image weg, merkte es sonst
   niemand.
5. **`check-app-env.sh` baut die 33 Fälle nicht nach.** `check-phpini.sh` prüft
   die Logik in Isolation, das Image-Skript nur, was allein das gebaute Image
   zeigen kann. Beides zu führen wäre Doppelpflege.
6. **Die shellcheck-Ausnahmen stehen inline mit Begründung**, nicht in einer
   Konfiguration — dieselbe Linie wie P3-Entscheidung 7 und P4-Entscheidung 2.

### Befunde aus P8

**B17 — `check-phpini.sh` trug einen absoluten Pfad auf genau einen Rechner.**
`LIB=/Users/Rolf/Development/.../lib-phpini.sh`. Der Test wäre auf jedem anderen
System und auf dem CI-Runner (P11) gescheitert — und zwar mit einer Meldung, die
nach kaputter Bibliothek ausgesehen hätte, nicht nach kaputtem Testaufbau. Der
Pfad wird jetzt aus dem Ort der Datei abgeleitet.

**B18 — echter Defekt: PCOV blockiert JIT genauso wie Xdebug, die Automatik
kannte nur Xdebug.** Der Grund für A10.3/L-A ist nicht „Xdebug", sondern „eine
Extension übernimmt `zend_execute_ex()`" — und das tut PCOV auch. Folge: das
**`test`-Profil** (`XDEBUG_MODE=off`, `PCOV_ENABLED=1`, `JIT=1254`) warnte bei
**jedem** Aufruf:

```
Warning: JIT is incompatible with third party extensions that override
zend_execute_ex(). JIT disabled. in Unknown on line 0
```

Also ausgerechnet in dem Profil, das für Testläufe gedacht ist. Das ist L-A
wortwörtlich, nur mit einer anderen Extension — im Prüffall der Bibliothek war es
nicht sichtbar, weil dort kein PHP läuft. `enforce_jit_policy` deckt jetzt beide
ab und benennt im Log, welche Extension JIT blockiert. Die Erwartung in
`check-phpini.sh` folgt dem korrigierten Verhalten (mit Kommentar an der
Fundstelle), nicht umgekehrt.

**B19 — dritter Fall der Klasse „der Test misst nichts": `--entrypoint` umgeht die
Prüfung.** `docker run --entrypoint php <image> -r ...` ersetzt den Entrypoint —
`lib-phpini.sh` läuft nie, es entsteht keine Laufzeit-INI, und der Test liest die
Defaults der Extensions statt unserer Profile. Beim ersten Lauf meldete
`check-app-env.sh` deshalb 12 Fehlschläge, die alle keine waren: `xdebug.mode`
kam als `develop` (Xdebugs Default), `pcov.enabled` als `1`. Richtig ist, das
Kommando **als Argument** zu übergeben: `docker run <image> php -r ...`. Der
Entrypoint protokolliert nach stderr, `2>/dev/null` genügt für einen sauberen
Messwert. Reihe mit B11 und B16.

**B20 — ein leeres Named Volume bekommt beim ersten Mount die Eigentümer des
Image-Verzeichnisses.** Mountet man ein leeres Volume auf einen Pfad, den das
Image kennt, kopiert Docker dessen Inhalt samt Ownership hinein — und überschreibt
damit genau die Eigentümerangabe, die ein UID-Test vorgeben will. Der Test meldete
dreimal `1000:1000` und hätte, andersherum erwartet, eine Angleichung „belegt",
die nie stattfand. Abhilfe: eine Markierungsdatei macht das Volume nicht-leer,
dann lässt Docker es unangetastet. **Für P11 relevant**, wenn dort dieselben
Fälle auf dem Linux-Runner laufen.

**Zwei PHP-Eigenarten, die eine Zusicherung sonst falsch machen** (in den Skripten
kommentiert): `ini_get('display_errors')` liefert `"1"` für On und einen
**Leerstring** für Off; `ini_get('xdebug.mode')` liefert bei `off` ebenfalls einen
Leerstring — maßgeblich ist dort die Umgebungsvariable, der Xdebug 3 ohnehin
Vorrang gibt (A10.5).

---

## P9 — abgeschlossen

### Geliefert

| Datei | Inhalt |
|---|---|
| `compose/nginx/templates/default.conf.template` | **neu.** Der vhost des Bestands, vollstaendig parametrisiert (A6.1–A6.2), verhaltensgleich im Uebrigen |
| `compose/nginx/nginx-defaults.env` | **neu.** Die elf Variablen mit dokumentierten Defaults (A6.4) — gleichzeitig ihre Dokumentation |
| `support/tests/check-nginx-template.sh` | **neu.** 39 Zusicherungen gegen das unveraenderte offizielle Image, zwei Instanzen |
| `support/makefiles/test.mk` | **geaendert:** `test-nginx` ergaenzt und in `test-all` aufgenommen |

Die elf Variablen: `HOST`, `APP_ROOT`, `DOCUMENT_ROOT`, `INDEX_FILE`,
`FASTCGI_UPSTREAM`, `PHP_PORT`, `CLIENT_MAX_BODY_SIZE`, `FASTCGI_READ_TIMEOUT`,
`FASTCGI_SEND_TIMEOUT`, `FASTCGI_CONNECT_TIMEOUT`, `REQUEST_SCHEME`. Der Bestand
substituierte fuenf (`phpfpm/src/nginx/entrypoint.sh:11`).

### Akzeptanz — nachgewiesen

`make test-nginx` laeuft mit **39/39** durch, gegen `nginx:1.28-alpine`
(nginx/1.28.3) und `php-image-builder-test/phpfpm:8.3`. Der Aufbau ist der, den
Projekte fahren sollen: fpm-Container plus **unveraendertes** offizielles nginx,
gemeinsames `/app`, ein Bind-Mount der Vorlage nach `/etc/nginx/templates`.

**Zwei Instanzen, weil eine allein nichts beweist:**

| | Instanz A | Instanz B |
|---|---|---|
| Konfiguration | **nur** `nginx-defaults.env` | jeder Wert ueberschrieben |
| Beweist | A6.4: laeuft ohne eigene Konfiguration | die Variablen wirken wirklich |

| Prueffall | Ergebnis |
|---|---|
| Start ohne eigenen Entrypoint und ohne eigenen Build (A6.3) | ✅ beide Instanzen |
| Keine unsubstituierte Variable in der erzeugten Konfiguration | ✅ |
| `fastcgi_pass app:9000` an **beiden** Stellen, `client_max_body_size 100m`, alle drei Timeouts | ✅ am Rendering |
| Front-Controller: `/nicht/vorhanden` → 200, `PROBE=index`, `REQUEST_URI` erhalten | ✅ |
| Location 2: `/index.php/foo/bar` → `PATH_INFO=/foo/bar` | ✅ |
| Location 3: `/info.php` → eigene Datei, eigenes `SCRIPT_FILENAME` | ✅ |
| `/.env` → 404 | ✅ |
| **A6.2 ohne TLS-Proxy:** `REQUEST_SCHEME=http`, **`HTTPS` gar nicht uebergeben** | ✅ |
| **A6.2 hinter TLS-Proxy:** ein Schalter setzt `HTTPS=on`, `REQUEST_SCHEME=https`, `HTTP_X_FORWARDED_PROTO=https` | ✅ |
| `HOST`, `DOCUMENT_ROOT`, `INDEX_FILE` ueberschrieben → `SERVER_NAME`, Dokumentwurzel und PATH_INFO-Location folgen | ✅ |
| `CLIENT_MAX_BODY_SIZE` **wirkt**: 2000 B gegen `1k` → 413, gegen `100m` → 200 | ✅ mit Gegenprobe auf `CONTENT_LENGTH=2000` |
| `FASTCGI_READ_TIMEOUT` **wirkt**: 3-s-Antwort gegen `1` → 504, gegen `600` → 200 | ✅ |
| `FASTCGI_UPSTREAM` landet wirklich im `fastcgi_pass` | ✅ Gegenprobe: falscher Name → nginx meldet ihn sichtbar |

**Gegenprobe zu A6.4** (nicht im Skript, weil sie den Start verhindert): ohne die
Defaults-Datei — nur die Vorlage gemountet — bricht nginx sichtbar ab
(`"client_max_body_size" directive invalid value`). Das ist der Beleg, dass die
Defaults gebraucht werden und nicht bloss Beiwerk sind.

**AK7 ist damit vollstaendig belegt**, alle drei Haelften: keine hartkodierten
Werte mehr aus der Liste in PRD 1.3, der Betrieb ohne TLS-Proxy ist korrekt, und
es laeuft mit dem unveraenderten offiziellen Image ohne eigenen Entrypoint. Das
Abhaken im PRD bleibt dem Gate in P12 vorbehalten. **AK12** braucht die zweite
Haelfte („der Demo-Stack belegt es") und faellt damit in P10.

`make test-all` bleibt gruen — der neue Prueflauf ist die neunte Stufe.

### Umsetzungsentscheidungen

1. **Die Defaults liegen in einer eigenen Datei — das ist eine Abweichung von
   der Zielstruktur des Plans** (dort steht nur die Vorlage) und sie ist
   unvermeidlich: `envsubst` kennt keine Default-Schreibweise. Was die Umgebung
   nicht traegt, bleibt unersetzt stehen und nginx startet nicht (oben belegt).
   A6.4 („ohne Konfiguration lauffaehig") ist also **nur** mit einer
   mitgelieferten Defaultquelle einloesbar. Die Datei ist gleichzeitig die von
   A6.4 verlangte Dokumentation und wird in P10 vom Demo-Stack per `env_file:`
   eingebunden — kein Wert doppelt gepflegt (A2.1). Vorrang: `environment:`
   schlaegt `env_file:`, dieselbe Richtung wie A10.2 bei den PHP-Werten;
   nachgewiesen an Instanz B.
2. **Ein Schalter statt zweier Werte.** `REQUEST_SCHEME=http|https` speist ueber
   einen `map`-Block alle drei fastcgi-Werte (`HTTPS`, `REQUEST_SCHEME`,
   `HTTP_X_FORWARDED_PROTO`). Zwei einzelne Variablen waeren einfacher zu lesen
   und koennten auseinanderlaufen — `HTTPS=on` bei `REQUEST_SCHEME=http` ist
   genau die stille Fehlkonfiguration, die dieses Vorhaben sonst ueberall
   austreibt. Im `http`-Fall wird `HTTPS` ueber nginx-eigenes `if_not_empty` gar
   nicht uebergeben, statt es auf `off` zu setzen: Frameworks pruefen den Wert
   unterschiedlich (`=== 'on'` vs. „nicht leer"), das Fehlen ist eindeutig. Genau
   so verfaehrt das offizielle `fastcgi_params` mit `$https` auch.
3. **Die fuenf bestehenden Variablennamen bleiben** (`HOST`, `APP_ROOT`,
   `DOCUMENT_ROOT`, `INDEX_FILE`, `PHP_PORT`). Sie stehen so in der README des
   Bestands und in den `environment:`-Bloecken der Projekte; sie umzubenennen
   waere ein Bruch ohne Gegenwert (Linie E2). `FASTCGI_UPSTREAM` ist **der Name
   aus dem Vorlaeuferdokument**, den PRD 1.3 als „existiert nicht" fuehrt — jetzt
   existiert er.
4. **Kein `NGINX_ENVSUBST_FILTER`.** Erwogen, um die Substitution auf einen
   Praefix zu begrenzen. Nicht noetig und deshalb weggelassen: das offizielle
   Skript uebergibt `envsubst` eine **Namensliste** aus der Umgebung, und
   nginx-eigene Variablen (`$uri`, `$args`, `$document_root`, `$1`) sind
   kleingeschrieben und stehen in keiner Umgebung. Ein Filter waere eine weitere
   Pflichtvariable, deren Fehlen niemand bemerkt.
5. **Eine Datei, kein ausgelagerter fastcgi-Block.** Der 11-Zeilen-Block steht in
   beiden PHP-Locations — nginx kennt kein Makro. Ein `include` einer zweiten
   gerenderten Datei waere moeglich (Endung `.inc`, damit `conf.d/*.conf` sie
   nicht selbst laedt), haette aber zwei Nachteile: die Zielstruktur des Plans
   nennt genau eine Datei, und wer nur die Vorlage mountet statt des
   Verzeichnisses, bekaeme einen kaputten Include. Ein Drift-Risiko entsteht
   nicht: die parametrisierten Werte kommen an beiden Stellen aus derselben
   Variablen.
6. **Nicht parametrisiert:** `send_timeout`, `keepalive_timeout`, die
   gzip-Einstellungen, die Security-Header, die `real_ip`-Netze, die
   fastcgi-Buffer und `expires`. A6.1 nennt sie nicht, und PRD 1.3 fuehrt sie
   nicht als Defekt. Jede weitere Variable ist eine, die ohne Eintrag in der
   Defaults-Datei den Start verhindert — der Preis will begruendet sein.
7. **Im Uebrigen verhaltensgleich.** Beide PHP-Locations, die Deny-Regeln, die
   Header und der `try_files`-Pfad sind unveraendert uebernommen. Erwogen und
   **nicht** getan: die Fallback-Location fuer beliebige `*.php`-Dateien
   streichen (waere eine Verhaltensaenderung ohne Auftrag) und HSTS an den
   Schalter binden (Browser ignorieren HSTS ueber Klartext ohnehin).
8. **Kommentare der Vorlage tragen keinen Platzhalter**, den die Umgebung nicht
   kennt. Ein solcher bleibt unersetzt stehen; nginx stoert das im Kommentar
   nicht, aber die Rendering-Pruefung kann einen harmlosen von einem echten Rest
   nicht unterscheiden — und soll streng bleiben. Erster Lauf des Prueffalls fiel
   genau darauf.

### Befunde aus P9

**B21 — fuenfter Fall der Klasse „der Test misst nichts": busybox-`wget
--post-file` sendet keinen Rumpf.** Ein POST von 2 MB gegen
`client_max_body_size 1m` lieferte **200 statt 413**. Ursache ist nicht die
Vorlage: `--post-file` setzt in busybox 1.37.0 die Methode POST, uebertraegt aber
nichts — die Sonde meldete `REQUEST_METHOD=POST` bei `CONTENT_LENGTH=0`. Mit
`--post-data` stimmt es (`CONTENT_LENGTH=2000`, 413 gegen `1k`, 200 gegen
`100m`). Der Prueffall zieht seither die angekommene Rumpflaenge als Gegenprobe
mit, sonst haette derselbe Fehler in anderer Gestalt wieder gruen gemeldet.
Reihe mit B11, B16, B19, B20.

**B22 — der spaetere `fastcgi_param` gewinnt; das Muster des Bestands ist damit
belegt.** Das offizielle `fastcgi_params` setzt selbst schon
`REQUEST_SCHEME $scheme` und `HTTPS $https if_not_empty`. Der Bestand (und unsere
Vorlage) schreibt beide **nach** dem `include` erneut — dass dabei der zweite
Wert zaehlt, war nie geprueft. Gemessen an Instanz B: bei `REQUEST_SCHEME=https`
kommt `https` in `$_SERVER` an, obwohl das `include` vorher `http` setzte. Das
Muster traegt.

**B23 — `nginx -t` loest den Upstream-Namen auf.** Ein Konfigurationstest ohne
laufenden fpm-Container scheitert mit `host not found in upstream "app"` — kein
Vorlagenfehler, sondern DNS. **Fuer P11 relevant:** ein reiner Lint der Vorlage
in der CI braucht entweder einen erreichbaren Upstream oder einen auflösbaren
Ersatznamen. Im Prueffall ist genau dieses Verhalten die Gegenprobe, dass
`FASTCGI_UPSTREAM` wirklich im `fastcgi_pass` landet.

---

## Offene Punkte / Risiken

| # | Punkt | Fällig in | Kritikalität |
|---|---|---|---|
| ~~N1~~ | ~~Basis-Image für `base`~~ — **entschieden 2026-07-25: Variante (a), `php:X-fpm-alpine`.** Begründung und Messung im Abschnitt „P3 → N1 entschieden" | — | erledigt |
| ~~N2~~ | ~~Override-Slots nicht als `ENV` backen, die profilunabhängigen Werte hingegen zwingend~~ — **umgesetzt und am gebauten Image belegt** (P3 → Akzeptanz). Gilt unverändert für P4, P5 und P7 | — | erledigt |
| ~~N5~~ | ~~`STOPSIGNAL SIGQUIT` aus dem fpm-Basisimage ist für einen CLI-Worker falsch~~ — **korrigiert in P4**, `StopSignal=SIGTERM` am gebauten Image geprüft | — | erledigt |
| **N6** | **Erster Push auf `headgent/phpcli`/`phpfpm` ist der einzige Punkt, an dem laufende Projekte Schaden nehmen könnten.** Vor dem ersten Push wird eine Tag-Strategie vorgelegt (Vorschlag: Nebentag `:<ver>-next`, `:latest` und `:<ver>` unangetastet, bis in einem Projekt gegengeprüft). Bis dahin: kein `docker login`, kein `--push`, keine CI-Auslösung | vor P11-Abschluss | **hoch** |
| ~~N4~~ | ~~FPM-Privilegienwechsel: zwei tragfähige Wege~~ — **entschieden 2026-07-25: Variante (b)**, und zwar zwingend: (a) ist nachweislich nicht lauffähig (Befund **B9** — der `chown`-Griff ist wirkungslos, `headgent/phpfpm` startet deshalb in keiner Version). Es war keine Abwägung | — | erledigt |
| ~~N3~~ | ~~FrankenPHP-OS-Variante~~ — **entschieden 2026-07-25: Alpine**, wenige Minuten später mit dem ganzen Target gestrichen (E11). Der offene Default-Port ist im Abschnitt „P7 — entfallen" trotzdem belegt festgehalten | — | erledigt |
| ~~O1~~ | ~~Image-Name für FrankenPHP~~ — **entschieden: `headgent/frankenphp`**, dann mit E11 gegenstandslos | — | erledigt |
| AK4 | UID-Nachweis ist auf macOS prinzipiell nicht führbar. P8 liefert den Test, P11 den Nachweis auf dem Linux-Runner. | P8/P11 | bekannt |

### Wartet auf ausdrückliche Freigabe (nach außen wirkend)

- **Kein GitHub-Repo angelegt**, kein Remote gesetzt (`make init` steht bereit).
- **Nichts archiviert** — `jardisOps/phpcli` und `jardisOps/phpfpm` sind unberührt (E8).
- **Commits sind freigegeben** und liegen vor (Stand P6: vier). Sie bleiben rein
  lokal — kein Remote, kein Push.
- **Vorgriff-Verzeichnis** `devops/image/docker-php-builder/` besteht noch (leere
  Verzeichnisse, Git-Repo ohne Commits, keine Datei). Gegenstandslos, kann entfernt
  werden.
- **Kein Push, kein `docker login`** — siehe **N6**.

### Belegte Unversehrtheit des Bestands (Stand P6, 2026-07-25)

Nachtrag P6: die Abnahme-Builds liefen bewusst unter `DOCKER_HUB=php-image-builder-test`
bzw. `-amd64`, damit die lokal liegenden `headgent/*`-Referenzimages nicht
überschrieben werden. Nach dem Matrix-Lauf gegengeprüft: `headgent/phpcli:8.2|8.3|8.4|latest`
und `headgent/phpfpm:8.2|8.3|8.4|latest` tragen unverändert ihre alten Image-IDs
und Größen. Entfernt wurden ausschließlich **eigene** Artefakte (die
`php-image-builder-*:test`-Images der Vorsession und der Cache des
`multiarch-builder`). Kein `docker push`, kein `docker login`.

### Belegte Unversehrtheit des Bestands (Stand P3, 2026-07-25)

Auf Nachfrage des Users geprüft, ob die Arbeit am neuen Repo laufende Projekte
gefährdet. Nein — nachgewiesen:

- `git status --porcelain` in `devops/image/phpcli` und `.../phpfpm`: je **0**
  geänderte Dateien. Beide wurden ausschließlich gelesen.
- Lokale `headgent/*`-Images (phpcli 8.2/8.3/8.4/latest, phpfpm 8.2/8.3/8.4/latest,
  nginx 1.28/latest) unverändert, Alter 7 Wochen bis 6 Monate — keins von heute.
- Heute lokal angefasst: `php:8.3-cli-alpine3.23` und `php:8.3-fpm-alpine3.23`
  (offizielle Images, gezogen zum Messen) sowie `php-image-builder-base:test` —
  ein Name, den es in keiner Registry gibt.
- Kein `docker push`, kein `docker login`, kein Tag auf `headgent/*`.

---

## N1 im Detail — Basis-Image für `base` (ENTSCHIEDEN 2026-07-25: Variante (a))

> **Erledigt.** Der Abschnitt bleibt als Entscheidungsgrundlage stehen. Die
> Messung, die in der Tabelle unten noch als „nicht ermittelt" steht, wurde am
> 2026-07-25 nachgeholt und kehrt das Ballast-Argument um — Ergebnis im Abschnitt
> „P3 → N1 entschieden".

Der Bestand baut auf **zwei verschiedenen** offiziellen Images:
`php:<ver>-cli-alpine<ALPINE>` (`phpcli/src/Dockerfile:28,62`) und
`php:<ver>-fpm-alpine<ALPINE>` (`phpfpm/src/php/Dockerfile:17,51`). Ein gemeinsames
`base` kann nicht beides sein; PRD Abschnitt 2 nennt nur „offizielles `php:X-alpine`".

**Verifiziert am 2026-07-25:** `php:8.3-fpm-alpine3.23` enthält **beides** —
`/usr/local/bin/php` (PHP 8.3.30 CLI) und `/usr/local/sbin/php-fpm`. Variante (a) ist
damit technisch tragfähig. Der Größenunterschied der beiden offiziellen Images wurde
**nicht** ermittelt (`docker manifest inspect` lieferte die Layer-Größen nicht) — falls
er die Entscheidung tragen soll, muss er gemessen werden.

| | Variante (a): `base` = `fpm-alpine` | Variante (b): `base` = Extension-Build-Stage |
|---|---|---|
| Aufbau | `cli` und `fpm` mit `FROM base` | `cli`/`fpm` je auf ihrem offiziellen Image, `COPY --from=base` der `.so`-Dateien |
| Gemeinsames (apk-Libs, `appuser`, Composer, Entrypoint, Symlinks, Labels) | steht **einmal** in `base` | **dupliziert** in `cli` und `fpm` — genau die Duplikation, die E1/A3.1 beseitigen sollen |
| Ballast | `cli` trägt `php-fpm` mit (Umfang unbekannt, s.o.) | keiner |
| Nähe zum PRD | entspricht Abschnitt 2 („`cli`, Basis: `base`") wörtlich | `base` wäre Build-Stage, kein Laufzeit-Basisimage |
| Nähe zum Bestand | neu | entspricht dem heutigen build-/runtime-Stage-Muster |
| Risiko | FPM-Image-Defaults (`WORKDIR`, `CMD`, Entrypoint) in `cli` überschreiben | `.so`-ABI-Kompatibilität zwischen beiden Images (gleiche PHP-Version und Alpine-Version, praktisch unkritisch) |

Beide erfüllen A1.2 (`contexts = { base = "target:base" }`) und AK2. **Empfehlung: (a)** —
das Duplikations-Argument wiegt schwerer als ein paar MB Ballast im CLI-Image, und E1
ist das Kernziel des Vorhabens. Entscheidung liegt beim User.

## Profiltabelle (in P2 umgesetzt, `lib-phpini.sh`)

| | `dev` | `test` | `prod` |
|---|---|---|---|
| `XDEBUG_MODE` | `debug` | `off` | `off` |
| `PCOV_ENABLED` | `0` | `1` | `0` |
| `OPCACHE_VALIDATE_TIMESTAMPS` | `1` | `1` | `0` (A10.6, behebt L-C/D3) |
| `OPCACHE_REVALIDATE_FREQ` | `0` | `0` | `0` |
| `OPCACHE_JIT` | aus, weil Xdebug aktiv (A10.3, behebt L-A) | `1254` | `1254` |
| `PHP_DISPLAY_ERRORS` | `On` (behebt L-D) | `On` | `Off` |
| `PHP_ERROR_REPORTING` | `E_ALL` | `E_ALL` | `E_ALL & ~E_DEPRECATED` (ohne `E_STRICT`, behebt L-G) |

Ebenfalls in P2 umgesetzt: JIT-Automatik (A10.3), expliziter Export (A10.5),
prod-Abbruch bei aktivem Xdebug (A10.4), Wertvalidierung (A10.7, L-E),
UID/GID-Neubau (A4/E7 gegen U1–U3). **L-B ist mit dem `test`-Profil erledigt:**
`XDEBUG_MODE` muss in keinem Testaufruf mehr abgeschaltet werden.

## Nächste Phase

**P10 — Demo-Stack.** Liefert `compose/demo-stack.yml`: mysql/mariadb + `fpm` +
**unverändertes** offizielles nginx mit der Vorlage aus P9 (A8.1). Hängt nur noch
an P9, seit E11 gibt es nur eine Ausprägung (A8.4 entfallen).

Akzeptanz nach Plan: `docker compose up` ohne Nacharbeit, Health-Checks für alle
Services (A8.2), die Template-Variablen exemplarisch befüllt (A8.3). Damit fällt
auch die zweite Hälfte von **AK12** („der Demo-Stack belegt, dass das offizielle
Image mit der gelieferten Config auskommt") — die erste ist mit P9 erbracht.

Was aus P9 dafür bereitliegt: `compose/nginx/nginx-defaults.env` wird per
`env_file:` eingebunden, überschrieben wird nur, was der Stack wirklich anders
braucht (`HOST`, ggf. `FASTCGI_UPSTREAM`, wenn der PHP-Service nicht `app` heißt).
Der Aufbau ist in `check-nginx-template.sh` schon einmal gefahren — Netz, gemeinsames
`/app`, Reihenfolge fpm-vor-nginx. Befund **B23** beachten: nginx löst den
Upstream-Namen beim Start auf, ein nginx ohne erreichbaren PHP-Service startet nicht.

Danach P11 (CI + Härtung), P12 (Doku + Abschluss).
