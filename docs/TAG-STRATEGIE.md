# Tag-Strategie für den ersten Push (N6)

- **Status:** Vorlage zur Freigabe, 2026-07-26. **Nichts davon ist umgesetzt.**
- **Zweck:** N6 ist der einzige Punkt dieses Vorhabens mit Außenwirkung. Diese
  Vorlage beantwortet die Frage, unter welchen Tags der erste Push erfolgen
  darf, ohne laufende Projekte zu treffen — und wie aus dem Nebentag später der
  reguläre wird.
- **Bezug:** `docs/PRD.md` N6/E2/A1.3, `docs/PROGRESS.md` (offener Punkt N6),
  `development.md` §6 (Release-Lifecycle: nur vorwärts, publizierter Code wird
  nie überschrieben).

---

## 1 · Ausgangslage — belegt, nicht vermutet

### 1.1 Wer hängt tatsächlich an den Images

Vollständige Suche über `/Users/Rolf/Development/` und `~/Sites` nach
`image:`-Zeilen, `FROM`-Zeilen, `.env`-Variablen und CI-Schritten:

| Referenz | Aktive Fundstellen |
|---|---|
| **`headgent/phpcli:8.3`** | **26** — 23 Jardis-Packages plus `core/kernel`, `support/contracts` und ein Worktree-Klon |
| `headgent/phpcli:8.4` | **0** laufende Projekte (nur fünf Codebeispiele in `jardisDoc`) |
| `headgent/phpcli:latest` | **0** |
| `headgent/phpfpm:*` | **0** |
| `headgent/nginx:*` | **0** |
| `headgent/phpcli:8.2` | **0** |
| Digest-Pins (`@sha256:…`) | **0** |

Alle 26 Fundstellen tragen dieselbe Compose-Zeile — meist
`${DOCKER_HUB:-headgent}/phpcli:${PHP_VERSION:-8.3}`, zweimal ohne
`DOCKER_HUB`-Variable — und jedes zugehörige `.env` setzt `PHP_VERSION=8.3`.
Es handelt sich durchweg um laufende Dienste, nicht um Build-Stages; die
CI-Jobs der Packages rufen `make phpunit`/`phpstan`/`phpcs` auf und benutzen
damit dieselbe Compose-Datei.

**Der reale Fußabdruck dieses Vorhabens ist also ein einziger Tag.** Das ist die
gute und die schlechte Nachricht zugleich: die Angriffsfläche ist schmal, aber
sie ist zu 100 % besetzt.

### 1.2 Was ein Push heute erzeugen würde

`make push-all` setzt nach heutigem Schema (verifiziert mit `make bake-print`,
Werte vom 2026-07-26) **vierzehn** Tags:

```
headgent/phpcli:8.3      headgent/phpcli:8.3-20260726
headgent/phpcli:8.4      headgent/phpcli:8.4-20260726
headgent/phpcli:8.5      headgent/phpcli:8.5-20260726      headgent/phpcli:latest
headgent/phpfpm:8.3      headgent/phpfpm:8.3-20260726
headgent/phpfpm:8.4      headgent/phpfpm:8.4-20260726
headgent/phpfpm:8.5      headgent/phpfpm:8.5-20260726      headgent/phpfpm:latest
```

Darunter ist `headgent/phpcli:8.3` — der Tag, an dem 26 Projekte hängen. Sie
bekämen das neue Image beim nächsten `docker compose pull` oder
`build --pull`, ohne dass irgendwo eine Zeile geändert worden wäre.

`:latest` würde außerdem von 8.4 (heutiger Stand der Registry) auf **8.5**
springen — eine PHP-Version, die es im Bestand nie gab.

### 1.3 Was die Konsumenten merken würden

Aus der Umstiegs-Tabelle der README, gefiltert auf das, was `phpcli:8.3`
betrifft:

| Änderung | Wirkung auf die 26 Projekte |
|---|---|
| **`php-cgi` und `phpdbg` fehlen** | ohne Folge — die Packages fahren PHPUnit, PHPStan, PHP_CodeSniffer und Composer |
| **Unix-Gruppe heißt `appuser` statt `appgroup`** | betrifft alles, was die Gruppe **namentlich** anspricht (`chown`, `usermod`, Rechte-Setup in Projekt-Skripten). Die numerische GID bleibt |
| **`APP_ENV` steuert die Umgebung** | das Image bringt `APP_ENV=dev` mit. Für `phpcli` ändert das den Xdebug-Default **nicht** (der war im Bestand schon `debug`), wohl aber `display_errors=On` und `opcache.validate_timestamps=1` |
| **JIT-Warnung verschwindet** | reine Verbesserung: bei aktivem Xdebug wird JIT jetzt sauber abgeschaltet, statt dass PHP bei jedem Aufruf warnt |
| **PHP-Patchstand steigt** | `apk upgrade` in beiden Stages, neu übersetzte Extensions |

Nichts davon ist ein bekannter Bruch für diese Konsumenten — **aber „nicht
bekannt" ist kein Nachweis.** Genau deshalb diese Strategie.

### 1.4 Was die Regel verlangt

`development.md` §6, sinngemäß auf Container-Tags übertragen: ein
veröffentlichtes Artefakt wird nicht überschrieben, und die Reihe läuft nur
vorwärts. Ein wandernder Tag wie `:8.3` ist per Definition kein unveränderliches
Artefakt — der **Digest** darunter ist es. Die Strategie muss deshalb
sicherstellen, dass jeder je publizierte Stand unter einem unveränderlichen
Namen erreichbar bleibt, auch nachdem `:8.3` weitergezogen ist.

---

## 2 · Vorschlag: zwei Kanäle, eine Beförderung

### 2.1 Das Modell

| Kanal | Tags | Wer liest ihn |
|---|---|---|
| **`next`** | `:<ver>-next` und `:<ver>-<datum>` | niemand, bis jemand es ausdrücklich einträgt |
| **`stable`** | `:<ver>` und `:latest` | die 26 Projekte |

Der erste Push schreibt **ausschließlich in `next`**. Kein bestehender Tag wird
angefasst — weder `:8.3` noch `:latest` noch irgendein `8.2`-Tag. Der Push ist
damit rein additiv und für jeden Konsumenten unsichtbar.

Zwei Eigenschaften machen diesen Zuschnitt praktisch:

1. **Der Nebentag ist ohne Codeänderung testbar.** Die Compose-Zeile der
   Packages bildet den Tag aus `${PHP_VERSION}`. Ein Projekt probiert das neue
   Image also mit genau einer Zeile in seiner `.env`:

   ```sh
   PHP_VERSION=8.3-next        # statt 8.3
   ```

   Keine Compose-Datei muss angefasst werden, und der Rückweg ist dieselbe
   Zeile rückwärts.

2. **Der datierte Tag ist der Anker der Beförderung.** `:<ver>-<datum>` ist
   unveränderlich und wird in beiden Kanälen gesetzt. Befördert wird später
   nicht „ein neuer Build", sondern **genau der Digest, der geprüft wurde**.

### 2.2 Beförderung ohne Rebuild

Aus `next` wird `stable` durch ein Registry-Retag, nicht durch einen zweiten
Build:

```sh
docker buildx imagetools create \
  --tag headgent/phpcli:8.3 \
  headgent/phpcli:8.3-20260726
```

Das ist kein neues Verfahren, sondern das, was das Bestands-Repo `phpcli` für
`:latest` ohnehin schon tat (`support/makefile/docker.mk:90-95`). Es überträgt
den Multi-Arch-Index unverändert — der befördete Stand ist **byte-gleich** mit
dem geprüften, es gibt keinen Zwischenraum, in dem sich etwas ändern könnte.

### 2.3 Rettungstag für den Bestand — vor der ersten Beförderung

Bevor `:8.3` weiterzieht, bekommt der **heutige** Stand einen unveränderlichen
Namen, damit ein Rückweg existiert:

```sh
docker buildx imagetools create \
  --tag headgent/phpcli:8.3-legacy \
  headgent/phpcli:8.3
```

Additiv, überschreibt nichts, kostet einen Retag. Danach ist ein Rollback ein
einzelner Befehl statt einer Archäologie über Digests. **Ohne diesen Schritt
keine Beförderung** — ein Rollback, der erst im Schadensfall erfunden wird, ist
keiner.

---

## 3 · Die Stufen, nach Schadensradius geordnet

| Stufe | Was geschieht | Betroffene Konsumenten | Umkehrbar durch |
|---|---|---|---|
| **0** | Voraussetzungen: GitHub-Repo, Remote, Secrets, `PUBLISH_ENABLED` | — | Repo privat lassen |
| **1** | Push in `next` für 8.3/8.4/8.5, beide Images | **0** | nichts nötig — additive Tags |
| **2** | Ein echtes Projekt fährt `PHP_VERSION=8.3-next`, voller `make phpunit`/`phpstan`/`phpcs` | 1, freiwillig | eine Zeile in dessen `.env` |
| **3** | Rettungstags `:<ver>-legacy` für alle Bestandstags, die befördert werden sollen | **0** | — |
| **4** | Beförderung **`phpfpm`** → `:8.3`/`:8.4`/`:8.5` | **0** (keine Konsumenten, und der Bestand ist ohnehin startunfähig — B9) | Retag zurück |
| **5** | Beförderung **`phpcli:8.4`** | **0** aktive (nur Doku-Beispiele) | Retag auf `:8.4-legacy` |
| **6** | Beförderung **`phpcli:8.3`** | **26** — der eigentliche Schritt | Retag auf `:8.3-legacy` |
| **7** | `phpcli:8.5` und `phpfpm:8.5` in `stable`, danach `:latest` von 8.4 auf 8.5 | 0 direkt | Retag zurück auf 8.4 |

Stufe 4 ist bemerkenswert: **`headgent/phpfpm` ist in allen drei publizierten
Versionen startunfähig** (Befund B9 — der `chown` auf `/proc/self/fd/{1,2}`
wirkt nicht, FPM scheitert danach am `error_log`). Dort ist jeder Push eine
Verbesserung gegenüber einem Artefakt, das niemand benutzen kann. Es wäre
vertretbar, `phpfpm` die `next`-Stufe überspringen zu lassen; der Vorschlag tut
es trotzdem nicht, weil **ein** Verfahren für beide Images billiger ist als zwei
und der Umweg genau einen Retag kostet.

Zwischen Stufe 2 und Stufe 6 gehört Zeit. Wie viel, ist eine Entscheidung —
siehe §6.

---

## 4 · Was `:latest` und PHP 8.2 angeht

**`:latest`** hat null Konsumenten und zeigt heute auf 8.4. Der neue Builder
würde es an 8.5 hängen (`PHP_LATEST` = letztes Element von `PHP_VERSIONS`).
Vorschlag: `:latest` wandert **zuletzt** (Stufe 7), nicht beim ersten Push.
Damit ist ausgeschlossen, dass ein neugieriger `docker pull headgent/phpcli`
mitten in der Umstellung eine PHP-Version bekommt, die noch nie in einem Projekt
gelaufen ist.

**PHP 8.2** ist aus der Matrix gestrichen (2026-07-25) und hat null Konsumenten.
Vorschlag: `headgent/phpcli:8.2` und `headgent/phpfpm:8.2` bleiben unberührt in
der Registry liegen — nicht gelöscht, nicht gepflegt, nicht neu gebaut. Dieselbe
Behandlung wie `headgent/nginx` (A6.5). Ein Deprecation-Pfad ist ohne
Konsumenten gegenstandslos.

---

## 5 · Was dafür gebaut werden müsste

Heute kennt der Builder nur einen Kanal. Der Umbau betrifft fünf Dateien:

| Datei | Eingriff |
|---|---|
| `docker-bake.hcl:105-114` | `image_tags()` bekommt einen zweiten Zweig: im `next`-Kanal `:<ver>-next` + `:<ver>-<datum>`, im `stable`-Kanal wie heute. Das ist die **einzige** Stelle, die Tags bildet — für beide Images, für `push` wie `push-all` |
| `support/makefiles/docker.helper.mk` | neue Variable `PUBLISH_CHANNEL ?= next` — der sichere Wert ist der Default |
| `support/makefiles/docker.build.push.mk:17-33` | Durchreichen der Variablen an `bake` |
| `support/tests/check-bake-graph.sh:78-106` | **der eigentliche Aufwand.** Der Test verdrahtet das heutige Schema als Vertrag: genau zwei Nicht-`latest`-Tags je Ziel, genau zwei `:latest`-Tags insgesamt, ein einheitliches Datum. Er läuft blockierend im `lint`-Job **vor** `publish`. Jede Änderung an der Tag-Form muss ihn mitziehen, sonst kommt der Lauf gar nicht bis zum Push. Der Test braucht einen zweiten Prüfpfad, der **beide** Kanäle abdeckt |
| `.github/workflows/ci.yml` | `PUBLISH_CHANNEL` in den `publish`-Job; die `PUBLISH_ENABLED`-Sperre bleibt, bis Stufe 0 freigegeben ist |

Dazu ein Beförderungs-Target, damit der Retag nicht von Hand getippt wird —
etwa `make promote PHP_VERSION=8.3 IMAGE=phpcli IMAGE_DATE=20260726`, mit
Anzeige des Digests vorher und nachher.

**Der Test ist hier nicht Beiwerk, sondern der Kern.** Dass
`check-bake-graph.sh` die Tag-Form heute erzwingt, ist der Grund, warum eine
stille Abweichung nicht möglich ist — genau die Eigenschaft, die man bei einem
Kanalmodell braucht. Er wird erweitert, nicht aufgeweicht.

---

## 6 · Zu entscheiden

| # | Frage | Vorschlag |
|---|---|---|
| **T1** | Kanalmodell `next`/`stable` mit Beförderung per Retag — so? | ja, wie oben |
| **T2** | Nebentag-Form: `:<ver>-next` | ja. `-next` liest sich als Kanal, nicht als Version, und funktioniert über `PHP_VERSION=8.3-next` ohne Änderung an einer Compose-Datei |
| **T3** | Welches Projekt fährt die Feldprobe in Stufe 2? | eines der kleineren Packages mit vollem QA-Lauf, z.B. `jardis/support/dotenv` — dann ein zweites mit Datenbank-Anbindung, z.B. `jardis/support/repository` |
| **T4** | Wie lange läuft die Feldprobe, bevor Stufe 6 kommt? | mindestens ein vollständiger `make phpunit`/`phpstan`/`phpcs`-Durchlauf in zwei Projekten, plus eine Woche Alltag. Zeit ist hier der billigste Prüfmechanismus |
| **T5** | Darf `phpfpm` die `next`-Stufe überspringen (null Konsumenten, Bestand startunfähig)? | nein — ein Verfahren für beide, der Umweg kostet einen Retag |
| **T6** | Rettungstags `:<ver>-legacy` vor der ersten Beförderung | ja, verpflichtend. Ohne Rückweg keine Beförderung |
| **T7** | `:latest` zuletzt und dann auf 8.5 | ja |
| **T8** | 8.2-Tags unberührt liegen lassen | ja |
| **T9** | Stufe 0 — GitHub-Repo anlegen, Remote setzen, Secrets und `PUBLISH_ENABLED` einrichten | **braucht eine eigene Freigabe.** Das ist der Moment, in dem N6 fällt |

---

## 7 · Was der erste CI-Lauf nebenbei erledigt

Mit Stufe 0/1 läuft der Workflow zum ersten Mal überhaupt. Damit wird
eingelöst, was das Akzeptanz-Gate offenlassen musste (O7, PRD bei AK8): die
GitHub-Actions-Verdrahtung des Trivy-Gates — Job-Reihenfolge, die Parameter der
`trivy-action`, der Summary-Schritt. Der Scan selbst ist lokal belegt
(0 CRITICAL/HIGH auf beiden Images, mit und ohne `ignore-unfixed`); ungeprüft
ist bisher nur, ob die Verdrahtung darum herum trägt.

**Reihenfolge daher:** erst Stufe 0 und 1 mit `PUBLISH_CHANNEL=next`. Sollte das
Trivy-Gate wider Erwarten rot werden, betrifft es einen Kanal, den niemand
liest.
