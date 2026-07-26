# Handover — Konsolidierung des PHP-Docker-Image-Builders

**Stand:** 2026-07-26, Ende der sechsten Umsetzungs-Session. **P1–P6, P8–P10 und
O6 abgeschlossen**, **P11 weit gediehen** (Workflow geschrieben, **AK4 erbracht**),
**P7 ist entfallen** (E11).

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder/`
Projekt- und künftiger Repo-Name: **`php-image-builder`**.
Bestandscode unverändert unter `devops/image/phpcli/` und `devops/image/phpfpm/`,
Vorläuferdokumente unter `devops/image/`.

---

## Wiedereinstieg — Stand am 2026-07-26

**Offen sind der Rest von P11 (Review + Commit) und P12.** Zehn Einheiten sind
abgeschlossen (P1–P6, P8–P10, O6), P7 ist gestrichen (E11) und die Nummer bleibt frei.

| Punkt | Stand |
|---|---|
| Arbeitsbaum | **sauber**, alles committet (19 Commits, kein Remote, nie gepusht) |
| Prüflauf | **grün, Exit 0** für PHP 8.3 — seit P11 **dreizehn** Stufen; `test-nginx` 55/55, `test-uid-linux` 13/13, shellcheck über 16 Dateien |
| Test-Images | `php-image-builder-test/phpcli:8.3` und `…/phpfpm:8.3` liegen **lokal** — `make test-all` startet damit ohne Neubau |
| Demo-Stack | läuft: `make demo-up` → drei Dienste `healthy` unter `http://localhost:8088`, `make demo-down` hinterlässt nichts |
| Aufgeräumt | keine Testcontainer, -volumes oder -netze übrig; `headgent/*` unberührt |
| **O6** | **umgesetzt und belegt am 2026-07-26** — beide Härtungen an der nginx-Vorlage (B24/B25) stehen, `test-nginx` 55/55, Gegenprobe gefahren |
| **P11** | **grösstenteils geliefert:** `.github/workflows/ci.yml` (vier Jobs, alle Trigger, `publish` abgeschaltet), OCI-Labels, drei neue Prüfstufen. **AK4 ist erbracht** — Details in PROGRESS „P11 — in Arbeit" |
| **AK4** | **erledigt.** Nachweis in einem `docker:28-dind`-Linux-Host statt auf einem GitHub-Runner (deine Entscheidung, 2026-07-26). Gegenprobe gegen `headgent/phpcli:8.3` zeigt U1 und U2 erstmals **gemessen** |
| Wartet auf Freigabe | **N6** (erster Push, Tag-Strategie), kein GitHub-Repo, kein Remote, keine Archivierung |

Einstieg: Kurzform:

```sh
cd /Users/Rolf/Development/headgent/devops/docker/php-image-builder
make test-all          # Ausgangslage bestätigen (grün)
make help              # Bedienoberfläche
```

**Womit die nächste Session beginnt — P12:**

1. **P12 — Doku + Abschluss:** `README.md`, `.claude/CLAUDE.md`, Akzeptanz-Gate
   gegen AK1–AK15. Für die README vorgemerkt: **B7** (die drei
   `InvalidDefaultArgInFrom`-Warnungen sind gewollt, nicht behebbar), **B15**
   (Plattenplatz bei `build-all`), **B28** (Host-Port), der Verlust von
   `php-cgi`/`phpdbg` im cli-Image (P3) und der Rückbau von `curl-dev`/
   `oniguruma-dev` (seit B12 vermutlich überflüssig).

**N6 bleibt die harte Grenze:** der Workflow ist geschrieben, aber nicht scharf.
`publish` läuft nur bei `vars.PUBLISH_ENABLED == 'true'` — die Variable
existiert nicht. Kein `docker login`, kein `--push`, keine CI-Auslösung, bis die
Tag-Strategie vorliegt und freigegeben ist.

---

## Die vier Dokumente — in dieser Reihenfolge lesen

| Datei | Inhalt | Vorrang |
|---|---|---|
| `docs/PROGRESS.md` | **Maßgeblich.** Laufender Zustand: P1–P6, P8–P10, O6 und P11 mit Nachweisen, alle Umsetzungsentscheidungen, Befunde **B1–B31**, offene Punkte, nächste Phase | geht bei Widersprüchen vor |
| `docs/PRD.md` | Anforderungen A1–A10, Entscheidungen E1–**E11**, Nicht-Ziele N1–**N8**, Akzeptanzkriterien AK1–AK15, vollständiger Ist-Zustand (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken L-A–L-G) mit Datei- und Zeilenangaben | bestätigt |
| `docs/PLAN.md` | Bauform, Zielstruktur, 12 Phasen mit Abhängigkeiten | freigegeben |
| `docs/HANDOVER.md` | diese Datei — Vorgeschichte und Einstieg | — |

**Der Bestandscode muss nicht neu analysiert werden.** Das PRD trägt ihn
vollständig mit Fundstellen.

---

## Stand

**Neunzehn Commits.** Das Repo hat **kein Remote** und ist nie
gepusht worden.

```
(HEAD)   feat: CI-Workflow, OCI-Labels und der Linux-UID-Nachweis (P11)
01db7bb  feat: nginx-Vorlage gehaertet — try_files und Security-Header (O6)
a3ac9a3  docs: O6 freigegeben, Folgeprompt auf O6 + P11 umgestellt
0c7d7f2  docs: Commit-Zahl und Log im Handover richtigstellen
90b7aeb  feat: Demo-Stack — mariadb + fpm + offizielles nginx (P10)
ca7b87f  docs: Wiedereinstiegs-Block und Phasenzaehlung
c455ca4  docs: update commit count in the handover
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
| P10 Demo-Stack | ✅ mariadb + fpm + offizielles nginx, 21/21, AK9 und AK12 erbracht |
| O6 Härtung der nginx-Vorlage (B24/B25) | ✅ vorgezogen vor P11, `test-nginx` 39 → 55 |
| P11 CI-Pipeline + Härtung | ✅ Workflow, OCI-Labels, AK4, drei neue Prüfstufen; Review gelaufen. **Der Workflow selbst ist nie gelaufen** (N6) |
| **P12 Doku + Abschluss** | **← hier weiter** |

Gebaut und geprüft: `base`, `cli` und `fpm` gegen PHP **8.3, 8.4 und 8.5** — in
**einem** `bake`-Lauf, nativ auf arm64. **amd64 ist seit P6 belegt** (PHP 8.3,
emuliert gebaut, `uname -m` = `x86_64`, fpm `healthy`). Der Linux-Nachweis für
die UID-Behandlung ist seit P11 erbracht (`docker:28-dind`, siehe AK4 oben).

## Bedienung seit P6

```sh
make build                          # cli + fpm für PHP_VERSION aus der .env
make build-all                      # cli + fpm für 8.3 / 8.4 / 8.5, ein Lauf
make demo-up / make demo-down       # Demo-Stack, http://localhost:8088 (seit P10)
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
| `test-lint` | hadolint ×3, shellcheck über **16** Shell-Dateien |
| `test-phpini` | 34 Fälle gegen `lib-phpini.sh`, ohne Container |
| `test-user` | 27 Fälle gegen `lib-user.sh`, in `alpine:3.23` |
| `test-boot` | cli startet, fpm wird `healthy` |
| `test-extensions` | 21 Extensions in cli **und** fpm |
| `test-app-env` | 15 Fälle: AK13, AK14/L-F, A10.2, A10.5, A10.7 |
| `test-uid` | 5 Fälle gegen echte Docker-Volumes (AK4) |
| `test-opcache` | 14 Fälle inkl. **AK15** im laufenden FPM |
| `test-bake` | 8 Fälle gegen die aufgelöste Bake-Definition (A1.2/A1.3/**A9.2/AK10**), ohne Build |
| `test-labels` | 7 Fälle je Image: die OCI-Labels, über `FROM base` vererbt (A7.4) |
| `test-uid-linux` | 13 Fälle gegen einen **echten Linux-Bind-Mount** in `docker:28-dind` (**AK4**) |
| `test-nginx` | **55** Fälle gegen das **unveränderte** offizielle nginx-Image (AK7), zwei Instanzen: nur Defaults / alles überschrieben, seit O6 plus die Härtungs-Prüffälle B24/B25 |
| `test-demo` | 21 Fälle gegen den laufenden Demo-Stack (AK9/AK12, A8.1–A8.3): ein `up --wait`, alle Dienste healthy, DB verbunden, Abbau ohne Reste |

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
| — | **Demo-Stack: `mariadb:11.8`** (LTS, nicht die kurzlebige 11.2 der Jardis-Projekte), Datenbank im `tmpfs`, und der Stack läuft über `make demo-up` mit `--project-directory .` — sonst findet Compose die `.env` im Root nicht (B26) | PROGRESS „P10 → Entscheidungen 1, 3, 4" |
| — | **`make demo-up` fährt bis zum ersten Push die Test-Images.** Die Compose-Datei verweist auf `headgent/phpfpm:<ver>`, wie ein Projekt es schreibt — unter dem Namen liegt bis N6 aber nur der startunfähige Bestand (B9) | PROGRESS „P10 → Entscheidung 5" |

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
- **Sechs Testfallstricke derselben Klasse „der Test misst nichts und meldet
  trotzdem grün".** Alle sechs haben in diesem Vorhaben schon einmal
  zugeschlagen: **B11** (`opcache.file_update_protection`, 2 s abwarten und
  `num_cached_scripts`/`hits` mitprüfen), **B16** (unter Emulation trägt ein
  FPM-Worker keinen `pool www`-Titel), **B19** (`--entrypoint php` umgeht den
  Entrypoint — dann gibt es keine Laufzeit-INI und man misst Extension-Defaults),
  **B20** (ein leeres Named Volume bekommt beim ersten Mount die Ownership des
  Image-Verzeichnisses zurück), **B21** (busybox-`wget --post-file` setzt POST,
  sendet aber keinen Rumpf — ein Body-Size-Limit lässt sich damit nicht prüfen),
  **B27** (`docker compose up --wait` meldet grün für einen Dienst **ohne**
  Healthcheck — in der Gegenprobe belegt). **B20 und B27 sind für P11
  relevant.**
- **B24/B25 — zwei belegte Bestandsdefekte in der nginx-Vorlage, in O6 behoben
  (2026-07-26).** Die `.php`-Fallback-Location hatte kein `try_files` — der
  klassische `/upload.jpg/x.php`-Pfad wurde allein von
  `security.limit_extensions` des php-fpm abgefangen (gemessen: 403). Und
  statische Dateien bekamen **keinen** Security-Header, weil ein `add_header` in
  der Location die sechs Server-Header verdrängte (gemessen). Beides ist je eine
  Zeile und gehört zur Härtung (A7); beides steht jetzt, mit 16 neuen
  Zusicherungen und gefahrener Gegenprobe. Die entscheidende: mit **angehaltenem
  fpm** antwortet die gehärtete Vorlage weiterhin 404, die Bestandsfassung 502 —
  der Request erreicht den Upstream also nachweislich nicht mehr.
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
