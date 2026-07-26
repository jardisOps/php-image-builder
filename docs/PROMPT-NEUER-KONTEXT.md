# Prompt für einen neuen Kontext

Stand 2026-07-26, nach Abschluss von P10 und nach der Freigabe von O6. Der Text
unten ist zum Kopieren gedacht — er zeigt nur auf die Dokumente, statt Inhalte
zu wiederholen, damit es eine einzige Wahrheitsquelle gibt.

---

Arbeitsverzeichnis: `/Users/Rolf/Development/headgent/devops/docker/php-image-builder`

Lies zuerst, in dieser Reihenfolge:

1. `docs/PROGRESS.md` — trägt den laufenden Zustand: was P1–P6 und P8–P10
   geliefert und nachgewiesen haben, warum P7 entfallen ist, alle
   Umsetzungsentscheidungen mit Begründung, die Befunde B1–B29, die offenen
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

**Stand:** P1–P6 und P8–P10 sind abgeschlossen und committet, **P7
(`frankenphp`) ist gestrichen** (E11). `base`, `cli` und `fpm` bauen in einem
`bake`-Lauf gegen PHP 8.3, 8.4 und 8.5; amd64 ist belegt, der Nachweis auf einem
echten Linux-Runner bleibt P11. Die nginx-Vorlage liegt als Asset vor und ist
gegen das unveränderte offizielle Image nachgewiesen (39/39, AK7). Der
Demo-Stack läuft (`make demo-up`, 21/21, AK9 und AK12 erbracht). `make test-all`
läuft grün — zehn Stufen, 17 Commits, kein Remote, nie gepusht.

Bestätige die Ausgangslage einmal mit `make test-all`, bevor du etwas änderst.

---

## Schritt 1 — O6 (freigegeben am 2026-07-26, vor dem CI-Teil)

Zwei belegte Bestandsdefekte der nginx-Vorlage, beide in `PROGRESS.md` unter
„Befunde aus P9" mit Messung dokumentiert, beide sachlich Härtung (A7):

- **B24** — `try_files $uri =404;` in die `.php`-Fallback-Location
  (`compose/nginx/templates/default.conf.template`, `location ~ \.php$`). Die
  Location gibt heute jeden Pfad weiter, der auf `.php` endet, auch wenn die
  Datei nicht existiert; der klassische `/upload.jpg/x.php`-Pfad wird derzeit
  allein von `security.limit_extensions` des php-fpm abgefangen. Für legitime
  Requests ist die Zeile wirkungsgleich.
- **B25** — die Zeile `add_header Cache-Control "public";` in der
  Static-Asset-Location **löschen** (Variante (b) der drei in `PROGRESS.md`
  aufgeführten Wege, dort auch die empfohlene). Grund ist nginx-Semantik: eine
  Location, die ein eigenes `add_header` trägt, erbt **keinen** der fünf
  Server-Header — statische Dateien bekommen dadurch heute nicht einmal
  `nosniff`. Mit der gelöschten Zeile erbt sie wieder, und die doppelte
  `Cache-Control`-Angabe verschwindet.

**Beides ohne Nachweis ist nichts wert.** `support/tests/check-nginx-template.sh`
wächst entsprechend mit — und zwar mit Gegenprobe, sonst ist es ein Test der
Klasse „misst nichts":

- B24: eine echte `/app/public/upload.jpg` mit PHP-Code anlegen,
  `/upload.jpg/x.php` anfragen und **404 aus nginx** messen. Gegenprobe:
  `/index.php` bleibt 200. Der bisherige Messwert war 403 aus dem php-fpm — der
  Unterschied 403/404 ist genau der Beleg, dass jetzt die Vorlage abfängt und
  nicht mehr die fpm-Einstellung.
- B25: `X-Content-Type-Options`, `X-Frame-Options` und
  `Strict-Transport-Security` auf einer **statischen** Antwort (`/a.css`)
  messen, nicht nur auf `/index.php`. Gegenprobe: `Cache-Control` trägt danach
  nur noch `max-age=31536000` aus `expires 1y` und nicht mehr zusätzlich
  `public`.

Danach `make test-all` grün, dann committen und `PROGRESS.md` fortschreiben
(eigener kurzer Abschnitt „O6 — umgesetzt" mit Nachweis, oder als Nachtrag zu
P9 — deine Wahl, aber die Messung gehört hinein).

---

## Schritt 2 — P11 (CI-Pipeline + Härtung)

Hängt an P8. Die Phasennummern rücken trotz der Lücke bei P7 **nicht** nach —
Befunde und Akzeptanzkriterien verweisen namentlich auf sie.

Einzulösen:

- `.github/workflows/ci.yml`: **ein** Workflow ersetzt die beiden bestehenden
  (A9.1), eine Änderung an `base` baut alle abhängigen Targets neu (A9.2), die
  heutigen Trigger bleiben erhalten — push/PR/dispatch/scheduled inklusive
  Keepalive-Job (A9.3).
- Härtung H1–H5 plus H10 (AK8): Trivy für **alle** Targets, CRITICAL/HIGH
  blockieren und **kein** `continue-on-error` mehr (A7.1, hebt D14 auf),
  SBOM-Attestation (A7.2), `id-token: write` + `attestations: write` (A7.3,
  hebt D13 auf), OCI-Labels
  `org.opencontainers.image.{source,version,revision,created}` in allen
  Dockerfiles (A7.4). `.dockerignore` (A7.5), `apk upgrade` im Build-Stage
  (A7.7) und `.hadolint.yaml` (A7.8) liegen bereits vor — prüfen statt neu
  bauen.
- **Der UID-Nachweis AK4** wird hier geführt: auf einem echten Linux-Runner mit
  Host-UID ≠ 1000, belegter Ziel-GID und frischem Named Volume. P8 hat den Test
  geliefert (`make test-uid`), auf macOS ist der Fehler prinzipiell unsichtbar.

Zu beachten:

- **N6 ist die harte Grenze dieser Phase.** Der Workflow darf geschrieben, aber
  **nicht scharf geschaltet** werden: kein `docker login`, kein `--push`, keine
  CI-Auslösung, bis die Tag-Strategie vorliegt und freigegeben ist. Der
  Vorschlag steht in `PROGRESS.md` (N6): Nebentag `:<ver>-next`, `:latest` und
  `:<ver>` unangetastet, bis in einem Projekt gegengeprüft.
- **B20** — ein leeres Named Volume bekommt beim ersten Mount die Ownership des
  Image-Verzeichnisses zurück. Für AK4 auf dem Runner maßgeblich.
- **B23** — ein reiner Lint der nginx-Vorlage braucht einen auflösbaren
  Upstream-Namen, sonst scheitert `nginx -t` an DNS statt an der Vorlage.
- **B27** — `docker compose up --wait` meldet grün für einen Dienst **ohne**
  Healthcheck. Ein CI-Schritt, der einen Stack so hochfährt, belegt für sich
  genommen nicht, dass die Dienste gesund sind.
- **B15/B28** — Betriebsbedingungen: `build-all` übersetzt drei Versionen
  gleichzeitig (Plattenplatz), der Demo-Stack belegt einen Host-Port.

Danach P12 (Doku + Abschluss, Akzeptanz-Gate gegen AK1–AK15).

---

Halte `docs/PROGRESS.md` nach jeder abgeschlossenen Phase fort — in derselben
Form wie die Abschnitte zu P1–P6 und P8–P10 (Geliefert, Akzeptanz mit Nachweis,
Umsetzungsentscheidungen, Befunde).

Wichtig:

- Antworte auf Deutsch.
- Die Bauform der Bestands-Repos bleibt erhalten und wird nur optimiert:
  Makefile-Struktur mit `support/makefiles/`, `##@`-Hilfesystem, `.env` als
  Single Source of Truth. Details in `PLAN.md`, Abschnitt „Bauform".
- **`make test-all` muss grün bleiben.** Ein Aufruf, seit P8; der Umfang steht
  in `docs/HANDOVER.md`. Wer eine Extension, ein Profil oder einen Laufzeitwert
  ändert, zieht dort nach.
- **Sechs Testfallstricke derselben Klasse „der Test misst nichts und meldet
  trotzdem grün" haben in diesem Vorhaben bereits zugeschlagen** — B11, B16,
  B19, B20, B21 und B27 in `PROGRESS.md`. Wer einen neuen Test schreibt, prüft
  ihn gegen diese sechs, bevor er ihn für grün hält. Läuft ein neuer Prüffall im
  ersten Anlauf grün, ist eine Gegenprobe fällig.
- Nach jeder Codierung den Skill `do-qa-codereview` fahren, vor dem Commit.
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
