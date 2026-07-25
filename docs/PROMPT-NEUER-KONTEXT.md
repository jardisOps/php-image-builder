# Prompt für einen neuen Kontext

Stand 2026-07-25, nach Abschluss von P6 und der Streichung von P7. Der Text unten
ist zum Kopieren gedacht — er zeigt nur auf die Dokumente, statt Inhalte zu
wiederholen, damit es eine einzige Wahrheitsquelle gibt.

---

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den laufenden Zustand: was P1–P6 geliefert und
   nachgewiesen haben, warum P7 entfallen ist, alle Umsetzungsentscheidungen mit
   Begründung, die Befunde B1–B16, die offenen Punkte und die nächste Phase. Das
   ist die maßgebliche Datei; sie geht bei Widersprüchen vor.
2. `docs/HANDOVER.md` — Einstieg, Stand, Bedienung, die vier Prüfungen,
   Arbeitsweise.
3. `docs/PRD.md` — Anforderungen A1–A10, Entscheidungen E1–E11, Nicht-Ziele
   N1–N8, Akzeptanzkriterien AK1–AK15 und der vollständige, verifizierte
   Ist-Zustand des Bestands (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken
   L-A–L-G) mit Datei- und Zeilenangaben.
4. `docs/PLAN.md` — Bauform, Zielstruktur, die Phasen mit Abhängigkeiten.

Analysiere den Bestandscode nicht neu — das PRD trägt ihn mit Fundstellen. Der
Bestand liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und
`.../phpfpm/` und bleibt unverändert.

**Stand:** P1–P6 sind abgeschlossen und committet, **P7 (`frankenphp`) ist
gestrichen** (E11). `base`, `cli` und `fpm` bauen in **einem** `bake`-Lauf gegen
PHP 8.3, 8.4 und 8.5; amd64 ist seit P6 belegt, der Nachweis auf einem echten
Linux-Runner bleibt P11. Das Repo hat kein Remote und ist nie gepusht worden.

**Beginne mit P8** (Tests, `support/makefiles/test.mk`). Die Phase hängt seit E11
an P6. Es ist nichts blockierend offen. Die Phasennummern P8–P12 rücken trotz der
Lücke bei P7 **nicht** nach — Befunde und Akzeptanzkriterien verweisen namentlich
auf sie.

Einzulösen:

- Die vier Prüfungen, die bisher von Hand laufen, gehören in `test.mk`. Die
  vollständigen Aufrufe stehen in `docs/HANDOVER.md`.
- **Zwei Testfallstricke sind verbindlich**, beide derselben Fehlerklasse „der
  Test misst nichts und meldet trotzdem grün": **B11**
  (`opcache.file_update_protection`, 2 s abwarten und
  `num_cached_scripts`/`hits` mitprüfen — daran ist ein Nachweis in P5 schon
  einmal gescheitert) und **B16** (unter Emulation trägt ein FPM-Worker keinen
  `pool www`-Titel; über Benutzer und `/ping` prüfen).
- **B15:** `bake` baut die Matrix parallel und braucht dabei spürbar
  Plattenplatz. Tests, die vorher bauen, sollten `make build` je Version nutzen.
- **AK4 ist auf macOS nicht vollständig führbar.** P8 liefert den Test, P11 den
  Nachweis auf dem Linux-Runner.

Danach P9 (nginx-Config als Asset), P10 (Demo-Stack, seit E11 nur noch eine
Ausprägung), P11 (CI + Härtung), P12 (Doku + Abschluss).

Halte `docs/PROGRESS.md` nach jeder abgeschlossenen Phase fort — in derselben
Form wie die Abschnitte zu P1–P6 (Geliefert, Akzeptanz mit Nachweis,
Umsetzungsentscheidungen, Befunde).

Wichtig:

- Antworte auf Deutsch.
- Die Bauform der Bestands-Repos bleibt erhalten und wird nur optimiert:
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als
  Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- **Die vier Prüfungen müssen grün bleiben** (hadolint über drei Dockerfiles,
  shellcheck über vier Shell-Dateien, 33 APP_ENV-Fälle, 27 UID-Fälle).
- Keine nach außen wirkenden Aktionen ohne ausdrückliche Freigabe: kein
  GitHub-Repo anlegen, kein Remote setzen, nichts archivieren, **nicht pushen**.
  Commits sind freigegeben; frag im Zweifel.
- Frag nach, bevor du von PRD oder Plan abweichst. Halte dich beim Umfang an das
  Bestellte: in P2 hatte ich zweimal überkonstruiert (eine Notwert-Ebene und eine
  Lookup-Tabelle, wo `${VAR:=wert}` genügt) — beides ist auf meine Anweisung
  zurückgebaut. Wenn etwas einfacher geht als geplant, sag es, statt es aufwendig
  zu bauen. Wenn etwas gar keinen Nutzen mehr trägt, sag auch das — genau daran
  ist P7 gestrichen worden.
- Kein Experten-Gremium, keine Subagenten, sofern ich sie nicht anfordere.

Zwei Dinge warten unverändert:

- **Kein GitHub-Repo, kein Remote, keine Archivierung** der beiden
  Bestands-Repos. Der erste Push auf `headgent/phpcli` bzw. `headgent/phpfpm` ist
  der einzige Punkt mit Außenwirkung — leg mir vorher eine Tag-Strategie vor
  (N6 in PROGRESS.md).
- `devops/image/docker-php-builder/` (der alte Vorgriff) steht noch da: leere
  Verzeichnisse plus ein Git-Repo ohne Commits. Gegenstandslos, kann weg — ich
  habe es nicht angefasst.
