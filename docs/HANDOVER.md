# Handover — Konsolidierung des PHP-Docker-Image-Builders

**Stand:** 2026-07-25, Ende der PRD-/Plan-Session. Umsetzung hat noch nicht begonnen.

> **Nachtrag 2026-07-25 (Umsetzungs-Session), gilt vor allen Pfadangaben unten:**
> Der Zielort wurde auf Anordnung des Users verlegt und der Name festgelegt:
> **`/Users/Rolf/Development/headgent/devops/docker/php-image-builder/`**, Projekt- und
> künftiger Repo-Name **`php-image-builder`**. Diese vier Dokumente liegen jetzt unter
> `docs/` in diesem Repo (nicht mehr unter `devops/image/docs/docker-php-builder/`).
> Der Vorgriff `image/docker-php-builder/` (leeres Verzeichnis, leeres Git-Repo ohne
> Commits) ist damit gegenstandslos. Bestandscode unverändert unter
> `devops/image/phpcli/` und `devops/image/phpfpm/`; die Vorläuferdokumente
> ebenfalls unverändert unter `devops/image/`.
> Der laufende Zustand steht in `docs/PROGRESS.md` — dort weiterlesen.

---

## Was zu tun ist

Zwei getrennte Docker-Image-Builder (`phpcli`, `phpfpm`) werden zu **einem** Repo konsolidiert, um Drift zu beseitigen, einen belegten UID/GID-Defekt zu beheben und FrankenPHP als drittes Ziel zu ergänzen.

## Die drei Dokumente — in dieser Reihenfolge lesen

| Datei | Inhalt | Status |
|---|---|---|
| `docs/docker-php-builder/PRD.md` | Anforderungen A1–A10, Entscheidungen E1–E10, Nicht-Ziele N1–N7, Akzeptanzkriterien AK1–AK15, **vollständiger Ist-Zustand** (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken L-A–L-G) | **Vom User bestätigt.** Keine offenen Punkte |
| `docs/docker-php-builder/PLAN.md` | Bauform-Übernahme, Zielstruktur, 12 Phasen P1–P12 mit Abhängigkeiten | Erstellt, vom User implizit freigegeben („leg mal los") |
| `docs/docker-php-builder/PROGRESS.md` | Laufender Zustand | Angelegt, P1 offen |

**Das PRD trägt den kompletten verifizierten Ist-Zustand mit Fundstellen.** Es muss nichts neu analysiert werden — alle Befunde sind belegt und mit Datei:Zeile referenziert. Der Bestandscode liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und `.../phpfpm/`.

## Aktueller Fortschritt

Nur ein Vorgriff auf P1 wurde ausgeführt:

- `docker-php-builder/` samt Unterverzeichnissen laut Zielstruktur angelegt
- `git init -b main` in diesem Verzeichnis ausgeführt
- **Keine einzige Datei geschrieben.** Da Git leere Verzeichnisse nicht trackt, ist der Repo-Stand faktisch leer

P1 beginnt also praktisch bei null; die Verzeichnisse sind lediglich schon da.

## Für P1 bereits recherchiert

Diese Dateien werden aus den Bestands-Repos übernommen — Inhalte sind geprüft:

| Datei | Quelle | Anpassung |
|---|---|---|
| `.gitignore` | `phpcli/.gitignore` | unverändert übernehmen |
| `.hadolint.yaml` | `phpfpm/.hadolint.yaml` | Kommentartext anpassen (gilt künftig für base/cli/fpm/frankenphp, nicht mehr für nginx); die Ignores DL3018 und DL4006 bleiben mit ihrer Begründung |
| `.github/CODEOWNERS` | `phpfpm/.github/CODEOWNERS` | Inhalt `* @headgent.dev` |
| `LICENSE` | `phpfpm/LICENSE` | MIT, Copyright 2024 Headgent GmbH |

Die konsolidierte `.env` entsteht aus `phpcli/src/.env` + `phpfpm/.env`. Beide sind im PRD Abschnitt 1.1 vollständig gegenübergestellt; die PECL-Versionen sind in beiden identisch, nur `REDIS_VERSION` vs. `REDIS_PECL_VERSION` weicht im Namen ab (D2). Achtung auf D16: `phpcli/src/Dockerfile:22` hat `ARG COMPOSER_VERSION=2.9.3` hartkodiert, während die `.env` 2.9.5 pflegt — dieses Muster ist künftig verboten (A2.4).

## Arbeitsweise in dieser Session

- **Sprache Deutsch** (globale Regel).
- **Keine Subagenten** — die Session-Konfiguration untersagte das Agent-Tool ohne ausdrückliche Anforderung. Falls im neuen Kontext erlaubt und gewünscht, kann der Workflow aus `project-workflow.md` §3 mit Umsetzungs-Subagent und unabhängigem Verifier je Phase gefahren werden; sonst arbeitet die Hauptsession die Phasen selbst ab.
- **Kein Experten-Gremium** — der User hat es für dieses Vorhaben ausdrücklich abgelehnt.
- Der User arbeitet auf **macOS**; der UID-Defekt ist dort prinzipiell unsichtbar und nur auf einem Linux-Runner nachweisbar (deshalb P8 = Test, P11 = Nachweis).

## Entscheidungen, die im Gespräch fielen und leicht übersehen werden

1. **Combined Image (php-fpm + nginx in einem Container) ist verworfen** — FrankenPHP ist mittelfristig das Ziel. Nicht wieder einführen (N1).
2. **Statisches FrankenPHP-Executable ist gestrichen** (N6) — samt der ganzen `static-php-cli`-Frage. Das Vorläuferdokument `anforderungen-docker-image-builder.md` fordert es noch; dieses ist überholt.
3. **Worker-Mode ist nicht im Lieferumfang** (N7), darf aber nicht strukturell verbaut werden (A5.2).
4. **nginx wird nicht mehr gebaut** (E9). Geliefert wird nur die Template-Config als Asset für das unveränderte offizielle Image. `headgent/nginx` hat keine Konsumenten, daher kein Deprecation-Pfad nötig.
5. **Image-Namen bleiben** `headgent/phpcli` und `headgent/phpfpm` (E2) — auf ausdrücklichen Wunsch, nicht aus Zwang.
6. **`pcntl` kommt nach `base`** und damit auch ins FPM-Image (E5), entgegen der bisherigen Praxis.
7. **Bauform der Bestands-Repos beibehalten und optimieren** — Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".

## Was das Vorläuferdokument falsch annimmt

`anforderungen-docker-image-builder.md` ist die Ausgangsbasis, aber an drei Stellen überholt — das PRD ist maßgeblich:

- Es nimmt an, die nginx-Config werde zur Build-Zeit erzeugt. Falsch: `envsubst` läuft bereits zur Laufzeit (`phpfpm/src/nginx/entrypoint.sh:11`).
- Es fordert das statische Executable (§3.2, §4) — gestrichen.
- Sein Zielbild (§2) widerspricht sich selbst bei nginx (Baum sagt „raus", §3.3 sagt „bleibt", §5 braucht es).
