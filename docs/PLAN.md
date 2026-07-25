# Plan — Konsolidierung des PHP-Docker-Image-Builders

- **Bezug:** `docs/PRD.md` (bestätigt 2026-07-25)
- **Zielort:** `/Users/Rolf/Development/headgent/devops/docker/php-image-builder/` (lokal, eigenes Git-Repo)
  - Geändert am 2026-07-25 auf Anordnung des Users; vorher war `image/docker-php-builder/` vorgesehen. Damit ist auch der Projekt- und künftige Repo-Name festgelegt: **`php-image-builder`** (löst den Arbeitsnamen `docker-php-builder` aus E8 ab).
  - PRD, Plan, Progress und Handover liegen seit demselben Zeitpunkt unter `docs/` **im** neuen Repo und sind damit mitversioniert. Die Vorläuferdokumente (`anforderungen-docker-image-builder.md`, `REQUIREMENTS_ANALYSE.md`) bleiben unter `devops/image/` liegen.
  - Der Bestandscode liegt weiterhin unter `devops/image/phpcli/` und `devops/image/phpfpm/`.
- **Pfad:** Voll-Pfad

---

## Bauform — beibehalten und optimieren

Die Struktur der beiden Bestands-Repos bleibt erhalten. Übernommen wird jeweils die reifere der beiden Varianten:

| Element | Herkunft | Begründung |
|---|---|---|
| Root-`Makefile` mit `include` der Module | beide | identisch aufgebaut |
| `support/makefiles/` (Plural) | phpfpm | feinere Aufteilung (5 statt 3 Dateien) |
| `.env` im Repo-Root als Single Source of Truth | phpfpm | phpcli hat sie unter `src/`, was den Build-Kontext verunreinigt |
| `##@`-Sektionen + `##`-Hilfetexte, awk-Hilfe | beide | identisch |
| Strukturiertes `info`-Target | phpfpm | übersichtlicher als die Flachliste in phpcli |
| `CACHE_BACKEND`-System (auto/gha/registry/local/none) | phpcli | phpfpm hat nichts Vergleichbares |
| Datums-Tags (`IMAGE_DATE`) | phpfpm | fehlt in phpcli |
| `.hadolint.yaml` | phpfpm | fehlt in phpcli |
| `ssh.mk` | beide | unverändert |

**Optimierungen:**

1. `docker-bake.hcl` ersetzt die duplizierte `buildx`-Schleifenlogik in `docker.build.*.mk`; die Make-Targets werden dünne Wrapper um `bake`.
2. phpcli baut lokal über `docker compose`, phpfpm über `buildx` — künftig einheitlich über `bake`.
3. `src/.env` (phpcli) und `.env` (phpfpm) werden zu **einer** Datei im Root.
4. Die `PHP_VERSIONS`/`LATEST`-Ableitung wird einmal in `docker.helper.mk` definiert statt zweimal unterschiedlich.

## Zielstruktur

```
php-image-builder/
├── docs/                         # PRD, PLAN, PROGRESS, HANDOVER (mitversioniert)
├── .env                          # Single Source of Truth (Build + Runtime-Defaults)
├── .dockerignore
├── .hadolint.yaml
├── .gitignore
├── LICENSE
├── Makefile
├── docker-bake.hcl
├── README.md
├── .github/
│   ├── CODEOWNERS
│   └── workflows/ci.yml
├── support/makefiles/
│   ├── docker.helper.mk          # Namen, Versionen, Cache-Backend, buildx-Setup
│   ├── docker.build.local.mk     # bake --load
│   ├── docker.build.push.mk      # bake --push (multi-arch)
│   ├── test.mk                   # Extension-/OPcache-/UID-/Boot-Tests
│   └── ssh.mk
├── src/
│   ├── shared/
│   │   ├── php-extensions.env    # Extension-Liste, von base + frankenphp gelesen
│   │   └── entrypoint/
│   │       ├── entrypoint.sh     # gemeinsamer Kern
│   │       ├── lib-user.sh       # UID/GID-Angleichung (A4)
│   │       └── lib-phpini.sh     # APP_ENV-Profile + INI-Erzeugung (A10)
│   ├── base/Dockerfile
│   ├── cli/Dockerfile
│   ├── fpm/
│   │   ├── Dockerfile
│   │   └── fpm-pool.sh           # target-spezifische Ergänzung
│   └── frankenphp/Dockerfile
└── compose/
    ├── demo-stack.yml            # mysql + fpm + offizielles nginx
    ├── demo-frankenphp.yml       # Profil-Variante
    └── nginx/templates/
        └── default.conf.template # vollständig parametrisiert (A6)
```

---

## Phasen

Abhängigkeiten sind strikt sequenziell, wo nicht anders vermerkt. Parallelisierung entfällt durchweg: alle Phasen teilen sich dieselbe QA-Infrastruktur (Docker-Daemon, feste Image-Namen, Ports) — die QA-Infrastruktur-Falle aus §3.3 greift.

| # | Phase | Liefert | Akzeptanz | Hängt an |
|---|---|---|---|---|
| P1 | Repo-Gerüst + konsolidierte `.env` | Verzeichnisstruktur, `.env` mit vereinheitlichten Schlüsseln, `Makefile`-Skelett, `.gitignore`/`.dockerignore`/`.hadolint.yaml`, `LICENSE`, `git init` | `make info` zeigt alle Werte; kein Schlüssel doppelt; D2/D16 aufgelöst | — |
| P2 | Gemeinsamer Entrypoint-Kern | `entrypoint.sh`, `lib-user.sh`, `lib-phpini.sh` | Shellcheck sauber; UID-Logik behandelt U1–U3; `APP_ENV`-Profile nach A10 inkl. JIT-Automatik | P1 |
| P3 | `base`-Target | `src/base/Dockerfile`, `php-extensions.env` | Baut lokal; alle Extensions geladen; `pcntl` enthalten (E5) | P2 |
| P4 | `cli`-Target | `src/cli/Dockerfile` | `FROM base`; Extensions vollständig; Entrypoint aus P2 | P3 |
| P5 | `fpm`-Target | `src/fpm/Dockerfile`, `fpm-pool.sh` | `FROM base`; FPM-Ping antwortet; Pool-Config erzeugt | P3 |
| P6 | `docker-bake.hcl` + Make-Targets | Bake-Matrix, `docker.helper.mk`, `docker.build.local.mk`, `docker.build.push.mk` | `docker buildx bake` baut base/cli/fpm in einem Lauf; ein Versionsstring treibt alle Tags | P4, P5 |
| P7 | `frankenphp`-Target | `src/frankenphp/Dockerfile` | Baut; liefert HTTP im Request-Modus; Extension-Menge = `base` | P6 |
| P8 | Tests | `test.mk` inkl. Extension-, OPcache-/JIT-, `APP_ENV`- und UID-Tests | `make test-all` grün; UID-Test deckt Host-UID ≠ 1000, belegte Ziel-GID, root-Volume ab | P7 |
| P9 | nginx-Config als Asset | `compose/nginx/templates/default.conf.template` | Vollständig parametrisiert (A6.1–A6.2); läuft mit unverändertem offiziellem Image | P1 |
| P10 | Demo-Stack | `compose/demo-stack.yml`, `compose/demo-frankenphp.yml` | `docker compose up` ohne Nacharbeit; Health-Checks; beide Profile | P7, P9 |
| P11 | CI-Pipeline + Härtung | `.github/workflows/ci.yml`, OCI-Labels, Trivy, SBOM/Attestations | Ein Workflow; `base`-Änderung baut alle Targets; Trivy blockiert CRITICAL/HIGH; UID-Test läuft auf Linux-Runner | P8 |
| P12 | Doku + Abschluss | `README.md`, `.claude/CLAUDE.md` | Akzeptanz-Gate gegen alle AK1–AK15 | alle |

### Anmerkungen zum Schnitt

- **P2 ist die Schlüsselphase.** Entrypoint-Kern, UID-Fix und `APP_ENV` hängen zusammen und werden gemeinsam gebaut; eine Aufteilung würde nur Nahtstellen erzeugen.
- **P4/P5 sind datei-disjunkt**, aber nicht parallelisierbar (gemeinsamer Docker-Daemon, `base`-Image als geteilte Ressource).
- **P9 hängt nur an P1** und könnte früher laufen; sie bleibt hinten, weil sie für den Demo-Stack (P10) gebraucht wird und sonst nichts blockiert.
- **Der UID-Nachweis (AK4) ist erst in P11 vollständig**, weil er einen Linux-Runner braucht — auf macOS ist der Fehler prinzipiell unsichtbar. P8 liefert den Test, P11 den Nachweis.

## Verbleibende Detailentscheidung

`headgent/frankenphp` als Image-Name (O1) — wird in P7 gesetzt, bis dahin änderbar.
