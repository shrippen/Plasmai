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
