# PRD — Konsolidierung des PHP-Docker-Image-Builders

- **Status:** Entwurf, noch nicht bestätigt
- **Datum:** 2026-07-25
- **Pfad-Einstufung:** Voll-Pfad (`project-workflow.md`, Schritt 0)
  - Trigger 2: publizierte Artefakte mit externen Konsumenten (`headgent/phpcli`, `headgent/phpfpm`, `headgent/nginx`)
  - Trigger 3: neue Architektur (Bake-Matrix, gemeinsames `base`-Target, neues FrankenPHP-Target)
  - Trigger 4: deutlich mehr als 3 Phasen
- **Technologie-Track:** nur Backend/Infrastruktur (kein FE-Build-Manifest im Scope)
- **Vorläufer-Dokumente:** `anforderungen-docker-image-builder.md`, `REQUIREMENTS_ANALYSE.md`

---

## 1 · Ausgangslage (verifizierter Ist-Zustand)

Zwei eigenständige Git-Repos mit eigenen Remotes:

| Repo | Remote | Baut |
|---|---|---|
| `image/phpcli` | `git@github.com:jardisOps/phpcli.git` | `headgent/phpcli` |
| `image/phpfpm` | `git@github.com:jardisOps/phpfpm.git` | `headgent/phpfpm`, `headgent/nginx` |

Beide bauen PHP 8.2/8.3/8.4 auf Alpine 3.23, multi-arch (amd64/arm64), mit identischen PECL-Versionen (apcu 5.1.28, redis 6.3.0, xdebug 3.5.1, pcov 1.0.12, amqp 2.2.0, rdkafka 6.0.5). Die Entrypoints sind zu rund 80 % identischer Code.

### 1.1 Belegte Drift zwischen den Stacks

| # | Punkt | phpcli | phpfpm |
|---|---|---|---|
| D1 | `pcntl` | installiert | fehlt (laut `.claude/CLAUDE.md` bewusst) |
| D2 | PECL-Redis-Variablenname | `REDIS_VERSION` | `REDIS_PECL_VERSION` |
| D3 | `OPCACHE_VALIDATE_TIMESTAMPS` | fehlt komplett | vorhanden, `=0` |
| D4 | `XDEBUG_IDEKEY` | fehlt | vorhanden |
| D5 | `INSTALL_DB_CLIENTS` | vorhanden | fehlt |
| D6 | Konfigurations-Muster | ENV fest im Dockerfile | ARG → ENV aus `.env` |
| D7 | Unix-Gruppenname | `appgroup` | `appuser` |
| D8 | `apk upgrade` im Build-Stage | vorhanden | fehlt |
| D9 | Default `XDEBUG_MODE` | `debug` | `off` |
| D10 | Default `PHP_MAX_EXECUTION_TIME` | `0` | `30` |
| D11 | Default `OPCACHE_REVALIDATE_FREQ` | `2` | `0` |
| D12 | Makefile-Verzeichnis | `support/makefile/` | `support/makefiles/` |
| D13 | CI `id-token`/`attestations` | vorhanden | fehlt (= Lücke L3 der Analyse) |
| D14 | CI Trivy-Scan | fehlt | vorhanden (`continue-on-error: true`) |
| D15 | `.hadolint.yaml` | fehlt | vorhanden |
| D16 | `COMPOSER_VERSION`-Default im Dockerfile | `2.9.3` hartkodiert, `.env` sagt `2.9.5` | kein Default (bewusst) |

D16 ist ein latenter Defekt: Wird `phpcli` ohne expliziten Build-Arg gebaut, greift der Dockerfile-Default 2.9.3 statt des in `.env` gepflegten Werts 2.9.5.

### 1.2 Belegte Defekte in der UID/GID-Behandlung

Betrifft `phpcli/src/entrypoint.sh:5-11` und `phpfpm/src/php/entrypoint.sh:7-13` gleichermaßen. Symptomatisch auf Linux, unter macOS durch die VM-Dateisystembrücke verdeckt.

| # | Ursache | Wirkung |
|---|---|---|
| U1 | `groupmod -g` / `usermod -u` scheitern bei belegter Ziel-ID; `2>/dev/null \|\| true` verschluckt den Fehler | Anpassung findet nicht statt, Fehler erscheint später als unerklärliches „Permission denied". Alpine belegt u.a. GID 20 (`dialout`) und GID 100 (`users`) — beides häufige Host-GIDs |
| U2 | Bedingung `[ "$HOST_UID" != "0" ]` überspringt die Anpassung bei root-eigenem `/app` | Docker legt frische Named Volumes als `root:root` an → `appuser` bleibt bei 1000 und kann nicht schreiben |
| U3 | `usermod -u` zieht keinen `chown` nach | Dateien, die vorher `appuser` gehörten, verwaisen bei der alten UID. Nachgezogen wird nur `/home/appuser` (+ `/run/php-fpm` bei FPM) |

### 1.4 Bewertung der bestehenden Xdebug/PCOV/JIT-Lösung

**Tragfähiger Kern, wird ausgebaut statt ersetzt** (E10):

- PCOV/Xdebug-Konfliktauflösung im Entrypoint (`phpcli:14`, `phpfpm:18`) — verhindert einen klassischen Fehler ohne Nutzerwissen
- Bewusste INI-Ladereihenfolge: `docker-php-ext-opcache.ini` → `00-opcache.ini` (`Dockerfile:112-114`), damit OPcache als zend_extension vor Xdebug lädt; `99-runtime-config.ini` lädt garantiert zuletzt
- Symlink von `/home/appuser/php-config/` nach `conf.d/` (`Dockerfile:128`) — Entrypoint schreibt als `appuser`, ohne `conf.d` beschreibbar zu machen
- Extensions immer geladen, nur inaktiv gestellt — kein Rebuild beim Umgebungswechsel

**Lücken:**

| # | Lücke | Wirkung |
|---|---|---|
| L-A | JIT wird bei aktivem Xdebug nicht abgeschaltet; Entrypoint schreibt `opcache.jit=1254` und `xdebug.mode=debug` gemeinsam | PHP schaltet JIT selbst ab und warnt bei **jedem** Aufruf — bei `phpcli` ist das der Default-Zustand |
| L-B | Der Default `XDEBUG_MODE=debug` wird in **jedem** Test überschrieben (`test.mk:13,108,130,142`) | Ein Default, der überall abgeschaltet werden muss, ist ein Modus ohne Schalter |
| L-C | `opcache.validate_timestamps=0` in `phpfpm`, in `phpcli` gar nicht gesetzt | FPM bemerkt Code-Änderungen im Entwicklungsbetrieb nicht; Container-Neustart nach jeder Änderung nötig |
| L-D | `display_errors=Off` in beiden `.env` | Für Entwicklung falscher Default |
| L-E | Keine Validierung der ENV-Werte | Ein Tippfehler landet ungeprüft in der INI |
| L-F | Kein Schutz gegen aktives Xdebug in Produktion | `REQUIREMENTS_ANALYSE.md` §4.3 benennt das Risiko und delegiert es an einen CI-Check, der nicht existiert |
| L-G | `E_STRICT` in `PHP_ERROR_REPORTING` | Seit PHP 8.0 bedeutungslos (Legacy) |

**Fragiler, aber korrekter Mechanismus:** `XDEBUG_MODE=off` wird ohne `export` gesetzt und wirkt trotzdem auf Kindprozesse, weil die Variable aus der Image-`ENV` stammt und ihr Export-Attribut behält. Das ist relevant, weil Xdebug 3 die Umgebungsvariable liest und ihr **Vorrang vor der INI-Einstellung** gibt. Der Mechanismus muss beim Umbau explizit werden (A10.5).

Der Anwender hat U1/U2 als das erinnerte Linux-Problem bestätigt. Alle drei werden behandelt, da alle drei belegte Defekte sind.

### 1.3 Befund zu nginx — Prämisse des Vorläuferdokuments trifft nicht zu

`anforderungen-docker-image-builder.md` §1 nimmt an, die nginx-Config werde zur Build-Zeit erzeugt. Tatsächlich läuft `envsubst` bereits zur **Laufzeit** (`phpfpm/src/nginx/entrypoint.sh:11`). Die Punkte 1–2 aus §3.3 jenes Dokuments sind damit gegenstandslos.

Der einzige echte Build-Zeit-Grund ist der PUID/PGID-Umbau (`phpfpm/src/nginx/Dockerfile:9-21`).

Zweiter Befund: Die Template-Config ist **unvollständig parametrisiert**. Substituiert werden nur `HOST`, `APP_ROOT`, `DOCUMENT_ROOT`, `INDEX_FILE`, `PHP_PORT`. Hartkodiert sind dagegen:

| Wert | Fundstelle | Problem |
|---|---|---|
| Upstream-Host `app:` | `default.conf.template:92,121` | Das im Vorläuferdokument genannte `FASTCGI_UPSTREAM` existiert nicht |
| `client_max_body_size 100m` | `:18` | Nicht überschreibbar |
| Sämtliche fastcgi-Timeouts | `:107-109,133-135` | Nicht überschreibbar |
| `fastcgi_param HTTPS on` / `REQUEST_SCHEME https` | `:101-103,127-129` | Fest auf TLS-Terminierung durch Traefik gemünzt; in einem Stack ohne vorgelagerten Proxy schlicht falsch |

---

## 2 · Zielbild

**Ein** Builder-Repo, das per Matrix-Build alle Artefakte aus einer gemeinsamen Konfiguration erzeugt.

| Target | Publiziert als | Basis | Zweck |
|---|---|---|---|
| `base` | — (nicht publiziert) | offizielles `php:X-alpine` | Single Source of Truth: PHP-Version, Extensions, Composer |
| `cli` | `headgent/phpcli` | `base` | Worker, Queue-Consumer, Cron, CI/Build-Kontext |
| `fpm` | `headgent/phpfpm` | `base` | php-fpm-only, Sidecar-Pattern |
| `frankenphp` | `headgent/frankenphp` *(Name offen, O1)* | eigenständig | Single-Process HTTP im klassischen Request-Modus |

**nginx ist kein Build-Target mehr** (E9). Geliefert wird stattdessen die Template-Konfiguration als versioniertes Asset, das mit dem unveränderten offiziellen Image verwendet wird.

---

## 3 · Getroffene Entscheidungen

| # | Entscheidung | Begründung |
|---|---|---|
| E1 | **Ein Builder-Repo** ersetzt die zwei bestehenden | Kernziel des Vorhabens |
| E2 | **Image-Namen bleiben unverändert** (`headgent/phpcli`, `headgent/phpfpm`, `headgent/nginx`) | Repo-Name und Image-Name sind unabhängig; Konsumenten dürfen nichts merken. `development.md` §6: publizierte Reihen laufen nur vorwärts |
| E3 | **Kein combined Image** (php-fpm + nginx in einem Container) | Verworfen zugunsten von FrankenPHP. Combined bräuchte einen Prozess-Manager (s6/supervisord) und löst dasselbe Problem, das FrankenPHP ohne diesen Aufwand löst |
| E4 | **FrankenPHP im klassischen Request-Modus** ist die Kernanforderung. Der Worker-Mode ist ausdrücklich **kein** Teil dieses Vorhabens | Reduziert Umfang und Risiko. Der Worker-Mode bleibt das mittelfristige Ziel (er hält die Anwendung zwischen Requests im Speicher und passt zum Koffer-/DomainKernel-Muster: Bootstrap einmal, dann Request-Loop), wird hier aber nur *nicht verbaut* — siehe A5.2 |
| E5 | **`pcntl` kommt nach `base`**, also auch in `fpm` | Kostet zur Laufzeit nichts; das bisherige Weglassen ist ein Nutzungs-, kein Sicherheitsargument. Hebt D1 auf |
| E6 | **Gemeinsame Basis, begründete Deltas** bei der Konfiguration | Extensions, PECL-Versionen, Variablennamen und Entrypoint-Kern sind für alle Targets identisch. Unterschiedlich bleiben nur Werte, die aus dem Einsatzzweck folgen (D10: CLI-Worker will kein Web-Timeout) — jedes verbleibende Delta wird im Plan einzeln begründet |
| E7 | **UID/GID-Behandlung wird strukturell neu gebaut**, nicht gepatcht | U1–U3 sind Symptome eines heuristischen Ansatzes. Zielbild: Zweiwege-Entrypoint (siehe A4) |
| E8 | **Neues Repo** unter `jardisOps/`; die beiden bestehenden werden archiviert, nicht gelöscht | Git-History bleibt erhalten, keine Verwirrung über den gültigen Build-Ort. **Name festgelegt am 2026-07-25: `php-image-builder`** (löst den Arbeitsnamen `docker-php-builder` ab), lokal unter `devops/docker/php-image-builder/` |
| E10 | **Xdebug, PCOV und JIT bleiben fest eingebaut**; die Aktivierung erfolgt über `APP_ENV` (A10) | Der Ein-Image-Ansatz bleibt (O5, gestützt auf `REQUIREMENTS_ANALYSE.md` §4.3). Die bestehende Entrypoint-Lösung ist im Kern gut — PCOV/Xdebug-Konfliktauflösung, bewusste INI-Ladereihenfolge (`00-opcache.ini` vor Xdebug), Symlink für schreibbare Runtime-INI — und wird ausgebaut statt ersetzt. `APP_ENV` löst zugleich die Default-Drift D9/D10/D11 auf: heute ist `phpcli` in seinen Defaults ein Entwicklungs-, `phpfpm` ein Produktionsimage |
| E9 | **nginx entfällt als Build-Target.** Geliefert wird die Template-Config als Asset, verwendet mit dem unveränderten offiziellen Image | Dieses Repo baut PHP-Laufzeiten; nginx ist keine — dieselbe Grenze, aus der heraus auch keine Datenbank-Images gebaut werden. Die beiden historischen Build-Gründe tragen nicht mehr: (a) `envsubst` kann das offizielle Image seit 1.19 selbst (`/docker-entrypoint.d/20-envsubst-on-templates.sh`), der eigene Entrypoint dupliziert es; (b) der PUID/PGID-Umbau war nie nötig, weil nginx `/app` nur **liest** — Lesen braucht keine identische UID, sondern Leserechte. Für den Sonderfall restriktiver Rechte genügt `user:` im Compose oder `nginxinc/nginx-unprivileged` |

---

## 4 · Anforderungen

### A1 — Konsolidiertes Repo mit Matrix-Build

- A1.1 Ein Repo enthält alle Targets aus Abschnitt 2.
- A1.2 `docker buildx bake` baut alle Targets in einem Durchlauf; `cli` und `fpm` beziehen `base` über `contexts = { base = "target:base" }`, ohne dass `base` publiziert wird.
- A1.3 Ein einziger Versionsstring treibt alle Tags gleichzeitig, sodass Konsumenten konsistente Kombinationen referenzieren können.
- A1.4 Die bestehenden Makefile-Einstiege bleiben als bedienbare Oberfläche erhalten (ein Verzeichnis, nicht zwei — hebt D12 auf).

### A2 — Eine Konfigurationsquelle

- A2.1 Eine `.env` speist alle Targets; kein Wert ist an zwei Stellen gepflegt.
- A2.2 Die Extension-Liste liegt in einer geteilten Definition, die `base` **und** der FrankenPHP-Build lesen (verhindert Drift).
- A2.3 Variablennamen sind über alle Targets identisch (hebt D2 auf).
- A2.4 Kein Dockerfile trägt einen hartkodierten Versions-Default, der die `.env` überstimmen kann (hebt D16 auf).
- A2.5 Jede beim Konsolidieren verbleibende Delta-Konfiguration ist im Plan namentlich begründet (D3, D4, D5, D9, D10, D11).

### A3 — Gemeinsamer Entrypoint-Kern

- A3.1 Der zu ~80 % duplizierte Entrypoint-Code existiert genau einmal.
- A3.2 Target-spezifische Anteile (FPM-Pool-Generierung) sind als klar abgegrenzte Ergänzung realisiert, nicht als Kopie.
- A3.3 Der Unix-Gruppenname ist über alle Targets einheitlich (hebt D7 auf).

### A4 — UID/GID-Behandlung, die auf Linux trägt

- A4.1 Läuft der Container als root, wird `appuser` an den Eigentümer von `/app` angepasst — mit **echter** Fehlerbehandlung: eine bereits belegte Ziel-GID/UID führt zur Wiederverwendung der existierenden Kennung oder zu einem sichtbaren, klaren Fehler, **nie** zum stillen Verschlucken (behebt U1).
- A4.2 Der Fall „`/app` gehört root" (frisches Named Volume) wird explizit behandelt statt übersprungen (behebt U2).
- A4.3 Nach einer UID/GID-Änderung sind alle vom Image angelegten, `appuser` zugeordneten Pfade nachgezogen (behebt U3).
- A4.4 Wird der Container von außen bereits mit `--user <uid>:<gid>` gestartet, unternimmt der Entrypoint keine Anpassung und das Image funktioniert dennoch mit einer im Image unbekannten UID.
- A4.5 Das Verhalten ist auf Linux mit Host-UID ≠ 1000, mit belegter Ziel-GID und mit frischem Named Volume nachweislich geprüft.

### A5 — FrankenPHP als Docker-Image

- A5.1 Das Image läuft im klassischen Request-Modus und ersetzt darin funktional die Kombination fpm+nginx.
- A5.2 Der Worker-Mode ist **nicht** Teil des Lieferumfangs. Es wird lediglich sichergestellt, dass seine spätere Aktivierung keine Umstellung des Images erzwingt (kein Aufbau, der ihn strukturell ausschließt). Ob darüber hinaus etwas vorbereitet wird, entscheidet der Plan nach Aufwand.
- A5.3 Das Image trägt dieselbe Extension-Menge wie `base` und bezieht sie aus derselben geteilten Definition (A2.2).

### A6 — nginx-Konfiguration als Asset statt als Image

- A6.1 Upstream-Host, Body-Size und die fastcgi-Timeouts sind parametrisiert statt hartkodiert.
- A6.2 Die feste HTTPS-Annahme (`fastcgi_param HTTPS on`, `REQUEST_SCHEME https`) ist schaltbar, sodass der Betrieb ohne vorgelagerten TLS-Proxy korrekt ist.
- A6.3 Das Template liegt so im Repo, dass es vom **unveränderten** offiziellen nginx-Image über dessen eingebaute Substitution (`NGINX_ENVSUBST_TEMPLATE_DIR`) verarbeitet wird — ohne eigenen Entrypoint und ohne eigenen Build.
- A6.4 Alle im Template verwendeten Variablen haben dokumentierte Defaults, sodass das Ergebnis ohne Konfiguration lauffähig ist.
- A6.5 `headgent/nginx` wird ersatzlos nicht mehr gebaut. Ein Deprecation-Pfad ist nicht erforderlich — es gibt keine Konsumenten (bestätigt 2026-07-25). Das bestehende Image bleibt in der Registry liegen, ohne Pflegezusage.

### A10 — `APP_ENV` als Umgebungsschalter

Xdebug, PCOV und OPcache/JIT bleiben in allen Targets fest eingebaut (E10). Ihre Aktivierung wird über **eine** Variable gesteuert statt über heute fünf einzelne.

- A10.1 `APP_ENV` mit den Werten `dev`, `test`, `prod` setzt ein konsistentes Profil aus Xdebug-, PCOV-, OPcache-, JIT- und Fehleranzeige-Einstellungen.
- A10.2 **Vorrangregel:** eine explizit gesetzte Einzelvariable (z. B. `XDEBUG_MODE`) schlägt das Profil; das Profil schlägt den Fallback. Die heutige Feinsteuerung bleibt damit vollständig erhalten.
- A10.3 Die bestehende PCOV/Xdebug-Konfliktauflösung bleibt erhalten und wird um eine **JIT-Automatik** ergänzt: ist Xdebug aktiv, wird `opcache.jit` explizit abgeschaltet, statt PHP die Abschaltung samt Warnung selbst vornehmen zu lassen (behebt L-A).
- A10.4 Bei `APP_ENV=prod` führt ein aktives Xdebug zu einem sichtbaren Abbruch statt zu stiller Übernahme — schließt das Fehlkonfigurations-Risiko aus `REQUIREMENTS_ANALYSE.md` §4.3 im Image selbst, statt es an einen CI-Check zu delegieren.
- A10.5 `XDEBUG_MODE` wird vom Entrypoint **explizit exportiert**, weil Xdebug 3 die Umgebungsvariable liest und ihr Vorrang vor der INI-Einstellung gibt. Heute funktioniert das nur implizit, weil die Variable aus der Image-`ENV` stammt und ihr Export-Attribut behält.
- A10.6 `opcache.validate_timestamps` ist in allen Targets gesetzt und profilabhängig: `1` in `dev`/`test`, `0` in `prod` (behebt D3 und die heutige Situation, dass FPM Code-Änderungen im Entwicklungsbetrieb nicht bemerkt).
- A10.7 Ein ungültiger Wert in `APP_ENV` oder in einer der Profilvariablen führt zu einem klaren Fehler beim Start, nicht zu einer stillschweigend falschen INI.

### A7 — Härtung aus der Requirements-Analyse

Die dort als H1–H6 priorisierten Maßnahmen werden im konsolidierten Repo umgesetzt:

- A7.1 CVE-Scanning (Trivy) in der CI für **alle** Targets, CRITICAL/HIGH blockieren den Push (H1; hebt D14 auf, das heute `continue-on-error` ist).
- A7.2 SBOM-Attestation für alle Targets (H2).
- A7.3 CI-Permissions `id-token: write` + `attestations: write` für alle Build-Jobs (H3; hebt D13 auf).
- A7.4 OCI-Labels `org.opencontainers.image.{source,version,revision,created}` in allen Dockerfiles (H4).
- A7.5 `.dockerignore` für alle Build-Kontexte (H5).
- A7.6 H6 (nginx `apk upgrade` + Healthcheck) entfällt in seiner ursprünglichen Form, da kein nginx mehr gebaut wird — der Patch-Stand kommt mit dem offiziellen Image. Der Healthcheck wandert in den Demo-Stack (A8.2).
- A7.7 `apk upgrade` auch im Build-Stage aller PHP-Targets (H10; hebt D8 auf).
- A7.8 `.hadolint.yaml` gilt für alle Dockerfiles (hebt D15 auf).

### A8 — Demo-Stack

- A8.1 Ein Compose-Stack (mysql/mariadb, php-fpm, nginx) startet ohne manuelle Nacharbeit mit `docker compose up`. Datenbank **und** nginx laufen dabei als unveränderte offizielle Images — der Stack demonstriert damit zugleich den Weg, den Projekte gehen sollen.
- A8.2 Health-Checks für alle Services.
- A8.3 Die nginx-Template-Variablen aus A6 sind exemplarisch befüllt.
- A8.4 Ein zweites Profil setzt FrankenPHP statt fpm+nginx ein, sodass beide Architekturen vergleichbar sind.

### A9 — CI-Pipeline

- A9.1 Ein Workflow ersetzt die beiden bestehenden.
- A9.2 Eine Änderung an `base` löst den Neubau **aller** abhängigen Targets aus.
- A9.3 Die heutigen Trigger bleiben erhalten (push/PR/dispatch/scheduled inkl. Keepalive-Job).

---

## 5 · Nicht-Ziele

| # | Ausgeschlossen | Grund |
|---|---|---|
| N1 | Combined Image (php-fpm + nginx in einem Container) | E3 |
| N2 | Wechsel auf Docker Hardened Images | `REQUIREMENTS_ANALYSE.md` §5.1; als Upgrade-Pfad vorgemerkt |
| N3 | Umbenennung der publizierten Image-Namen | E2 |
| N4 | Migration der Konsumenten-Projekte | Nicht Teil dieses Repos |
| N5 | Optionale Härtungen H7–H9 (SHA-Pinning, `clear_env`) | Niedrige Priorität; nach Abschluss erneut bewerten |
| N6 | **Statisches FrankenPHP-Executable** als portables Binary und Release-Asset | Aufwendigster und unsicherster Teil des Vorläuferzuschnitts (eigener Build-Pfad über `static-php-cli`, unbelegte Extension-Verfügbarkeit bei `rdkafka`/`amqp`/`xdebug`, zusätzliches Release-Publishing) — zahlt auf keins der vier Ziele ein. Jederzeit nachrüstbar, sinnvollerweise gemeinsam mit dem Worker-Mode (E4) |
| N7 | **FrankenPHP Worker-Mode** | E4 |

---

## 6 · Offene Punkte

| # | Frage | Vorschlag | Blockiert |
|---|---|---|---|
| O1 | Image-Name für FrankenPHP | `headgent/frankenphp` | A5 |
| ~~O2~~ | ~~Bleibt `headgent/nginx` als eigenständiges Image bestehen?~~ | **Entschieden:** nein, siehe E9 und A6. `headgent/nginx` hat keine Konsumenten, daher entfällt auch ein Deprecation-Pfad | — |
| ~~O3~~ | ~~Statisches Executable und dessen Extension-Verfügbarkeit~~ | **Entschieden:** entfällt, siehe N6 | — |
| ~~O4~~ | ~~Name und Ort des neuen Repos~~ | **Entschieden:** neues Repo (Name siehe E8), `jardisOps/phpcli` und `jardisOps/phpfpm` werden archiviert statt gelöscht — History bleibt erhalten | — |
| ~~O5~~ | ~~Bleibt Xdebug/PCOV in allen Targets geladen?~~ | **Entschieden:** ja, fest eingebaut, Aktivierung über `APP_ENV` — siehe E10 und A10 | — |

---

## 7 · Akzeptanzkriterien

- [ ] AK1 — Ein Repo baut alle Targets aus Abschnitt 2 mit einem `docker buildx bake`-Aufruf.
- [ ] AK2 — `base`, `cli` und `fpm` teilen nachweislich **eine** PHP-Versions- und Extensions-Definition; kein Wert ist doppelt gepflegt.
- [ ] AK3 — Kein Image-Name hat sich geändert; `headgent/phpcli` und `headgent/phpfpm` sind mit der neuen Versionsreihe fortsetzbar.
- [ ] AK4 — Der UID/GID-Nachweis aus A4.5 ist erbracht: Host-UID ≠ 1000, belegte Ziel-GID und frisches Named Volume funktionieren auf Linux.
- [ ] AK5 — FrankenPHP liegt als lauffähiges Docker-Image im klassischen Request-Modus vor und bedient denselben Anwendungsfall wie fpm+nginx.
- [ ] AK6 — Das FrankenPHP-Image trägt dieselbe Extension-Menge wie `cli` und `fpm`, aus derselben Definition bezogen.
- [ ] AK7 — Die nginx-Config enthält keine hartkodierten Werte mehr aus der Liste in 1.3, der Betrieb ohne TLS-Proxy ist korrekt, und sie läuft mit dem **unveränderten** offiziellen Image ohne eigenen Entrypoint.
- [ ] AK8 — H1–H5 plus H10 sind umgesetzt; Trivy blockiert bei CRITICAL/HIGH und läuft nicht mehr mit `continue-on-error`.
- [ ] AK9 — Der Demo-Stack startet mit `docker compose up` ohne Nacharbeit; das FrankenPHP-Profil ebenfalls.
- [ ] AK10 — Ein CI-Workflow ersetzt beide bestehenden; eine `base`-Änderung baut alle abhängigen Targets neu.
- [ ] AK11 — Jede in Abschnitt 1.1 gelistete Drift ist entweder aufgehoben oder als bewusstes Delta begründet.
- [ ] AK13 — `APP_ENV=dev|test|prod` setzt in allen Targets ein konsistentes Profil; eine explizit gesetzte Einzelvariable schlägt das Profil weiterhin.
- [ ] AK14 — Bei aktivem Xdebug erscheint **keine** JIT-Warnung mehr (L-A behoben), und `APP_ENV=prod` mit aktivem Xdebug bricht sichtbar ab (L-F behoben).
- [ ] AK15 — Im `dev`-Profil bemerkt auch das FPM-Target Code-Änderungen ohne Container-Neustart (L-C behoben).
- [ ] AK12 — Das Repo baut kein nginx-Image mehr; der Demo-Stack belegt, dass das offizielle Image mit der gelieferten Config auskommt.
