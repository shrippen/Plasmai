# TODO: Plugins Drehzettel und Anfahrten in Plasmai 2.0

Stand 2026-09-25. Plan für die Anbindung der Kimai-Plugins Drehzettel und Anfahrten (MileageBundle) in Plasmai 2.0.

Neue Basis: `feature/android-plasmamobile` (2.0.0, `61268ca`). Gelesen: DESIGN.md, ROADMAP.md, CHANGELOG.md, README.md, todo.md, app/BUILD.md, FilmDayView/FilmDayPage/filmDays.js, beide `main.qml`. Die Plugin-APIs stammen aus `kimai-drehzettel-bundle@claude/kimai-plugins-code-review-yakjp9` (`Controller/Api/DrehzettelApiController.php`, `Domain/FilmDayPatch.php`) und `kimai-anfahrten@claude/plugin-ui-kit` (`API/MileageApiController.php`).

## 1. Was sich gegenüber der alten Analyse geändert hat

- **2.0-Struktur:** Es gibt zwei UIs mit gemeinsamer Logik.
  - Plasmoid: `contents/ui/*` mit `mainViewMode` main/manual/stats/**filmday**, die Orchestrierung liegt in `contents/ui/main.qml`.
  - Kirigami-App: `app/qml/*` mit eigenen Seiten (`TimerPage`, `ManualEntryPage`, `StatsPage`, **`FilmDayPage`**, `SettingsPage` …), Drawer in `app/qml/main.qml`.
  - `app/qml/shared/*` sind **Kopien** der `contents/ui/*`-Komponenten (QQC2 statt PlasmaComponents3, Drift bekannt: todo.md:48).
  - Die JS-Logik unter `contents/code/*` wird von beiden direkt importiert.
- **FilmDayView existiert schon** (Kimai-only über `providerCapabilities.filmDays`, `timeTracker.js:41/153`).
  - Beginn und Ende gehen als normaler Kimai-Timesheet an den Server (create/patch).
  - Pause, Catering, Kategorie, Tagestyp, Drehtag, Zusatzgage und Notiz liegen lokal in `shared.json` → `filmDaysJson`, Schlüssel `"<projectId>|<YYYY-MM-DD>"` (`filmDays.js`).
  - Plasmoid: `main.qml:949-1060`. App: `FilmDayPage.qml` + `app/qml/main.qml:175-184`.
- **shared.json:** Auf dem Desktop teilen sich Plasmoid und App die Datei. Auf Android bleibt sie im App-internen Speicher (BUILD.md:98). **Lokale Drehtage können also auf mehreren Geräten unterschiedlich existieren.**
- Die App macht **keine** Holiday-/WorkContract-Plugin-Erkennung (`app/qml/main.qml:401-417` nutzt nur die User-Prefs). Einen Probe-Mechanismus gibt es nur im Plasmoid (`kimaiApi.js:879-950`, Cache nur im Speicher).
- ROADMAP.md:132-142 ist veraltet. Dort steht, `dayType`/`productionDay` fehlten in der API. Seit 2026-09-25 sind beide in GET/PUT enthalten, und PUT ist ein Teil-Update.

## 2. API-Inventar (Kurzfassung)

**Drehzettel** `/api/drehzettel` (`IsGranted('API')`)

| Endpunkt | Kern |
|---|---|
| GET `/ping` | `{installed, pluginVersion, apiVersions:["v1"]}` |
| GET `/v1/engagement-status?project&user?&date?` | `{active, engagementId, toggleDefault, rulesetName}` |
| GET/PUT `/v1/film-days/{date}?project&user?` | `{date, engagementId, breakMinutes\|null, catering:bool, category\|null, note\|null, dayType, productionDay\|null}`. PUT ist partiell, `null` setzt auf den Regelwerk-Default zurück, 400 `{error}` |

- Ein Engagement gehört genau zu einem User und einem Projekt, ein FilmDay ist eindeutig pro (Engagement, Datum). Plasmais Schlüssel Projekt+Datum passt also 1:1 für den eigenen User.
- Kein Engagement, unbekanntes Projekt und ungültiges Datum liefern alle dasselbe 404. Fremde Rechte oder ein fehlendes `drehzettel`-Recht (`assertView`) liefern 403.

**Mileage** `/api/mileage` (`IsGranted('mileage')`): `meta`, `trips` (Jahr/Monat), `trips/{id}` GET/PATCH/DELETE, POST `trips`, `vehicles`, `suggestions` + `accept`/`dismiss`, `tax/{year}`. Details stehen in der alten Analyse. **Neu:** PATCH/POST `trips` nimmt `timesheet` an (nur eigene Einträge; setzt `project` automatisch, wenn es nicht mitgeschickt wird).

## 3. Feld-Mapping lokal ↔ API

| Lokal (`filmDays.js`) | Default lokal | API | Abweichung / Regel |
|---|---|---|---|
| `breakMinutes` int, UI 0–360 | **45** (immer explizit) | `breakMinutes` int\|null, 0–720 | `null` = Regelwerk-Default. UI auf 0–720 erweitern und die Option „Standard (x min)“ anbieten (braucht D2). Lokal kann man einen Default nicht von einer bewussten 45 unterscheiden → bei der Migration als expliziten Wert senden. |
| `catering` `"yes"/"no"` | `"no"` | `catering` bool | Umrechnen: `=== "yes"` ↔ `true`. |
| `category` `""`/workday/saturday/sunday/holiday | `""` | string\|null | `""` ↔ `null` (der Server akzeptiert beides). |
| `dayType` workday/travel | workday | gleich | identisch |
| `productionDay` int\|null, UI **0–999** („Drehtag-Zähler“) | null | **`shootingDayNumber`** int\|null, **1–999** | Entschieden (D7): Der lokale Zähler ist der fortlaufende Drehtag der Produktion und wird zu `shootingDayNumber` (rein informativ). |
| – (neu) | – | **`productionDay`** int\|null, **1–7** | Tag in der Drehwoche, steuert die Zuschläge am 6. und 7. Tag (`WeekCalculator.php:46`). Lokal gab es das Feld nicht, die Migration sendet es nicht. Neues Eingabefeld „Drehtag der Woche (1–7, leer = automatisch)“. |
| `extraPayCents` int | 0 | – | Bis D6 lokal lassen, danach `extraPayCents`. |
| `note` string | `""` | string\|null, getrimmt, ≤ 500 | `""` ↔ `null`. Client: `maximumLength: 500`, trimmen. |

Reine Funktionen in `filmDays.js`: `toApiPatch(local, serverOrNull)` (liefert nur die abweichenden Keys), `fromApi(json, localExtras)`, `isServerEmpty(json)`, `planMigration(map, projectIds, cutoff)`.

## 4. Entscheidungen (Empfehlung)

1. **Lokaler Modus bleibt als Fallback**, und zwar nur wenn `ping` **404** liefert (Plugin fehlt) oder `apiVersions` kein `v1` enthält. Der Grund: 2.0 liefert die View bereits aus, und Nutzer ohne Plugin haben Daten. Das Info-Label bleibt dann stehen.
2. **Ist das Plugin da, ist der Server die Quelle der Wahrheit** (Server-Modus). Lokal schreibt Plasmai dann nur noch `extraPayCents` (bis D6) und die Offline-Warteschlange. So gibt es keinen Split-Brain.
3. **Erkennung:** `ping` pro Profil.
   - 200 + v1 → Server-Modus.
   - 404 → lokaler Modus.
   - 0/5xx → transient, nicht cachen.
   - Das Ergebnis wird **pro Profil persistent** in `shared.json` gespeichert (`drehzettelModeByProfile`), damit Plasmai offline nicht in den lokalen Modus kippt. Refresh alle 24 h bzw. beim Profilwechsel.
4. **Engagement-Gating** pro (Projekt, Datum):
   - `engagement-status`, Cache 1 h pro Profil+Projekt+Datum.
   - `active` → Extras aktiv, Kopfzeile „Drehtag · <rulesetName>“.
   - Nicht aktiv → Extras ausgeblendet mit dem Hinweis „Kein aktives Engagement – nur Beginn/Ende werden gespeichert“. Beginn und Ende bleiben speicherbar.
   - Mit D1 wird die Engagement-Liste des Tages einmal geladen, der Picker markiert Filmprojekte vor, und die Statusabfrage pro Projekt entfällt.
5. **Rechte:**
   - Mit D3 kommt `permissions.view` aus `ping`.
   - Ohne D3 gilt: 403 auf GET film-days → Extras read-only bzw. ausgeblendet mit dem Hinweis „Kein Recht ‚drehzettel‘“, kein lokaler Fallback.
   - Der Parameter `user` wird nie gesendet (nur eigene Daten).
6. **Offline / Fehler:**
   - GET schlägt transient fehl → Formular mit den zuletzt gesehenen Serverwerten (Speicher-Cache) anzeigen, Extras deaktivieren, Hinweis.
   - Das Speichern bleibt zweistufig: erst Timesheet, dann PUT. Scheitert der PUT transient, wird der Patch in `filmDaysPending` (shared.json, Schlüssel Profil|Projekt|Datum) abgelegt und beim nächsten Öffnen oder Verbinden erneut gesendet. Dabei gilt: der Server gewinnt, wenn er seit dem Patch geändert wurde, erkennbar durch Vergleich mit dem mitgespeicherten Basiswert.
   - 400 → Feldfehler anzeigen, nicht in die Warteschlange.
7. **Einmalige Migration** (pro Profil und Gerät, nach Bestätigung):
   - Dialog „N lokale Drehtage auf den Server übertragen?“.
   - Kandidaten: Einträge, deren Projekt-ID im Projektkatalog des aktiven Profils vorkommt. Der Schlüssel enthält kein Profil, gemeldete Mehrdeutigkeit wird akzeptiert.
   - Je Eintrag sequenziell: GET.
     - 404 → „kein Engagement“, bleibt lokal, im Bericht.
     - Server leer (`isServerEmpty`: alles null, catering false, dayType workday) → PUT `toApiPatch`.
     - Server hat Werte und sie weichen ab → **der Server gewinnt**, der lokale Wert wird in `filmDaysConflicts` gesichert und im Bericht aufgelistet (Ansicht mit „lokal übernehmen“ pro Tag).
     - Gleich → erledigt.
   - Erfolgreiche Einträge bekommen `migratedAt` (nicht löschen). Löschen erst in einer späteren Version, damit ein Rollback möglich bleibt.
   - Resumable und idempotent. Ein zweites Gerät, z. B. Android, läuft mit denselben Regeln, der Server gewinnt.

## 5. TODO (priorisiert)

### Plugin-API-Voraussetzungen – Drehzettel
- **D1 M – in Arbeit** (`claude/plasmai-api`): `GET /v1/engagements?date=` → `DrehzettelApiController.php`. Keine Abhängigkeit.
- **D2 S – in Arbeit**: Defaults in GET (`defaultBreakMinutes`, `effectiveCategory`).
- **D3 S – in Arbeit**: `ping.permissions {view, manage}`.
- **D4 S – in Arbeit**: 404 unterscheidbar (`code: no_engagement|unknown_project`), fehlendes `project` → 400.
- **D5 M – später**: `GET /v1/days/{date}/summary` (netto, Zuschläge; füllt „Verdienst“ in der FilmDayView).
- **D6 S – in Arbeit**: `extraPayCents` (Entity, Migration, Patch, JSON).
- **D7 S – entschieden, in Arbeit (PR #4)**: zwei Felder. `productionDay` (1–7) = Tag in der Drehwoche für die Zuschläge am 6. und 7. Tag; neu `shootingDayNumber` (1–999) = fortlaufender Drehtag der Produktion, rein informativ.

### Plugin-API-Voraussetzungen – MileageBundle
- **M1 S – erledigt im Fix-PR**: `timesheet` in POST/PATCH `trips`.
- **M2 S**: `trips?from=&to=`, `suggestions?from=&to=`.
- **M3 S**: `ping`/`meta` um `apiVersion`, `permissions`, `commuteKm`, `defaultVehicle`, `dawarichConfigured`, `lockedMonths` erweitern.
- **M4 S**: `accept` mit `project`, `distanceKm`, `comment` und `timesheet`; Suggestion-JSON um `timesheet` ergänzen.
- **M5 S – erledigt**: Nicht-String-`comment` → 400.
- **M6 M (optional)**: `GET /summary?from=&to=`.

### Plasmai – Drehzettel: Migration FilmDayView → Server-API
- **P1 M ✅** `contents/code/kimaiApi.js`: `detectDrehzettel` (ping, v1; persistenter Cache pro Profil), `fetchEngagementStatus`, `fetchEngagements(date)` (D1), `fetchFilmDay`, `putFilmDay`. Tests in `tests/unit/tst_kimaiApi.qml` (200/403/404/5xx, Body enthält nur geänderte Keys). Braucht G2.
- **P2 S ✅** `contents/code/filmDays.js`: Mapping aus §3 (`toApiPatch`, `fromApi`, `isServerEmpty`, `planMigration`) plus Tests in `tests/unit/tst_filmDays.qml`. Keine Abhängigkeit.
- **P3 M ✅** Neu `contents/code/filmDaySync.js`: Modusentscheidung, Laden, zweistufiges Speichern, `filmDaysPending`-Warteschlange. Aufrufer mit Callbacks sind `contents/ui/main.qml` (ersetzt 969-1060) und `app/qml/FilmDayPage.qml`. So entsteht die Orchestrierung nicht doppelt. Braucht P1 und P2.
- **P4 M ✅** UI in `contents/ui/FilmDayView.qml` **und** `app/qml/shared/FilmDayView.qml`:
  - Property `mode` (local/server/noEngagement/noPermission/offline) mit passendem Label (ersetzt das feste Info-Label Z. 282).
  - Pause 0–720 mit „Standard“, zwei Felder „Drehtag der Woche (1–7)“ und „Drehtag der Produktion (1–999)“ im Server-Modus, `maximumLength` 500 bei der Notiz.
  - Zusatzgage als „nur auf diesem Gerät“ markiert, bis D6 da ist.
  - Kopfzeile mit `rulesetName`.
  - Braucht P3, für „Standard“ zusätzlich D2.
- **P5 S ✅** Engagement-Gating beim Projekt- und Datumswechsel: `onProjectChosen` lädt Status und Extras neu (behebt B1). Picker-Markierung per D1.
- **P6 M ◐** Migrationsdialog mit Bericht: Plasmoid als Overlay in `contents/ui/main.qml`, App als `Kirigami.PromptDialog` in `FilmDayPage.qml`. Konfliktliste mit „lokal übernehmen“. Braucht P3.
- **P7 S ✅** Rechte: D3 auswerten, 403 → `noPermission`. Braucht D3 bzw. läuft ohne D3 über 403.

### Plasmai – Anfahrten (2.0-Struktur)
- **A1 M** `kimaiApi.js`: `detectMileage` (`/meta` 200/403), `fetchMileageMeta`, `fetchTrips`, `createTrip`/`patchTrip` (mit `timesheet`), `fetchVehicles`, `fetchSuggestions`, `accept`/`dismiss`. Braucht G2.
- **A2 M** `contents/ui/TripSheet.qml` plus Kopie `app/qml/shared/TripSheet.qml`: km, Zweck, Fahrzeug, Ziel, Hin/Rück, verknüpft mit einem Timesheet (M1).
- **A3 S Desktop:** Overflow-Eintrag „Fahrt erfassen“ in `contents/ui/ActivityListRow.qml` (Recents) und am laufenden Eintrag. `mainViewMode: "trip"` in `contents/ui/main.qml`.
- **A4 M Mobile:**
  - Neue Seite `app/qml/TripsPage.qml` (Monatsliste, Vorschläge, Aktion „Fahrt erfassen“, „Arbeitsweg heute“).
  - Drawer-Eintrag und Component in `app/qml/main.qml`.
  - Zeilenmenü in `app/qml/shared/ActivityListRow.qml` → öffnet TripSheet vorbelegt.
  - In `FilmDayPage` bei `dayType = travel` nach dem Speichern „Anfahrt erfassen“ anbieten.
  - Die Dawarich-Vorschläge gehören primär hierher.
- **A5 S** Vorschläge-Zeile auf dem Desktop (`contents/ui/main.qml`), lazy geladen, per Schalter abschaltbar.
- **A6 S** km-Kachel in `contents/code/statsData.js` sowie `contents/ui/StatsView.qml` und `app/qml/shared/StatsView.qml`.

### Gemeinsam
- **G1 S ✅** `timeTracker.js`: Capabilities `drehzettelApi` und `mileage` (Kimai-only), `filmDays` bleibt. DESIGN.md-Liste ergänzen.
- **G2 S ✅** `kimaiApi.js`: generischer `detectPlugin(url, token, path)` mit Profil-Cache. Einmal auch in `app/qml/main.qml` aufrufen, die App hat heute keine Probe.
- **G3 S** Schalter „Anfahrten anzeigen“: Plasmoid über `contents/config/main.xml` + `ConfigDisplay.qml`, App über `app/qml/SettingsPage.qml`. Keys für beide in `contents/code/sharedConfig.js` (Liste Z. 44) aufnehmen, ebenso `filmDaysPending`, `filmDaysConflicts` und `drehzettelModeByProfile`.
- **G4 S** i18n: `translate/extract.sh`, `fill_po.py`, App-Strings in `translate/langs/app_strings.py`, `po2json.py` für Android.
- **G5 M** Tests: `tst_filmDays.qml`, `tst_kimaiApi.qml`, `tst_statsData.qml`, Viewer-Test ohne Plugins. Keine Live-Schreibtests.
- **G6 S** Doku:
  - DESIGN.md §„Film day view“ neu schreiben (Modi, Migration, Gating).
  - ROADMAP.md:132-142 korrigieren.
  - README, CHANGELOG, app/BUILD.md (Migration pro Gerät).

**Stand 2026-09-25 (`claude/plasmai-plugins`):**
- G1, G2, P1–P5, P7 umgesetzt. Abweichungen vom Plan:
  - Probe-Cache heißt `pluginProbesJson` (generisch, Schlüssel `profileId|url|plugin`, 24 h) statt `drehzettelModeByProfile`. Die Holiday-/WorkContract-Erkennung bleibt bei ihrem eigenen Stundencache (nicht umgebaut, zu riskant ohne Live-WorkContract).
  - Engagement-Gating ohne eigenen `engagement-status`-Aufruf: das GET film-days ist die Prüfung (404 `no_engagement`). `rulesetName` kommt aus `/v1/engagements?date=` (1 h Cache pro Profil+Datum), bei alten Plugins aus `engagement-status`. Keine Picker-Markierung.
  - `productionDay` = „Zuschlagstag (1–7, leer = automatisch)“ (Tag der TV-FFS-Kalenderwoche für die Zuschläge am 6./7. Tag; Streak-Modus „consecutive“ entfällt, `streakMode` wird nicht ausgewertet).
  - Zusatzgage geht an den Server (`extraPayCents`); nur bei Plugins ohne `extraPay` bleibt sie lokal („nur auf diesem Gerät“).
  - Verdienst aus `/v1/days/{date}/summary` (`payCents`, Währung).
- P6 teilweise: Planer, Runner (`FilmDaySync.migrate`) und eine Inline-Bestätigung in der FilmDayView (beide UIs) mit Bericht. Konflikte bleiben lokal unangetastet und bekommen `migrated[profileKey].result = "conflict"`; eine Konfliktansicht mit „lokal übernehmen“ und `filmDaysConflicts` fehlt noch. Einträge ohne Engagement werden nicht erneut angeboten.
- Getestet: Unit-Tests (`tst_filmDays`, `tst_kimaiRequests`, `tst_filmDaySync`) und Live-Replay der JS-Funktionen gegen Kimai 2.67 + Drehzettel (admin: Server-Modus, Speichern, nur geänderte Keys, 400, Warteschlange, Migration; user1: kein Engagement). Die QML-Views sind nur per qmllint geprüft, nicht gerendert.
- §6: B3, B8, B9 erledigt (`claude/filmday-b3-b8-b9`).

**Reihenfolge:** P2 und D-Punkte parallel → G1/G2 → P1 → P3 → P4/P5/P7 → P6. Danach A1 → A2 → A4 (mobil zuerst) → A3/A5/A6.

## 6. Bugs in FilmDayView / filmDays.js mit Bezug zur Migration

- **B1** ✅ behoben in `claude/plasmai-2.0-review-fixes`. Beim Projektwechsel werden die Extras und `filmDayTimesheet` nicht neu geladen. `onProjectChosen` lädt nur Aktivitäten (`contents/ui/main.qml:3147`, `FilmDayPage.qml:123`). Folge: Werte von Projekt A werden unter Projekt B gespeichert, und der Timesheet von A wird per PATCH auf B umgehängt.
- **B2** ✅ behoben in `claude/plasmai-2.0-review-fixes`. `match = entries[0]` als Fallback (`main.qml:990`, `FilmDayPage.qml:40`). Damit wird ein fremder Eintrag (anderes Projekt, evtl. der laufende Timer ohne `end`) gewählt und beim Speichern überschrieben bzw. gestoppt.
- **B3** ✅ Bei mehreren Einträgen pro Tag wird nur einer gepatcht, die übrigen bleiben liegen. Die Nettozeit ist falsch.
- **B4** `breakSpin.to: 360` und `applyEntryFields` schneiden Serverwerte bis 720 still ab. Beim nächsten Speichern ist der Wert verloren.
- **B5** Lokal gibt es nur einen Zähler 0–999. Gelöst durch D7: Er wird zu `shootingDayNumber`; `productionDay` (1–7) kommt als neues Feld dazu. Der Wert 0 wird bei der Migration als leer behandelt.
- **B6** Die Notiz hat lokal kein Limit, der Server 500 → 400.
- **B7** `entryDefaults().breakMinutes = 45` wird immer explizit gespeichert. Ein Regelwerk-Default lässt sich nicht erkennen.
- **B8** ✅ Der Schlüssel `projectId|date` enthält kein Profil bzw. keine Server-URL. Projekt-IDs verschiedener Kimai-Instanzen kollidieren.
- **B9** ✅ Die App lädt `filmDaysJson` nur beim Start (`app/qml/main.qml:662`) und schreibt die ganze Map zurück. Auf dem Desktop überschreibt sie Einträge, die das Plasmoid inzwischen geschrieben hat (Last-Writer-Wins).
- **B10** ✅ behoben in `claude/plasmai-2.0-review-fixes`. `FilmDayPage.doSave` ignoriert Validierungs- und API-Fehler ohne Meldung (`return` in Z. 68/81) und prüft keinen Busy-Zustand.
- **B11** Das Speichern ist nicht atomar: Scheitert ein späterer PUT, sind Timesheet und Extras inkonsistent. Das wird mit P3 (Warteschlange) gelöst.
