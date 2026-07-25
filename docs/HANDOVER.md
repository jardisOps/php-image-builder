# Handover — Konsolidierung des PHP-Docker-Image-Builders

**Stand:** 2026-07-25, Ende der dritten Umsetzungs-Session. **P1–P6 abgeschlossen
und committet**, **P7 ist entfallen** (E11) — nächste Phase ist **P8**.

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder/`
Projekt- und künftiger Repo-Name: **`php-image-builder`**.
Bestandscode unverändert unter `devops/image/phpcli/` und `devops/image/phpfpm/`,
Vorläuferdokumente unter `devops/image/`.

---

## Die vier Dokumente — in dieser Reihenfolge lesen

| Datei | Inhalt | Vorrang |
|---|---|---|
| `docs/PROGRESS.md` | **Maßgeblich.** Laufender Zustand: P1–P6 mit Nachweisen, alle Umsetzungsentscheidungen, Befunde B1–B16, offene Punkte, nächste Phase | geht bei Widersprüchen vor |
| `docs/PRD.md` | Anforderungen A1–A10, Entscheidungen E1–**E11**, Nicht-Ziele N1–**N8**, Akzeptanzkriterien AK1–AK15, vollständiger Ist-Zustand (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken L-A–L-G) mit Datei- und Zeilenangaben | bestätigt |
| `docs/PLAN.md` | Bauform, Zielstruktur, 12 Phasen mit Abhängigkeiten | freigegeben |
| `docs/HANDOVER.md` | diese Datei — Vorgeschichte und Einstieg | — |

**Der Bestandscode muss nicht neu analysiert werden.** Das PRD trägt ihn
vollständig mit Fundstellen.

---

## Stand

**Fünf Commits, 27 Dateien.** Das Repo hat **kein Remote** und ist nie gepusht
worden.

```
(HEAD)   docs: record the P6 commit hash in the handover
ea450dc  feat: docker-bake.hcl drives base/cli/fpm in one run (P6)
238f969  docs: hand over at end of P5 — status, four checks, follow-up prompt for P6
7ad5cc7  feat: build matrix moves to PHP 8.3/8.4/8.5, drop 8.2
1aa8d30  feat: consolidated PHP image builder — base, cli and fpm targets
```

| Phase | Stand |
|---|---|
| P1 Repo-Gerüst + konsolidierte `.env` | ✅ |
| P2 Gemeinsamer Entrypoint-Kern (UID/GID + `APP_ENV`) | ✅ |
| P3 `base`-Target | ✅ |
| P4 `cli`-Target | ✅ |
| P5 `fpm`-Target | ✅ |
| P6 `docker-bake.hcl` + Make-Targets | ✅ |
| ~~P7 `frankenphp`-Target~~ | **entfallen (E11)** — Nummer bleibt frei, P8–P12 rücken nicht nach |
| **P8 Tests** | **← hier weiter** (hängt jetzt an P6) |
| P9–P12 | offen |

Gebaut und geprüft: `base`, `cli` und `fpm` gegen PHP **8.3, 8.4 und 8.5** — in
**einem** `bake`-Lauf, nativ auf arm64. **amd64 ist seit P6 belegt** (PHP 8.3,
emuliert gebaut, `uname -m` = `x86_64`, fpm `healthy`); der Nachweis auf einem
echten Linux-Runner bleibt P11.

## Bedienung seit P6

```sh
make build                          # cli + fpm für PHP_VERSION aus der .env
make build-all                      # cli + fpm für 8.3 / 8.4 / 8.5, ein Lauf
make build BAKE_TARGETS=fpm         # nur ein Target (base kommt automatisch mit)
make build BUILD_PLATFORM=linux/amd64
make bake-print                     # aufgelöste Definition, baut nichts
PHP_VERSION=8.5 make build          # Umgebung schlägt die .env (B1)
make push / make push-all           # geschrieben, NIE ausgeführt — siehe N6
```

`make build-all` übersetzt drei PHP-Versionen **gleichzeitig** und braucht
entsprechend Plattenplatz (Befund B15).

---

## Die vier Prüfungen, die grün bleiben müssen

Aus dem Repo-Root. Sie sind in P8 in `test.mk` einzubinden.

```sh
# hadolint — für alle drei Dockerfiles, je Exit 0
for f in src/base/Dockerfile src/cli/Dockerfile src/fpm/Dockerfile; do
  docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" \
    hadolint/hadolint:latest hadolint --config /.hadolint.yaml - < "$f"; done

# shellcheck — alle vier Shell-Dateien
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  --external-sources --source-path=src/shared/entrypoint \
  src/shared/entrypoint/*.sh src/shared/php-extensions.env src/fpm/fpm-pool.sh

bash support/tests/check-phpini.sh          # 33/33
docker run --rm --platform linux/amd64 \
  -v "$PWD/src/shared/entrypoint/lib-user.sh:/lib-user.sh:ro" \
  -v "$PWD/support/tests/check-user-alignment.sh:/check.sh:ro" \
  alpine:3.23 sh /check.sh                  # 27/27
```

Das Ad-hoc-Build-Skript aus P3/P4 ist mit P6 **entfallen** — `make build` löst es
ab. Die damit erzeugten `php-image-builder-*:test`-Images sind entfernt.

---

## Was in dieser Session entschieden wurde

| # | Entscheidung | Wo begründet |
|---|---|---|
| **N1** | `base` = `php:X-fpm-alpine`, auch für CLI. Gemessen: fpm-Image ist 16,7 MB **kleiner** als cli und trägt einen byte-gleichen PHP-CLI | PROGRESS „P3 → N1 entschieden" |
| **N4** | FPM startet als root, wechselt die Worker selbst per `user =`. **Keine Abwägung** — der su-exec-Weg funktioniert nachweislich nicht | PROGRESS „P5 → N4", Befund B9 |
| — | `cli` bleibt ein eigenes Target (vier Zeilen), weil `max_execution_time`, `STOPSIGNAL` und `HEALTHCHECK` zwischen Worker und Request entgegengesetzt sind | PROGRESS „P4 → Vorbemerkung" |
| — | Matrix auf **8.3 / 8.4 / 8.5**, 8.2 gestrichen | PROGRESS „Versions-Matrix umgestellt" |
| — | `bake` bekommt seine Werte **ausschließlich** über den `export` des Makefiles — es liest die `.env` nicht selbst; `args = { X = null }` vererbt nichts | PROGRESS „P6 → Entscheidungen 1 und 2" |
| **E11** | **FrankenPHP entfällt ganz.** Ohne Worker-Mode bringt es nur „ein Container statt zwei", kostet ein drittes publiziertes Image — und hätte mit **null Konsumenten** begonnen, genau der Grund, aus dem `headgent/nginx` gestrichen wurde | PROGRESS „P7 — entfallen", PRD E11 |

## Die wichtigsten Befunde

- **B9 — `headgent/phpfpm` ist in allen drei publizierten Versionen
  startunfähig.** Der `chown` auf `/proc/self/fd/{1,2}` liefert Exit 0 und wirkt
  nicht (anonyme Pipe), FPM scheitert danach am `error_log`. Der User hat
  bestätigt, dass derzeit nichts gegen phpfpm läuft. Das neue Image behebt es.
- **B12/B13 — zwei überflüssige Bauschritte im Bestand**: `curl`/`dom`/`mbstring`
  wurden nachgebaut, obwohl einkompiliert; `docker-php-ext-enable opcache` war
  immer ein No-op. Beide brachen erst bei 8.5 auf.
- **B11 — Testfallstrick `opcache.file_update_protection` (2 s).** Jeder
  OPcache-Test muss die Frist abwarten und `num_cached_scripts`/`hits` mitprüfen,
  sonst misst er nichts. **Verbindlich für P8.**
- **B16 — zweiter Testfallstrick, gleiche Klasse:** unter Rosetta-Emulation heißt
  ein FPM-Worker nicht `php-fpm: pool www`. Ein Test, der darauf grept, misst auf
  emulierter Fremdarchitektur nichts — über Benutzer und `/ping` prüfen.
- **B15 — `bake` baut die Matrix parallel.** `make build-all` übersetzt drei
  PHP-Versionen gleichzeitig; auf einer vollen Docker-VM bricht das mit
  „No space left on device" ab. Kein Designfehler, eine Betriebsbedingung.

---

## Arbeitsweise in dieser Session (fortzuführen)

- **Sprache Deutsch.**
- **Keine Subagenten, kein Experten-Gremium** — der User hat beides ausdrücklich
  ausgeschlossen, sofern er sie nicht anfordert.
- **Bauform der Bestands-Repos bleibt erhalten und wird nur optimiert:**
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als
  Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- **Nichts nach außen ohne ausdrückliche Freigabe:** kein GitHub-Repo, kein
  Remote, kein Push, keine Archivierung. Commits sind **freigegeben** (fünf
  liegen vor); bei Unsicherheit fragen.
- **Umfang: nicht überkonstruieren.** Der User hat in P2 zweimal zurückgebaut
  (Notwert-Ebene, Lookup-Tabelle). Wenn etwas einfacher geht als geplant: sagen
  statt aufwendig bauen. Vor Abweichungen von PRD oder Plan nachfragen.
- **Keine Annahmen.** Jeder Befund wird belegt — dieselbe Linie, die B9, B12 und
  B13 überhaupt erst sichtbar gemacht hat.

---

## Vor dem Abschluss zu erledigen

- **N6 — der erste Push ist der einzige Punkt mit Außenwirkung.** Vorher eine
  Tag-Strategie vorlegen (Vorschlag: Nebentag `:<ver>-next`, `:latest` und
  `:<ver>` unangetastet, bis in einem Projekt gegengeprüft).
- Kein GitHub-Repo, kein Remote (`make init` steht bereit, ist nie gelaufen).
- `jardisOps/phpcli` und `jardisOps/phpfpm` sind unberührt und **nicht**
  archiviert (E8).
- `devops/image/docker-php-builder/` (alter Vorgriff: leere Verzeichnisse plus
  Git-Repo ohne Commits) steht noch da und ist gegenstandslos.
