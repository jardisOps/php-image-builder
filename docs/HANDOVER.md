# Handover — Konsolidierung des PHP-Docker-Image-Builders

**Stand:** 2026-07-25, Ende der vierten Umsetzungs-Session. **P1–P6, P8 und P9
abgeschlossen und committet**, **P7 ist entfallen** (E11) — nächste Phase ist **P10**.

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder/`
Projekt- und künftiger Repo-Name: **`php-image-builder`**.
Bestandscode unverändert unter `devops/image/phpcli/` und `devops/image/phpfpm/`,
Vorläuferdokumente unter `devops/image/`.

---

## Die vier Dokumente — in dieser Reihenfolge lesen

| Datei | Inhalt | Vorrang |
|---|---|---|
| `docs/PROGRESS.md` | **Maßgeblich.** Laufender Zustand: P1–P6, P8 und P9 mit Nachweisen, alle Umsetzungsentscheidungen, Befunde B1–B23, offene Punkte, nächste Phase | geht bei Widersprüchen vor |
| `docs/PRD.md` | Anforderungen A1–A10, Entscheidungen E1–**E11**, Nicht-Ziele N1–**N8**, Akzeptanzkriterien AK1–AK15, vollständiger Ist-Zustand (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken L-A–L-G) mit Datei- und Zeilenangaben | bestätigt |
| `docs/PLAN.md` | Bauform, Zielstruktur, 12 Phasen mit Abhängigkeiten | freigegeben |
| `docs/HANDOVER.md` | diese Datei — Vorgeschichte und Einstieg | — |

**Der Bestandscode muss nicht neu analysiert werden.** Das PRD trägt ihn
vollständig mit Fundstellen.

---

## Stand

**Dreizehn Commits, 35 Dateien.** Das Repo hat **kein Remote** und ist nie
gepusht worden.

```
(HEAD)   docs: update commit count in the handover
cbc3d62  docs: Code-Review-Befunde zu P9 (B24, B25, offener Punkt O6)
b8a4405  docs: hand over at end of P9
d4e89e6  feat: nginx-Vorlage als Asset, vollstaendig parametrisiert (P9)
9d2f171  docs: hand over at end of P8
a473405  feat: test.mk — ein Prueflauf loest die Handarbeit ab (P8)
93ee074  docs: update commit count and log in the handover
7cd1187  feat!: drop the frankenphp target entirely (E11)
aaf7772  docs: record the P6 commit hash in the handover
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
| P8 Tests | ✅ `make test-all` grün |
| P9 nginx-Config als Asset | ✅ Vorlage + Defaults, 39/39 gegen das offizielle Image (AK7) |
| **P10 Demo-Stack** | **← hier weiter** (hängt nur an P9) |
| P11–P12 | offen |

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

## Der Prüflauf, der grün bleiben muss

Seit P8 ein Aufruf aus dem Repo-Root — die Handarbeit der Phasen P2–P6 ist damit
abgelöst:

```sh
make test-all          # baut Test-Images fuer PHP_VERSION und prueft alles
```

| Target | Umfang |
|---|---|
| `test-lint` | hadolint ×3, shellcheck über 12 Shell-Dateien |
| `test-phpini` | 34 Fälle gegen `lib-phpini.sh`, ohne Container |
| `test-user` | 27 Fälle gegen `lib-user.sh`, in `alpine:3.23` |
| `test-boot` | cli startet, fpm wird `healthy` |
| `test-extensions` | 21 Extensions in cli **und** fpm |
| `test-app-env` | 15 Fälle: AK13, AK14/L-F, A10.2, A10.5, A10.7 |
| `test-uid` | 5 Fälle gegen echte Docker-Volumes (AK4) |
| `test-opcache` | 14 Fälle inkl. **AK15** im laufenden FPM |
| `test-nginx` | 39 Fälle gegen das **unveränderte** offizielle nginx-Image (AK7), zwei Instanzen: nur Defaults / alles überschrieben |

Die Test-Images entstehen unter `php-image-builder-test/` und überschreiben die
lokalen `headgent/*`-Images nicht. Eine andere Version prüfen:
`PHP_VERSION=8.5 make test-all`.

---

## Was in dieser Session entschieden wurde

| # | Entscheidung | Wo begründet |
|---|---|---|
| **N1** | `base` = `php:X-fpm-alpine`, auch für CLI. Gemessen: fpm-Image ist 16,7 MB **kleiner** als cli und trägt einen byte-gleichen PHP-CLI | PROGRESS „P3 → N1 entschieden" |
| **N4** | FPM startet als root, wechselt die Worker selbst per `user =`. **Keine Abwägung** — der su-exec-Weg funktioniert nachweislich nicht | PROGRESS „P5 → N4", Befund B9 |
| — | `cli` bleibt ein eigenes Target (vier Zeilen), weil `max_execution_time`, `STOPSIGNAL` und `HEALTHCHECK` zwischen Worker und Request entgegengesetzt sind | PROGRESS „P4 → Vorbemerkung" |
| — | Matrix auf **8.3 / 8.4 / 8.5**, 8.2 gestrichen | PROGRESS „Versions-Matrix umgestellt" |
| — | `bake` bekommt seine Werte **ausschließlich** über den `export` des Makefiles — es liest die `.env` nicht selbst; `args = { X = null }` vererbt nichts | PROGRESS „P6 → Entscheidungen 1 und 2" |
| — | **nginx-Vorlage: ein Schalter `REQUEST_SCHEME=http\|https`** statt zweier Werte, und die Defaults liegen in `compose/nginx/nginx-defaults.env` — envsubst kennt keine Default-Schreibweise, ohne die Datei startet nginx nicht | PROGRESS „P9 → Entscheidungen 1 und 2" |
| **E11** | **FrankenPHP entfällt ganz.** Ohne Worker-Mode bringt es nur „ein Container statt zwei", kostet ein drittes publiziertes Image — und hätte mit **null Konsumenten** begonnen, genau der Grund, aus dem `headgent/nginx` gestrichen wurde | PROGRESS „P7 — entfallen", PRD E11 |

## Die wichtigsten Befunde

- **B9 — `headgent/phpfpm` ist in allen drei publizierten Versionen
  startunfähig.** Der `chown` auf `/proc/self/fd/{1,2}` liefert Exit 0 und wirkt
  nicht (anonyme Pipe), FPM scheitert danach am `error_log`. Der User hat
  bestätigt, dass derzeit nichts gegen phpfpm läuft. Das neue Image behebt es.
- **B12/B13 — zwei überflüssige Bauschritte im Bestand**: `curl`/`dom`/`mbstring`
  wurden nachgebaut, obwohl einkompiliert; `docker-php-ext-enable opcache` war
  immer ein No-op. Beide brachen erst bei 8.5 auf.
- **B18 — echter Defekt, gefunden von den P8-Tests: PCOV blockiert JIT genauso
  wie Xdebug.** Die JIT-Automatik kannte nur Xdebug, also warnte ausgerechnet das
  `test`-Profil bei jedem Aufruf („JIT is incompatible…") — L-A wortwörtlich, nur
  mit anderer Extension. In `lib-phpini.sh` behoben.
- **Fünf Testfallstricke derselben Klasse „der Test misst nichts und meldet
  trotzdem grün".** Alle fünf haben in diesem Vorhaben schon einmal zugeschlagen:
  **B11** (`opcache.file_update_protection`, 2 s abwarten und
  `num_cached_scripts`/`hits` mitprüfen), **B16** (unter Emulation trägt ein
  FPM-Worker keinen `pool www`-Titel), **B19** (`--entrypoint php` umgeht den
  Entrypoint — dann gibt es keine Laufzeit-INI und man misst Extension-Defaults),
  **B20** (ein leeres Named Volume bekommt beim ersten Mount die Ownership des
  Image-Verzeichnisses zurück), **B21** (busybox-`wget --post-file` setzt POST,
  sendet aber keinen Rumpf — ein Body-Size-Limit lässt sich damit nicht prüfen).
  B20 ist für P11 relevant.
- **B24/B25 — zwei belegte Bestandsdefekte in der nginx-Vorlage, bewusst nicht
  eigenmächtig geändert (O6).** Die `.php`-Fallback-Location hat kein
  `try_files` — der klassische `/upload.jpg/x.php`-Pfad wird derzeit allein von
  `security.limit_extensions` des php-fpm abgefangen (gemessen: 403, kein Code
  ausgeführt). Und statische Dateien bekommen **keinen** Security-Header, weil
  ein `add_header` in der Location die fünf Server-Header verdrängt (gemessen).
  Beides ist je eine Zeile und gehört zur Härtung (A7).
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
  Remote, kein Push, keine Archivierung. Commits sind **freigegeben** (neun
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
