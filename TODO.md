# TODO – Review-Befunde (Kimai 2.67)

Legende: ✅ = live gegen Kimai 2.67 reproduziert, 📖 = aus Code-Review.

## P0
- [x] ✅ `exported: false` nie senden (kimaiApi.js:766) – wird nicht mehr gesendet; Start/manueller Eintrag als user1 live 200
- [x] ✅ `billable` nur senden, wenn vom User geändert UND Berechtigung vorhanden (main.qml:840, main.qml:2135, manuelle Einträge) – Kimai 2.67 liefert in `/api/users/me` nur Rollen, keine Permissions (edit_billable ist konfigurierbar). Daher: nur bei Änderung senden; fehlt die Berechtigung (400 „extra fields“, `billable` fehlt in `errors.children`), einmal ohne `billable` wiederholen, pro Server/Token merken und Hinweis anzeigen. Split übernimmt weiterhin den Wert des Originals (wird bei fehlender Berechtigung ebenso verworfen).

## P1
- [x] ✅ fetchTimesheetsRange: X-Total-Pages nutzen, 404 nach Seite 1 = Ende (kimaiApi.js:1294) – live mit genau 100 Einträgen: 1 Request, 100 Einträge
- [x] ✅ customers/projects/activities einmal ohne Paging laden (getJsonAllPages, kimaiApi.js:302)
- [x] ✅ restart mit {"copy":"all"} (kimaiApi.js:802) – live: Beschreibung wird übernommen
- [x] 📖 Idle-Discard: idleSince beim Erkennen speichern, Ende nicht vor Beginn (main.qml:589)
- [x] 📖 ManualEntryView-Signal-Parameter billable als var statt bool (ManualEntryView.qml:44/379) – bestätigt: `bool` machte aus `null` `false`, d. h. jeder manuelle Eintrag sendete `billable:false`. Gleiches in ActiveEditView behoben.
- [x] 📖 Token über stdin statt env-Argument an kwallet.sh (secret.js:90) – stdin ist mit der Executable-Engine nicht möglich; stattdessen `KIMAI_TOKEN=… exec sh kwallet.sh`, womit die weltlesbare `sh -c`-Kommandozeile sofort ersetzt wird (Token nur noch in der Umgebung, an secret-tool über stdin)

## P2
- [x] 📖 Request-Timeout (Timer + abort), isBusy nicht hängen lassen – Watchdog-Timer (5 s) bricht Requests nach 30 s ab
- [x] 📖 Beim Start `begin` weglassen (Kimai setzt „jetzt“ in der Kimai-Zeitzone)
- [ ] 📖 Zeiten in Kimai-Profil-Zeitzone (manuelle Einträge, Bearbeiten, Split, Idle-Ende) – offen: QML-JS hat kein Intl/IANA-Zeitzonen; ein aus Serverantworten abgeleiteter Offset ist über DST-Grenzen nicht sicher
- [x] 📖 mktemp statt $FILE.tmp (sharedConfig.sh, catalogCache.sh)
- [x] 📖 Katalog nicht als sh -c-Argument (E2BIG ab 128 KiB) – Chunks à 30 000 Zeichen über `catalogCache.sh append/commit`
- [x] 📖 Versteckte Einträge (visible=3) in Pickern ausfiltern – Kunden/Projekte/Tätigkeiten mit `visible:false` (auch Projekte versteckter Kunden)
- [ ] 📖 Absence-Credit nur für automatisch gebuchte Einträge (workContractAdjust.js:354) – offen: Befund stimmt (echte Arbeit an Abwesenheitstagen wird gutgeschrieben), aber Auto-Buchungen des (kostenpflichtigen) WorkContractBundle sind ohne Doku/Fixture nicht sicher erkennbar
- [x] 📖 idle.sh: Fallback auf D-Bus wenn IdleHint ≠ yes
- [x] 📖 Kleinkram: 1000er-Heuristik Abwesenheitsdauer (≤ 24 = Stunden), Sparkline DST (Wanduhr-Sekunden), notify-send `--`, fileUrlToPath Percent-Decoding
