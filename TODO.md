# TODO – Review-Befunde (Kimai 2.67)

Legende: ✅ = live gegen Kimai 2.67 reproduziert, 📖 = aus Code-Review.

## P0
- [ ] ✅ `exported: false` nie senden (kimaiApi.js:766)
- [ ] ✅ `billable` nur senden, wenn vom User geändert UND Berechtigung vorhanden (main.qml:840, main.qml:2135, manuelle Einträge)

## P1
- [ ] ✅ fetchTimesheetsRange: X-Total-Pages nutzen, 404 nach Seite 1 = Ende (kimaiApi.js:1294)
- [ ] ✅ customers/projects/activities einmal ohne Paging laden (getJsonAllPages, kimaiApi.js:302)
- [ ] ✅ restart mit {"copy":"all"} (kimaiApi.js:802)
- [ ] 📖 Idle-Discard: idleSince beim Erkennen speichern, Ende nicht vor Beginn (main.qml:589)
- [ ] 📖 ManualEntryView-Signal-Parameter billable als var statt bool (ManualEntryView.qml:44/379)
- [ ] 📖 Token über stdin statt env-Argument an kwallet.sh (secret.js:90)

## P2
- [ ] 📖 Request-Timeout (Timer + abort), isBusy nicht hängen lassen
- [ ] 📖 Zeiten in Kimai-Profil-Zeitzone; beim Start `begin` weglassen
- [ ] 📖 mktemp statt $FILE.tmp (sharedConfig.sh, catalogCache.sh)
- [ ] 📖 Katalog nicht als sh -c-Argument (E2BIG ab 128 KiB)
- [ ] 📖 Versteckte Einträge (visible=3) in Pickern ausfiltern
- [ ] 📖 Absence-Credit nur für automatisch gebuchte Einträge (workContractAdjust.js:354)
- [ ] 📖 idle.sh: Fallback auf D-Bus wenn IdleHint ≠ yes
- [ ] 📖 Kleinkram: 1000er-Heuristik Abwesenheitsdauer (workContractAdjust.js:224), Sparkline DST, notify-send --, fileUrlToPath Percent-Decoding
