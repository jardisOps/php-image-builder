# Prompt für einen neuen Kontext

Stand 2026-07-25, nach Abschluss von P8. Der Text unten ist zum Kopieren gedacht —
er zeigt nur auf die Dokumente, statt Inhalte zu wiederholen, damit es eine
einzige Wahrheitsquelle gibt.

---

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den laufenden Zustand: was P1–P6 und P8 geliefert
   und nachgewiesen haben, warum P7 entfallen ist, alle Umsetzungsentscheidungen
   mit Begründung, die Befunde B1–B20, die offenen Punkte und die nächste Phase.
   Das ist die maßgebliche Datei; sie geht bei Widersprüchen vor.
2. `docs/HANDOVER.md` — Einstieg, Stand, Bedienung, Prüflauf, Arbeitsweise.
3. `docs/PRD.md` — Anforderungen A1–A10, Entscheidungen E1–E11, Nicht-Ziele
   N1–N8, Akzeptanzkriterien AK1–AK15 und der vollständige, verifizierte
   Ist-Zustand des Bestands (Drift D1–D16, UID-Defekte U1–U3, Xdebug/JIT-Lücken
   L-A–L-G) mit Datei- und Zeilenangaben.
4. `docs/PLAN.md` — Bauform, Zielstruktur, die Phasen mit Abhängigkeiten.

Analysiere den Bestandscode nicht neu — das PRD trägt ihn mit Fundstellen. Der
Bestand liegt unter `/Users/Rolf/Development/headgent/devops/image/phpcli/` und
`.../phpfpm/` und bleibt unverändert.

**Stand:** P1–P6 und P8 sind abgeschlossen und committet, **P7 (`frankenphp`) ist
gestrichen** (E11). `base`, `cli` und `fpm` bauen in einem `bake`-Lauf gegen PHP
8.3, 8.4 und 8.5; amd64 ist belegt, der Nachweis auf einem echten Linux-Runner
bleibt P11. `make test-all` läuft grün. Das Repo hat kein Remote und ist nie
gepusht worden.

**Beginne mit P9** (nginx-Config als Asset). Die Phase hängt nur an P1, es ist
nichts blockierend offen. Die Phasennummern rücken trotz der Lücke bei P7 **nicht**
nach — Befunde und Akzeptanzkriterien verweisen namentlich auf sie.

Einzulösen in P9:

- `compose/nginx/templates/default.conf.template`, vollständig parametrisiert.
- Der Ist-Zustand steht im PRD Abschnitt 1.3 **mit Fundstellen**: hartkodiert
  sind heute der Upstream-Host `app:`, `client_max_body_size 100m`, sämtliche
  fastcgi-Timeouts und die feste HTTPS-Annahme (`fastcgi_param HTTPS on`,
  `REQUEST_SCHEME https`). Die letzte muss schaltbar werden — ohne vorgelagerten
  TLS-Proxy ist sie schlicht falsch (A6.2).
- Es läuft mit dem **unveränderten** offiziellen nginx-Image über dessen
  eingebaute Substitution (`NGINX_ENVSUBST_TEMPLATE_DIR`), ohne eigenen
  Entrypoint und ohne eigenen Build (A6.3). Der eigene Entrypoint des Bestands
  dupliziert nur, was das offizielle Image seit 1.19 selbst kann (E9).
- Alle Variablen brauchen dokumentierte Defaults, damit das Ergebnis ohne
  Konfiguration lauffähig ist (A6.4).

Danach P10 (Demo-Stack, seit E11 nur noch eine Ausprägung), P11 (CI + Härtung),
P12 (Doku + Abschluss).

Halte `docs/PROGRESS.md` nach jeder abgeschlossenen Phase fort — in derselben
Form wie die Abschnitte zu P1–P6 und P8 (Geliefert, Akzeptanz mit Nachweis,
Umsetzungsentscheidungen, Befunde).

Wichtig:

- Antworte auf Deutsch.
- Die Bauform der Bestands-Repos bleibt erhalten und wird nur optimiert:
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als
  Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- **`make test-all` muss grün bleiben.** Ein Aufruf, seit P8; der Umfang steht
  in `docs/HANDOVER.md`. Wer eine Extension, ein Profil oder einen Laufzeitwert
  ändert, zieht dort nach.
- **Vier Testfallstricke derselben Klasse „der Test misst nichts und meldet
  trotzdem grün" haben in diesem Vorhaben bereits zugeschlagen** — B11, B16, B19
  und B20 in `PROGRESS.md`. Wer einen neuen Test schreibt, prüft ihn gegen diese
  vier, bevor er ihn für grün hält.
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
