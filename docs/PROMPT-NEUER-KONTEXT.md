# Prompt für einen neuen Kontext

Stand 2026-07-25, nach Abschluss von P5. Der Text unten ist zum Kopieren gedacht —
er zeigt nur auf die Dokumente, statt Inhalte zu wiederholen, damit es eine einzige
Wahrheitsquelle gibt.

---

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den laufenden Zustand: was P1–P5 geliefert und
   nachgewiesen haben, alle Umsetzungsentscheidungen mit Begründung, die Befunde
   B1–B13, die offenen Punkte und die nächste Phase. Das ist die maßgebliche
   Datei; sie geht bei Widersprüchen vor.
2. `docs/HANDOVER.md` — Einstieg, Stand, die vier Prüfungen, Arbeitsweise.
3. `docs/PRD.md` — Anforderungen A1–A10, Entscheidungen E1–E10, Nicht-Ziele
   N1–N7, Akzeptanzkriterien AK1–AK15 und der vollständige, verifizierte
   Ist-Zustand des Bestands (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken
   L-A–L-G) mit Datei- und Zeilenangaben.
4. `docs/PLAN.md` — Bauform, Zielstruktur, die 12 Phasen P1–P12 mit
   Abhängigkeiten.

Analysiere den Bestandscode nicht neu — das PRD trägt ihn mit Fundstellen. Der
Bestand liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und
`.../phpfpm/` und bleibt unverändert.

**Stand:** P1–P5 sind abgeschlossen und in zwei Commits versioniert (`1aa8d30`,
`7ad5cc7`), 24 Dateien. `base`, `cli` und `fpm` bauen und laufen gegen PHP 8.3,
8.4 und 8.5 — geprüft nativ auf arm64, amd64 steht noch aus. Das Repo hat kein
Remote und ist nie gepusht worden.

**Beginne mit P6** (`docker-bake.hcl` + Make-Targets). Es ist nichts blockierend
offen. Einzulösen, aus P3–P5 mitgegeben:

- `contexts = { base = "target:base" }` für `cli` und `fpm` (A1.2). Das
  Ad-hoc-Skript der Vorsession hat das über `--build-context` nachgebildet und
  funktioniert; `bake` löst es nativ auf.
- `base` gehört **nicht** in die Default-Gruppe — es wird nicht publiziert.
- Die ARG-Namen je Target stehen fest: `base` 21, `cli` 1
  (`PHP_MAX_EXECUTION_TIME_CLI`), `fpm` 7 (`PHP_MAX_EXECUTION_TIME_WEB` plus
  sechs `FPM_PM_*`). Alle Werte kommen aus der `.env`, keiner doppelt (A2.1).
- Ein Versionsstring treibt alle Tags gleichzeitig (A1.3, `IMAGE_DATE` in
  `docker.helper.mk`).
- **Kein `--push`-Lauf.** Die Push-Targets werden geschrieben, nicht ausgeführt.
- Erst hier wird die Matrix über **amd64** gebaut; P3–P5 sind nur auf arm64
  nachgewiesen.

Danach die Phasen der Reihe nach. In P7 (`frankenphp`) sind **N3** (OS-Variante
Alpine gegen Debian) und **O1** (Image-Name) zu entscheiden — leg sie mir vor,
bevor du baust. `dunglas/frankenphp:1.12.6-php{8.3,8.4,8.5}-alpine` ist
verfügbar, geprüft am 2026-07-25.

Halte `docs/PROGRESS.md` nach jeder abgeschlossenen Phase fort — in derselben
Form wie die Abschnitte zu P1–P5 (Geliefert, Akzeptanz mit Nachweis,
Umsetzungsentscheidungen, Befunde).

Wichtig:

- Antworte auf Deutsch.
- Die Bauform der Bestands-Repos bleibt erhalten und wird nur optimiert:
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als
  Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- **Die vier Prüfungen müssen grün bleiben** (hadolint über drei Dockerfiles,
  shellcheck über vier Shell-Dateien, 33 APP_ENV-Fälle, 27 UID-Fälle). Die
  vollständigen Aufrufe stehen in `docs/HANDOVER.md`.
- **Für jeden OPcache-Test verbindlich:** `opcache.file_update_protection`
  (2 Sekunden) abwarten und `num_cached_scripts`/`hits` mitprüfen, sonst misst
  der Test nichts. Siehe Befund B11 — genau daran ist ein Nachweis in P5 schon
  einmal gescheitert.
- Keine nach außen wirkenden Aktionen ohne ausdrückliche Freigabe: kein
  GitHub-Repo anlegen, kein Remote setzen, nichts archivieren, **nicht pushen**.
  Commits sind freigegeben; frag im Zweifel.
- Frag nach, bevor du von PRD oder Plan abweichst. Halte dich beim Umfang an das
  Bestellte: in P2 hatte ich zweimal überkonstruiert (eine Notwert-Ebene und eine
  Lookup-Tabelle, wo `${VAR:=wert}` genügt) — beides ist auf meine Anweisung
  zurückgebaut. Wenn etwas einfacher geht als geplant, sag es, statt es aufwendig
  zu bauen.
- Kein Experten-Gremium, keine Subagenten, sofern ich sie nicht anfordere.

Zwei Dinge warten unverändert:

- **Kein GitHub-Repo, kein Remote, keine Archivierung** der beiden
  Bestands-Repos. Der erste Push auf `headgent/phpcli` bzw. `headgent/phpfpm` ist
  der einzige Punkt mit Außenwirkung — leg mir vorher eine Tag-Strategie vor
  (N6 in PROGRESS.md).
- `devops/image/docker-php-builder/` (der alte Vorgriff) steht noch da: leere
  Verzeichnisse plus ein Git-Repo ohne Commits. Gegenstandslos, kann weg — ich
  habe es nicht angefasst.
