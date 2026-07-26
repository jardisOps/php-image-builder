# Prompt für einen neuen Kontext

Stand 2026-07-26, Ende der sechsten Umsetzungs-Session: **O6 und P11
abgeschlossen** (Workflow geschrieben, OCI-Labels, **AK4 erbracht**).
Der Text unten ist zum Kopieren gedacht — er zeigt nur auf die Dokumente, statt
Inhalte zu wiederholen, damit es eine einzige Wahrheitsquelle gibt.

---

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den laufenden Zustand: was P1–P6, P8–P10, O6 und
   P11 geliefert und nachgewiesen haben, warum P7 entfallen ist, alle
   Umsetzungsentscheidungen mit Begründung, die Befunde **B1–B31**, die offenen
   Punkte und die nächste Phase. Das ist die maßgebliche Datei; sie geht bei
   Widersprüchen vor.
2. `docs/HANDOVER.md` — Einstieg, Stand, Bedienung, Prüflauf, Arbeitsweise.
3. `docs/PRD.md` — Anforderungen A1–A10, Entscheidungen E1–E11, Nicht-Ziele
   N1–N8, Akzeptanzkriterien AK1–AK15 und der vollständige, verifizierte
   Ist-Zustand des Bestands (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken
   L-A–L-G) mit Datei- und Zeilenangaben.
4. `docs/PLAN.md` — Bauform, Zielstruktur, die Phasen mit Abhängigkeiten.

Analysiere den Bestandscode nicht neu — das PRD trägt ihn mit Fundstellen. Der
Bestand liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und
`.../phpfpm/` und bleibt unverändert.

**Stand:** P1–P6, P8–P10, O6 und P11 sind abgeschlossen. `make test-all` war
zuletzt **grün, Exit 0** (PHP 8.3, dreizehn Stufen), der Code Review zu P11 ist
gelaufen, alles ist committet. **P7 ist gestrichen** (E11), **AK4 ist erbracht**.

**Es steht nur noch P12 an — Doku + Abschluss:** `README.md`, `.claude/CLAUDE.md`
und das Akzeptanz-Gate gegen AK1–AK15. Bestätige die Ausgangslage einmal mit
`make test-all`, bevor du etwas änderst.

Für die README ausdrücklich vorgemerkt:

- **B7** — die drei `InvalidDefaultArgInFrom`-Warnungen bei jedem Build sind die
  gewollte Folge von A2.4 und nicht behebbar; sie soll niemand als Fehler lesen.
- **B15** (`build-all` braucht Plattenplatz), **B28** (Host-Port des Demo-Stacks).
- **`make test-all` setzt seit `test-uid-linux` `--privileged` voraus** (der
  AK4-Nachweis fährt einen `docker:28-dind`-Linux-Host hoch).
- Der Verlust von `php-cgi` und `phpdbg` im cli-Image (Folge der
  N1-Entscheidung, P3) gehört in die Release-Notiz.
- Rückbau von `curl-dev`/`oniguruma-dev` prüfen — seit B12 vermutlich
  überflüssig, braucht je einen Build-Test.

Beim Akzeptanz-Gate zu beachten: **AK8 ist nur teilweise belegbar.** H2–H5 und
H10 sind am Artefakt nachgewiesen, aber der Trivy-Lauf selbst (H1) braucht einen
CI-Lauf — und der ist durch N6 gesperrt.

**N6 ist die harte Grenze und weiterhin offen.** Der Workflow ist geschrieben,
aber nicht scharf: `publish` läuft nur bei `vars.PUBLISH_ENABLED == 'true'`, und
diese Repository-Variable existiert nicht. Kein GitHub-Repo, kein Remote, kein
`docker login`, kein `--push`, keine CI-Auslösung — bis eine Tag-Strategie
vorliegt und freigegeben ist (Vorschlag steht in PROGRESS: Nebentag
`:<ver>-next`, `:latest` und `:<ver>` unangetastet, bis in einem Projekt
gegengeprüft).

**Beachten:** die sieben Testfallstricke der Klasse „der Test misst nichts und
meldet trotzdem grün" — B11, B16, B19, B20, B21, B27 und **B31** (die neueste:
eine Sonde maß den Verzeichniseigentümer, also die *Eingabe* des Prüffalls,
statt die Prozesskennung; aufgefallen nur durch die Gegenprobe gegen das
defekte Bestands-Image). **Grün im ersten Anlauf heißt Gegenprobe fällig.**

**Sonst:** Deutsch, `make test-all` bleibt grün, `do-qa-codereview` nach jeder
Codierung, nichts nach außen ohne Freigabe, kein Gremium und keine Subagenten,
bei Abweichung von PRD/Plan nachfragen.
