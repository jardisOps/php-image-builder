# Prompt für einen neuen Kontext

Stand 2026-07-25, nach Abschluss von P2. Der Text unten ist zum Kopieren gedacht —
er zeigt nur auf die Dokumente, statt Inhalte zu wiederholen, damit es eine einzige
Wahrheitsquelle gibt.

---

Wir konsolidieren zwei PHP-Docker-Image-Builder zu einem Repo. Analyse, PRD und Plan
sind abgeschlossen und bestätigt; die Umsetzung läuft. Die Phasen P1 und P2 sind
fertig und nachgewiesen.

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den **laufenden Zustand**: was P1/P2 geliefert und
   nachgewiesen haben, alle getroffenen Umsetzungsentscheidungen mit Begründung, die
   Befunde B1–B3, die offenen Punkte N1–N4 und die nächste Phase. **Das ist die
   maßgebliche Datei; sie geht bei Widersprüchen vor.**
2. `docs/PRD.md` — Anforderungen A1–A10, Entscheidungen E1–E10, Nicht-Ziele N1–N7,
   Akzeptanzkriterien AK1–AK15 und der **vollständige, verifizierte Ist-Zustand** des
   Bestands (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken L-A–L-G) mit
   Datei- und Zeilenangaben.
3. `docs/PLAN.md` — Bauform, Zielstruktur, die 12 Phasen P1–P12 mit Abhängigkeiten.
4. `docs/HANDOVER.md` — nur zur Vorgeschichte; der Nachtrag oben darin gilt vor allen
   Pfadangaben im Rumpf.

Analysiere den Bestandscode **nicht neu** — das PRD trägt ihn mit Fundstellen.
Der Bestand liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und
`.../phpfpm/` und bleibt unverändert.

**Beginne mit P3 (`base`-Target).** Kläre dabei zuerst **N1** — die Wahl des
offiziellen Basis-Images ist im PRD nicht entschieden und blockiert P3/P4/P5.
PROGRESS.md enthält dazu einen eigenen Abschnitt mit beiden Varianten, den
verifizierten Fakten und einer Empfehlung; leg mir die Entscheidung vor, bevor du
Dockerfiles schreibst. In P3 ebenfalls einzulösen: D16/A2.4 und N2.

Danach die Phasen der Reihe nach. Halte `docs/PROGRESS.md` nach jeder abgeschlossenen
Phase fort — in derselben Form wie die Abschnitte zu P1 und P2 (Geliefert, Akzeptanz
mit Nachweis, Umsetzungsentscheidungen, Befunde).

Wichtig:

- **Antworte auf Deutsch.**
- Die **Bauform** der Bestands-Repos bleibt erhalten und wird nur optimiert:
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als Single
  Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- Die drei Prüfungen aus P2 (shellcheck, 33 APP_ENV-Fälle, 27 UID-Fälle) müssen grün
  bleiben. Die Aufrufe stehen in `PROGRESS.md` unter „P2 → Akzeptanz".
- **Keine nach außen wirkenden Aktionen ohne ausdrückliche Freigabe:** kein GitHub-Repo
  anlegen, kein Remote setzen, nichts archivieren, nicht pushen. Auch **kein Commit** —
  das Repo hat bis jetzt bewusst keinen. Frag, wenn du meinst, dass ein Commit fällig
  ist.
- **Frag nach, bevor du von PRD oder Plan abweichst.** Halte dich beim Umfang an das
  Bestellte: in P2 hatte ich zweimal überkonstruiert (eine Notwert-Ebene und eine
  Lookup-Tabelle, wo `${VAR:=wert}` genügt) — beides ist auf meine Anweisung
  zurückgebaut, siehe PROGRESS.md „P2 → Umsetzungsentscheidungen" 2 und 3. Wenn
  etwas einfacher geht als geplant, sag es, statt es aufwendig zu bauen.
- Kein Experten-Gremium, keine Subagenten, sofern ich sie nicht anfordere.
