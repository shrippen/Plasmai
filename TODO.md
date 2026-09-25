# TODO – Review-Befunde (Kimai 2.67)

Legende: ✅ = live gegen Kimai 2.67 reproduziert, 📖 = aus Code-Review.
Stand 2.0: Plasmoid (`contents/`) und App (`app/`, Android/Plasma Mobile) nutzen dieselbe API-Schicht (`contents/code/kimaiApi.js`, `providerUtil.js`); JS-Fixes gelten für beide. „N/A App“ = betrifft nur die Shell-Helfer des Plasmoids (App: QtKeychain/FileStore/IdleWatcher in `app/main.cpp`).

## P0
- [x] ✅ `exported: false` nie senden – ROLE_USER-Writes (Start, manueller Eintrag, Filmtag) scheiterten mit „extra fields“; live als user1 200
- [x] ✅ `billable` nur senden, wenn vom User geändert; ohne edit_billable (400 „extra fields“, `billable` fehlt in `errors.children`) einmal ohne `billable` wiederholen, pro Server/Token merken, Hinweis anzeigen (Plasmoid: Meldung, App: Passive Notification). Split übernimmt den Wert des Originals (wird ebenso verworfen).

## P1
- [x] ✅ fetchTimesheetsRange: X-Total-Pages, 404 nach Seite 1 = Ende – live mit genau 100 Einträgen: 1 Request, 100 Einträge
- [x] ✅ customers/projects/activities einmal ohne Paging laden
- [x] ✅ restart mit {"copy":"all"} – live: Beschreibung wird übernommen
- [x] 📖 Idle-Discard: idleSince beim Erkennen speichern, Ende nicht vor Beginn – Plasmoid und App (`app/qml/main.qml`)
- [x] 📖 Signal-Parameter billable `var` statt `bool` (ManualEntryView, ActiveEditView) – in `contents/ui` und `app/qml/shared`; FilmDayView hat kein billable
- [x] 📖 Token nicht als `sh -c`-Argument an kwallet.sh – `KIMAI_TOKEN=… exec sh kwallet.sh`. N/A App (QtKeychain; Android: Datei im App-Datenverzeichnis)

## P2
- [x] 📖 Request-Timeout: Watchdog-Timer (5 s) bricht Requests nach 30 s ab – Plasmoid und App. Offen: KCM-Seiten (eigener Prozess) haben keinen Watchdog
- [x] 📖 Beim Start `begin` weglassen (Kimai setzt „jetzt“ in der Kimai-Zeitzone)
- [ ] 📖 Zeiten in Kimai-Profil-Zeitzone (manuelle Einträge, Bearbeiten, Split, Idle-Ende, Filmtag) – offen: QML-JS hat kein Intl/IANA-Zeitzonen
- [x] 📖 mktemp statt $FILE.tmp (sharedConfig.sh, catalogCache.sh); App: `QSaveFile` in FileStore/Token-Datei
- [x] 📖 Katalog nicht als `sh -c`-Argument (E2BIG ab 128 KiB) – Chunks über `append/commit`; in 2.0 auch shared.json (wächst mit `filmDaysJson`). N/A App
- [x] 📖 Versteckte Einträge (visible=false) in Pickern ausfiltern – gemeinsame Picker-Modelle, gilt auch für die App
- [ ] 📖 Absence-Credit nur für automatisch gebuchte Einträge (workContractAdjust.js) – offen: Auto-Buchungen des WorkContractBundle ohne Doku/Fixture nicht sicher erkennbar
- [x] 📖 idle.sh: Fallback auf D-Bus wenn IdleHint ≠ yes. App fragt ScreenSaver-D-Bus direkt (Android: keine Idle-Erkennung)
- [x] 📖 Kleinkram: Abwesenheitsdauer ≤ 24 = Stunden, Sparkline DST, notify-send `--` (App: D-Bus direkt, N/A), fileUrlToPath Percent-Decoding (N/A App)

## Neu in 2.0 gefunden
- [x] 📖 App-Split erzeugte die zweite Hälfte mit `projectId`/`activityId` statt `project`/`activity` → jeder Split scheiterte nach dem Kürzen des Originals (live: „begin, project and activity are required“); billable/Tags fehlten
- [x] 📖 App `appBackend.js`: One-shot-Listener trennte bei der ersten Antwort, auch für ein anderes Profil → bei parallelen Keychain-Loads ging ein Token-Callback verloren
- [ ] 📖 App zeigt fehlgeschlagene Writes (Stop, Bearbeiten, Löschen, Split) meist nicht an – nur Verbindungsstatus

## Filmtag (Fixes)
- [x] B1 Projektwechsel lud Eintrag und Extras nicht neu → Extras unter falschem Projekt, alter Eintrag wurde aufs neue Projekt gepatcht. Jetzt: Projektwahl lädt den Tag neu; veraltete Antworten (schnelles Blättern) werden verworfen
- [x] B2 Fallback `entries[0]` griff fremde Einträge (auch den laufenden Timer) und überschrieb/stoppte sie. Jetzt: nur beendete Einträge des gewählten Projekts, sonst neuer Eintrag (`FilmDays.pickDayEntry`/`saveTargetId`)
- [x] B10 App `FilmDayPage.doSave` schluckte Validierungs-/API-Fehler, kein Schutz gegen Doppel-Save – jetzt Passive Notification, Save-Guard

## Filmtag – Migration (Server-API, separat)
- [ ] B3 Mehrere Einträge pro Tag: nur einer wird gepatcht
- [ ] B4 Pause lokal max. 360 min, Server erlaubt 720
- [ ] B5 productionDay lokal 0–999, Server 1–7
- [ ] B6 Notiz lokal unbegrenzt, Server 500 Zeichen
- [ ] B7 Pause wird immer explizit (Default 45) gespeichert
- [ ] B8 Speicher-Key ohne Profil/Server-URL
- [ ] B9 App liest `filmDaysJson` nur beim Start und schreibt die ganze Map zurück (überschreibt Plasmoid-Änderungen)
- [ ] B11 Speichern ist zweistufig (Kimai-Eintrag, dann lokale Extras), nicht atomar
- [ ] Nachtdrehs (Ende nach Mitternacht) sind nicht erfassbar (Ende muss nach Beginn am selben Tag liegen)
