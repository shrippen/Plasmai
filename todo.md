# TODO: Android / Plasma-Mobile-App an Plasmoid angleichen

Stand: 2026-09-21, Branch `feature/android-plasmamobile`. Alle Änderungen sind uncommitted; der letzte Android-Build (`scripts/build-android.sh debug`) ist grün.

Ziel: möglichst viele Standard-Kirigami-Elemente statt eigener Controls, damit Plasmoid, Plasma Mobile und Android optisch und funktional angeglichen sind.

## Erledigt (auf dem Pixel 6 geprüft)
- [x] Icons: Breeze-Dark-Subset (95 SVGs) in `app/icons/breeze-dark/`, im QRC registriert, Theme in `app/main.cpp` (nur Android) gesetzt.
- [x] Timer-Karte: Zusammenfassung und Restzeit in zwei Zeilen, kompakter Leerzustand statt großem Placeholder.
- [x] Drawer-Navigation stapelt keine Seiten mehr (`root.navigateTo()` in `app/qml/main.qml`).
- [x] Seiten nutzen Kirigami-Titel (`title:`), eigene `Heading level 1` entfernt. Timer-Seite: "Add entry"/"Statistics" als Kirigami-`actions`, Toolbar oben (`pageStack.globalToolBar.style: ToolBar`).
- [x] Eigene Farb-Properties (`root.bg*`/`root.clr*`) entfernt, überall `Kirigami.Theme.*`.
- [x] Tooltips auf Touch aus (`!Kirigami.Settings.isMobile`).
- [x] Statistik: Billable-Filter mit sichtbarem Hintergrund im aktiven Zustand.
- [x] Add entry: Floating-Placeholder ("31.01.00", "23:59") über gefüllten Feldern ausgeblendet; Seite rendert korrekt.

- [x] Funktionstest auf dem Pixel 6 (Timer): Continue, Stop, Beschreibung, Bearbeiten laufender Eintrag (Save/Cancel), Recent-Menü (Pin/Unpin, Edit, Split, Delete mit Bestätigung), Edit-Seite mit Save. Behoben: Favoriten erschienen nie (`pinnedEntries` per `push` statt Zuweisung), Recent-Pin nutzte Objekte statt IDs (`[object Object]`), Favoriten zeigten Roh-IDs nach Kaltstart, Recent-Menü schloss sich bei jedem 30-s-Refresh (`recentTimesheets` nur noch bei Änderung ersetzen), Stop/Save/Cancel in der Karte waren hell.
- [x] Favorit starten (Play, Fix `startPinned`), "Start something else…"-Formular (Projekt-/Aktivitäts-Suche, Start), Create-Entity-Dialog (öffnet dunkel; `Material.theme: Material.Dark` am `ApplicationWindow` in `main.qml` färbt "Create customer" korrekt) auf dem Pixel 6 geprüft.
- [x] Add entry speichern, Wechsel bei laufendem Timer (Switch-Dialog, `switchConfirmRequested`-Signal statt `switchDialog` in `main.qml`), "Already running"-Hinweis (pinKey angeglichen) auf dem Pixel 6 geprüft. Tastatur: Timer-, Add-entry- und Verbindungsseite scrollen das Feld nach oben, Vorschlagsliste wird nicht mehr verdeckt (`SearchableCombo` platziert das Popup laufend neu, `ImhNoPredictiveText` für sofortiges Filtern).
- [ ] Idle-Dialog: auf Android nicht auslösbar (`supportsIdleDetection` nur unter Linux). Nur per Code-Review geprüft, nicht visuell. Split-Dialog mit sinnvollem Zeitpunkt ebenfalls offen.
- [ ] Datum-Popup: leerer Button zwischen `<` und `>` (Icons `go-previous-view`/`go-next-view`/`go-jump-today` jetzt im QRC, auf dem Gerät noch nicht erneut geprüft). Verbindung: doppeltes "Profile name" entfernt, ebenfalls nicht erneut geprüft.
- [ ] Kleinigkeiten: Beschreibungsfeld-Platzhalter ("Description…") auf der laufenden Karte fast unsichtbar (`placeholderTextColor` setzen); Floating-Labels "Select project…"/"Select activity…" überlappen den Rahmen; Menüposition der Row-Overflow-Menüs wechselt (oben/unten).

- [x] Add entry lädt schnell: Datum-/Zeit-Popups (`DatePopup`/`TimePopup`) werden per `Loader` erst beim ersten Öffnen erzeugt (vorher 4 Popups mit Kalender-Views beim Seitenaufbau, ca. 2 s).
- [x] Connection: Test-Button ohne Spacer, gleicher Abstand wie Save/Clear. Play-Icons in Favoriten/Recent auf `iconSizes.small` (wie Plasmoid). Color-Maintenance-Seite hat einen Erklärtext (`InlineMessage`). Datum-Popup: fehlende Icons im QRC ergänzt. Einstellungen: lange Checkbox-Texte brechen um (`shared/WrapCheckBox.qml`).
- [x] Übersetzungen: `translate/extract.sh` liest jetzt auch `app/qml`; App-only-Strings in `translate/langs/app_strings.py` (11 Sprachen). Plasma Mobile: CMake kompiliert `translate/*.po` zu `plasmai.mo` (KLocalizedString-Domain `plasmai`, Dev-Läufe über `PLASMAI_BUILD_LOCALE_DIR`). Android: `translate/po2json.py` erzeugt `app/i18n/<lang>.json` (im QRC, `I18nFallback` in `main.cpp`). Auf dem Pixel 6 mit App-Sprache Deutsch geprüft; Plasma-Mobile-Pfad nur gebaut, nicht gestartet. Workflow: `translate/extract.sh`, `python3 translate/fill_po.py`, `translate/build.sh`.

## Umgesetzt, aber noch NICHT auf dem Gerät geprüft
- [ ] Dialoge: Stop/Delete/Switch als `Kirigami.PromptDialog`, Split/Idle/Create-Entity als `Kirigami.Dialog` (`TimerPage.qml`, `shared/CreateEntityDialog.qml`). Prüfen: Größe, Buttons, `standardButton(Kirigami.Dialog.Ok)` in `CreateEntityDialog`, Idle-Dialog (`NoAutoClose`).
- [ ] Datum/Zeit: `DateField`/`TimeField` nutzen `DatePopup`/`TimePopup` aus kirigami-addons. Prüfen: Popup öffnet zentriert, Auswahl setzt Feld, dunkle Optik, `i18nd`/`i18ndc`-Fallback in `main.cpp`.
- [ ] Vendored kirigami-addons v1.6.0 (`dateandtime`, `components`, `delegates`): C++-Modelle in `app/addons/` (in `CMakeLists.txt`, `main.cpp` per `qmlRegisterType`), QML in `app/qml/kirigami-addons/`, Lizenzhinweis `app/addons/README.md`. Desktop-Build (`scripts/build-desktop.sh`) lief durch, Laufzeit auf Plasma Mobile ungeprüft.
- [ ] Alle übrigen Seiten (Statistik, Favoriten, Einstellungen, Verbindung, Farbwartung) nach der Umstellung auf `Kirigami.Page` + `QQC2.ScrollView` optisch durchsehen; Keyboard-Scroll in Verbindung/Add entry (`pageScroll.contentItem`) testen.

## Offen / bekannte Probleme
- [x] Timer-Karte: Zusammenfassung, "No activity" und Continue-Button liegen jetzt innerhalb der Karte (wie im Plasmoid, `heroColumn`); Höhe per `implicitHeight`. Continue-Button hat explizite `Material.*`-Farben, weil `Material.theme` innerhalb der Karte trotz `Material.Dark` Light lieferte (Ursache weiter unklar).
- [x] Übrige Seiten (Statistik, Add entry, Favoriten, Verbindung, Einstellungen, Farbwartung) und Datum-/Zeit-Popup auf dem Pixel 6 geprüft: alles dunkel, keine hellen Buttons. Kleinigkeiten: leerer Button zwischen `<` und `>` im Datum-Popup; Verbindung zeigt "Profile name" doppelt (Label und Floating-Label) und hat große Abstände; Einstellungen scrollen noch nicht bis unten geprüft.
- [x] **Continue-Button** war hell mit weißem Text, weil `Material.theme` im `Kirigami.Page`-Kontext Light lieferte. Fix: `Material.theme: Material.Dark` auf der `pageScroll`-ScrollView in `TimerPage.qml` (auf dem Pixel 6 geprüft). Die übrigen Seiten haben dieselbe Struktur und brauchen ggf. denselben Fix (siehe Seiten-Review oben).
- [ ] `Kirigami.ScrollablePage` färbt Material-Controls falsch (helle Buttons, dunkle Felder, `Material.theme` liest 0/Light). Deshalb bewusst `Kirigami.Page` + `QQC2.ScrollView`. Falls Ursache gefunden: auf `ScrollablePage` zurückstellen.
- [ ] `app/qml/kirigami-styles/.../Material/Theme.qml`: Dark-Werte jetzt als Literale (`_fg`, `_bg`, `_dialog`, `_listHighlight`), weil `Material.*` dort ohne Item-Kontext Light liefert. Prüfen, ob die Palette zum Plasmoid passt (`_bg` #1e1e22).
- [ ] Warnung im Log: `QFont::setPointSize: Point size <= 0 (-3)`.
- [ ] Nach Statistik-Seite: "Projects by hour"/"Tätigkeitsverteilung" (Pies) weiter unten noch nicht visuell verglichen.

## Noch nicht gemacht (aus dem Plan)
- [ ] `Kirigami.FormLayout` für Add entry, Connection, Settings, Statistik-Filter (Settings/Connection nutzen teilweise schon `FormLayout`). Statistik-Segmente evtl. als `QQC2.TabBar`.
- [ ] Listen: `ActivityListRow` auf `Kirigami.SwipeListItem` / `QQC2.SwipeDelegate` mit Kirigami-Actions; Kebab-Menü als `Kirigami.ActionToolBar`.
- [ ] `SearchableCombo` (452 Zeilen) auf `QQC2.ComboBox` (editierbar, gefiltertes Model) bzw. `Kirigami.SearchField` ablösen; `TagPicker` (385 Zeilen) prüfen.
- [ ] Theme angleichen: Radien/Abstände/Schrift, Monospace-Timer mit Glow, Tracking-Tint wie im Plasmoid (`DESIGN.md`).
- [ ] Gemeinsame Quelle für `contents/ui/` und `app/qml/shared/` (aktuell Kopien; Diffs > 40 Zeilen: StatsView, DaySparkline, ActiveEditView) statt Drift.
- [ ] Plasma-Mobile-Render live prüfen (kein Gerät/keine Session bisher; dort gilt Breeze statt Material, Icon-Fallback nur auf Android).

## Plasma Mobile (Desktop-Test, ohne echtes Gerät)
Kein Plasma-Mobile-Gerät vorhanden. Stattdessen `app/build-test/plasmai-app` (CMake-Option `-DPLASMAI_TEST_DRIVER=ON`, Default aus) mit `org.kde.desktop`-Stil unter `QT_QPA_PLATFORM=offscreen` + `QT_QPA_PLATFORMTHEME=kde` betrieben — das entspricht optisch dem, was Plasma Mobile zeigt (Breeze statt Material, kein Icon-Fallback nötig). Steuerung per `app/testdriver.h` (Skriptsprache `size/wait/grab/click/text/key/scroll/js/quit`, `PLASMAI_TEST_SCRIPT`/`PLASMAI_TEST_OUT`), Screenshots nur vom App-Fenster (kein Desktop-Screenshot).
- [x] Alle Seiten (Timer, Add entry, Statistik, Favoriten, Verbindung, Einstellungen, Farbwartung) gerendert und geprüft — sehen wie unter Android aus (KDE-Palette statt Material-Dark, das ist erwartet).
- [x] Deutsche Übersetzung (`LANGUAGE=de`) auf allen Seiten geprüft — funktioniert wie unter Android, inkl. Farbwartungs-Hinweistext.
- [x] Funktionstest: "Start something else…"-Formular mit Projekt-/Aktivitätssuche, Datum-/Zeit-Popup, Start, Stop, Zeilenmenü (Pin/Edit/Split/Delete-Dialog mit Bestätigung), Add entry speichern (inkl. Datum-/Zeit-Popup). Alle erzeugten Test-Einträge wieder gelöscht, Wochensumme danach wieder beim Ausgangswert (18h 15m).
- [x] Bug gefunden und behoben: Das Zeilen-Overflow-Menü (`historyMenu.popup()`) öffnete links oben im Fenster statt an der Schaltfläche — `popup()` ohne Argumente folgt dem Mauszeiger, was auf Touch/Plasma-Mobile bedeutungslos ist. Jetzt an `historyButton` verankert (`app/qml/shared/ActivityListRow.qml`).
- [ ] Nicht geprüft: echtes Touch-Verhalten (Scroll-Fling, Soft-Keyboard-Verhalten, Bildschirmgrößen/Auflösungen), Idle-Dialog (derselbe Trigger wie Desktop, aber nicht ausgelöst), Statistik-Diagramme im Detail (nur Übersicht gesehen), reales Plasma-Mobile-Gerät.

## Hinweise zum Testen
- Build: `./scripts/build-android.sh debug`, Install: `adb install -r dist/android/plasmai-app.apk`, Screenshots: `adb exec-out screencap -p`.
- Vor Screenshots prüfen, dass Plasmai im Vordergrund ist (`adb shell dumpsys window | grep mCurrentFocus`); das Handy ist auch das Alltagsgerät.
- Desktop-Schnelltest: `./scripts/run-desktop.sh` (Material-Stil dort per `QT_QUICK_CONTROLS_STYLE=Material`). Keine Vollbild-Screenshots des Desktops machen.
- Referenz Plasmoid: `screenshots/01-panel.jpg`, `03-statistics.jpg`. Plan: `~/.claude/plans/majestic-twirling-magpie.md`.

## Code-Review Kimai 2.67 (Fixes aus PR #2 portiert)


Legende: ✅ = live gegen Kimai 2.67 reproduziert, 📖 = aus Code-Review.
Stand 2.0: Plasmoid (`contents/`) und App (`app/`, Android/Plasma Mobile) nutzen dieselbe API-Schicht (`contents/code/kimaiApi.js`, `providerUtil.js`); JS-Fixes gelten für beide. „N/A App“ = betrifft nur die Shell-Helfer des Plasmoids (App: QtKeychain/FileStore/IdleWatcher in `app/main.cpp`).

### P0
- [x] ✅ `exported: false` nie senden – ROLE_USER-Writes (Start, manueller Eintrag, Filmtag) scheiterten mit „extra fields“; live als user1 200
- [x] ✅ `billable` nur senden, wenn vom User geändert; ohne edit_billable (400 „extra fields“, `billable` fehlt in `errors.children`) einmal ohne `billable` wiederholen, pro Server/Token merken, Hinweis anzeigen (Plasmoid: Meldung, App: Passive Notification). Split übernimmt den Wert des Originals (wird ebenso verworfen).

### P1
- [x] ✅ fetchTimesheetsRange: X-Total-Pages, 404 nach Seite 1 = Ende – live mit genau 100 Einträgen: 1 Request, 100 Einträge
- [x] ✅ customers/projects/activities einmal ohne Paging laden
- [x] ✅ restart mit {"copy":"all"} – live: Beschreibung wird übernommen
- [x] 📖 Idle-Discard: idleSince beim Erkennen speichern, Ende nicht vor Beginn – Plasmoid und App (`app/qml/main.qml`)
- [x] 📖 Signal-Parameter billable `var` statt `bool` (ManualEntryView, ActiveEditView) – in `contents/ui` und `app/qml/shared`; FilmDayView hat kein billable
- [x] 📖 Token nicht als `sh -c`-Argument an kwallet.sh – `KIMAI_TOKEN=… exec sh kwallet.sh`. N/A App (QtKeychain; Android: Datei im App-Datenverzeichnis)

### P2
- [x] 📖 Request-Timeout: Watchdog-Timer (5 s) bricht Requests nach 30 s ab – Plasmoid und App. Offen: KCM-Seiten (eigener Prozess) haben keinen Watchdog
- [x] 📖 Beim Start `begin` weglassen (Kimai setzt „jetzt“ in der Kimai-Zeitzone)
- [ ] 📖 Zeiten in Kimai-Profil-Zeitzone (manuelle Einträge, Bearbeiten, Split, Idle-Ende, Filmtag) – offen: QML-JS hat kein Intl/IANA-Zeitzonen
- [x] 📖 mktemp statt $FILE.tmp (sharedConfig.sh, catalogCache.sh); App: `QSaveFile` in FileStore/Token-Datei
- [x] 📖 Katalog nicht als `sh -c`-Argument (E2BIG ab 128 KiB) – Chunks über `append/commit`; in 2.0 auch shared.json (wächst mit `filmDaysJson`). N/A App
- [x] 📖 Versteckte Einträge (visible=false) in Pickern ausfiltern – gemeinsame Picker-Modelle, gilt auch für die App
- [ ] 📖 Absence-Credit nur für automatisch gebuchte Einträge (workContractAdjust.js) – offen: Auto-Buchungen des WorkContractBundle ohne Doku/Fixture nicht sicher erkennbar
- [x] 📖 idle.sh: Fallback auf D-Bus wenn IdleHint ≠ yes. App fragt ScreenSaver-D-Bus direkt (Android: keine Idle-Erkennung)
- [x] 📖 Kleinkram: Abwesenheitsdauer ≤ 24 = Stunden, Sparkline DST, notify-send `--` (App: D-Bus direkt, N/A), fileUrlToPath Percent-Decoding (N/A App)

### Neu in 2.0 gefunden
- [x] 📖 App-Split erzeugte die zweite Hälfte mit `projectId`/`activityId` statt `project`/`activity` → jeder Split scheiterte nach dem Kürzen des Originals (live: „begin, project and activity are required“); billable/Tags fehlten
- [x] 📖 App `appBackend.js`: One-shot-Listener trennte bei der ersten Antwort, auch für ein anderes Profil → bei parallelen Keychain-Loads ging ein Token-Callback verloren
- [ ] 📖 App zeigt fehlgeschlagene Writes (Stop, Bearbeiten, Löschen, Split) meist nicht an – nur Verbindungsstatus

### Filmtag (Fixes)
- [x] B1 Projektwechsel lud Eintrag und Extras nicht neu → Extras unter falschem Projekt, alter Eintrag wurde aufs neue Projekt gepatcht. Jetzt: Projektwahl lädt den Tag neu; veraltete Antworten (schnelles Blättern) werden verworfen
- [x] B2 Fallback `entries[0]` griff fremde Einträge (auch den laufenden Timer) und überschrieb/stoppte sie. Jetzt: nur beendete Einträge des gewählten Projekts, sonst neuer Eintrag (`FilmDays.pickDayEntry`/`saveTargetId`)
- [x] B10 App `FilmDayPage.doSave` schluckte Validierungs-/API-Fehler, kein Schutz gegen Doppel-Save – jetzt Passive Notification, Save-Guard

### Filmtag – Drehzettel-API (`filmDaySync.js`, `todo-plugins.md` P1–P7)
Nur Unit-Tests und Live-Replay der JS-Logik gegen Kimai 2.67 + Drehzettel (admin mit Engagement, user1 ohne); FilmDayView/FilmDayPage nicht gerendert (Plasmoid-Viewer/App-Build hier nicht verfügbar).
- [ ] B3 Mehrere Einträge pro Tag: nur einer wird gepatcht
- [x] B4 Pause lokal max. 360 min, Server erlaubt 720 – jetzt 0–720 in beiden Modi
- [x] B5 Lokaler Zähler 0–999 → `shootingDayNumber` (D7), 0 = leer; `productionDay` des Servers ist das neue Feld „Zuschlagstag (1–7)“
- [x] B6 Notiz auf 500 Zeichen begrenzt, getrimmt
- [x] B7 Server-Modus: Option „Standard (n min)“ = `null`; lokal bleibt 45 explizit (bei der Migration als 45 gesendet)
- [ ] B8 Speicher-Key ohne Profil/Server-URL (lokaler Modus; Warteschlange, Probe-Cache und Migrationsmarken enthalten Profil+URL)
- [ ] B9 App liest `filmDaysJson` nur beim Start und schreibt die ganze Map zurück (überschreibt Plasmoid-Änderungen)
- [x] B11 Zweistufiges Speichern: scheitert der PUT transient, landet der Patch in `filmDaysPending` und wird später gesendet (Server gewinnt bei Änderung dazwischen)
- [ ] Nachtdrehs (Ende nach Mitternacht) sind nicht erfassbar (Ende muss nach Beginn am selben Tag liegen)

Plan für die Anbindung der Plugins Drehzettel und Anfahrten: siehe `todo-plugins.md`.
