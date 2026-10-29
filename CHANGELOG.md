# Changelog

## [Unreleased]

## [2.6.3] — 2026-10-29

### English

The widget's "Switch activity" and "You were idle" dialogs have their buttons back.

#### Fixed
- Widget (Kante styles): the "Switch activity" and "You were idle" dialogs showed no buttons. A switch to a recent activity could not be confirmed, and the idle question could not be answered with "Keep time" or "Discard idle". Both dialogs show their buttons again, and a test now checks every dialog of the widget for this.

#### Note
- The app is unchanged from 2.6.2.

All changes: https://github.com/shrippen/Plasmai/compare/v2.6.2...v2.6.3

### Deutsch

Die Dialoge „Tätigkeit wechseln“ und „Du warst im Leerlauf“ des Widgets haben ihre Knöpfe wieder.

#### Behoben
- Widget (Kante-Stile): Die Dialoge „Tätigkeit wechseln“ und „Du warst im Leerlauf“ zeigten keine Knöpfe. Ein Wechsel zu einer zuletzt genutzten Tätigkeit ließ sich nicht bestätigen, die Leerlauf-Frage nicht mit „Zeit behalten“ oder „Leerlauf verwerfen“ beantworten. Beide Dialoge zeigen ihre Knöpfe wieder, und ein Test prüft das jetzt für jeden Dialog des Widgets.

#### Hinweis
- Die App ist gegenüber 2.6.2 unverändert.

## [2.6.2] — 2026-10-27

### English

The Plasma widget no longer fills the memory of the desktop shell.

#### Fixed
- Widget: plasmashell grew by gigabytes a day (14 GB after two days). Every save of the offline data stayed in memory; now nothing is kept. The offline data is also written less often (if nothing changed, once an hour instead of every five minutes; a running timer alone is no change) and no longer grows by a few entries every day.

All changes: https://github.com/shrippen/Plasmai/compare/v2.6.1...v2.6.2

### Deutsch

Das Plasma-Widget füllt nicht mehr den Speicher der Desktop-Shell.

#### Behoben
- Widget: plasmashell wuchs um Gigabytes am Tag (14 GB nach zwei Tagen). Jedes Speichern der Offline-Daten blieb im Arbeitsspeicher liegen; jetzt bleibt nichts zurück. Die Offline-Daten werden außerdem seltener geschrieben (ohne Änderung nur noch einmal pro Stunde statt alle fünf Minuten; ein laufender Timer allein zählt nicht als Änderung) und wachsen nicht mehr jeden Tag um ein paar Einträge.

## [2.6.1] — 2026-10-13

### English

The Plasma widget for 2.6.0: its package was missing from the 2.6.0 release.

#### Fixed
- 2.6.0 came without the widget package (`.plasmoid`) and the install script, so the one-line install command failed with "not found" while 2.6.0 was the latest release. The package build stopped at a comment that named the internal screenshot code it removes. The checks now build the widget package on every pull request, so this shows before a release.

#### Note
- No changes in the app or the widget beyond 2.6.0: everything new in 2.6.0 below applies.

All changes: https://github.com/shrippen/Plasmai/compare/v2.6.0...v2.6.1

### Deutsch

Das Plasma-Widget zu 2.6.0: Sein Paket fehlte im Release 2.6.0.

#### Behoben
- 2.6.0 kam ohne das Widget-Paket (`.plasmoid`) und das Installationsskript, deshalb schlug der Einzeiler zur Installation mit „nicht gefunden“ fehl, solange 2.6.0 das neueste Release war. Der Paketbau brach an einem Kommentar ab, der den internen Screenshot-Code nannte, den er entfernt. Die Prüfungen bauen das Widget-Paket jetzt bei jedem Pull Request, so fällt das vor einem Release auf.

#### Hinweis
- App und Widget sind gegenüber 2.6.0 unverändert: Alles Neue aus 2.6.0 unten gilt.

## [2.6.0] — 2026-10-13

### English

A terminal client for the desktop app, a day of its own for the activity chart, and editing that keeps the dates and times you enter.

#### New
- Terminal client in the desktop app (Linux, macOS): `plasmai-app --tui` shows the timer, recents, today as hour rows with gaps and the week as a table. 1–9 start or switch, `s` stops. For tracking from a terminal or over SSH; it uses the app's profile and keeps its own offline outbox. The widget has none.

#### Improved
- Statistics: the activity distribution has its own day switcher, so you can look at another day without moving the other charts. Day and week take half the width each; an empty day keeps the chart's height.
- Statistics (Kante styles): hovering a block in "Projects by hour" shows its project, time span and duration; on touch a tap does.

#### Fixed
- Editing an entry could move its start 100 years back. In a short date format with a two-digit year ("13.10.26", "10/13/26") the date field read its own text as 1926. A running entry then started in 1926, and Kimai refused a stopped one as too long. Two-digit years now mean this century.
- App time picker in 12-hour languages (US English and others): it showed a 24-hour dial without AM/PM and put 12:xx in the morning. It now shows 1–12 with AM/PM. In every language, Select without turning a dial gave the current time instead of the time it opened with.
- 12-hour time fields: typing an hour no longer moves a PM time to the morning (3 on 2:30 PM stays 3:30 PM).
- Statistics (Kante styles): the chart read-outs wrote project names in the project colour, which some colours made unreadable. They now use the text colour with a coloured square in front.

All changes: https://github.com/shrippen/Plasmai/compare/v2.5.3...v2.6.0

### Deutsch

Ein Terminal-Client für die Desktop-App, ein eigener Tag für das Tätigkeitsdiagramm und Bearbeiten, das Datum und Uhrzeit so behält, wie du sie eingibst.

#### Neu
- Terminal-Client in der Desktop-App (Linux, macOS): `plasmai-app --tui` zeigt Timer, Zuletzt, Heute als Stundenzeilen mit Lücken und die Woche als Tabelle. 1–9 startet oder wechselt, `s` stoppt. Zum Erfassen aus dem Terminal oder per SSH; er nutzt das Profil der App und hat einen eigenen Offline-Ausgang. Das Widget hat keinen.

#### Verbessert
- Statistik: Die Tätigkeitsverteilung hat einen eigenen Tagesumschalter, so siehst du einen anderen Tag, ohne die übrigen Diagramme zu verschieben. Tag und Woche teilen sich die Breite; ein leerer Tag behält die Höhe des Diagramms.
- Statistik (Kante-Stile): Fährst du über einen Block in „Projekte nach Stunde“, zeigt er Projekt, Zeitraum und Dauer; auf Touch reicht ein Tippen.

#### Behoben
- Beim Bearbeiten konnte der Start eines Eintrags 100 Jahre zurückspringen. In einem kurzen Datumsformat mit zweistelliger Jahreszahl („13.10.26“, „10/13/26“) las das Datumsfeld seinen eigenen Text als 1926. Ein laufender Eintrag begann dann 1926, einen beendeten lehnte Kimai als zu lang ab. Zweistellige Jahre bedeuten jetzt dieses Jahrhundert.
- Zeitwähler der App in 12-Stunden-Sprachen (US-Englisch und andere): Er zeigte ein 24-Stunden-Rad ohne AM/PM und legte 12:xx auf den Vormittag. Jetzt zeigt er 1–12 mit AM/PM. In jeder Sprache gab „Auswählen“ ohne Drehen die aktuelle Uhrzeit zurück statt der, mit der er geöffnet wurde.
- 12-Stunden-Zeitfelder: Eine getippte Stunde verschiebt eine PM-Zeit nicht mehr auf den Vormittag (3 auf 2:30 PM bleibt 3:30 PM).
- Statistik (Kante-Stile): Die Read-outs der Diagramme schrieben Projektnamen in der Projektfarbe, die manche Farben unlesbar machten. Jetzt stehen sie in der Textfarbe mit einem farbigen Quadrat davor.

## [2.5.3] — 2026-10-07

### English

A smoother tray popup on Windows.

#### Improved
- Windows: the tray popup fades in while sliding out of the taskbar, and back out as it closes. It follows the Windows setting for animation effects.

All changes: https://github.com/shrippen/Plasmai/compare/v2.5.2...v2.5.3

### Deutsch

Ein weicheres Tray-Fenster unter Windows.

#### Verbessert
- Windows: Das Tray-Fenster blendet sich ein, während es aus der Taskleiste gleitet, und beim Schließen wieder aus. Es folgt der Windows-Einstellung für Animationseffekte.

## [2.5.2] — 2026-10-06

### English

The Windows app keeps its settings again.

#### Fixed
- Windows: the app did not save its settings. Windows refused to replace the settings file, so the setup wizard stored the token but not the server address, and the app showed a connection problem. Settings are now written directly when the file cannot be replaced.

All changes: https://github.com/shrippen/Plasmai/compare/v2.5.1...v2.5.2

### Deutsch

Die Windows-App behält ihre Einstellungen wieder.

#### Behoben
- Windows: Die App speicherte ihre Einstellungen nicht. Windows verweigerte das Ersetzen der Einstellungsdatei, deshalb speicherte der Einrichtungsassistent das Token, aber nicht die Serveradresse, und die App meldete ein Verbindungsproblem. Lässt sich die Datei nicht ersetzen, werden die Einstellungen jetzt direkt geschrieben.

## [2.5.1] — 2026-10-06

### English

The app starts again.

#### Fixed
- App (Android, Windows, Linux): 2.5.0 did not start; a file of the new Look step was missing from the app. The Plasma widget was not affected.

All changes: https://github.com/shrippen/Plasmai/compare/v2.5.0...v2.5.1

### Deutsch

Die App startet wieder.

#### Behoben
- App (Android, Windows, Linux): 2.5.0 startete nicht; eine Datei des neuen Schritts „Aussehen“ fehlte in der App. Das Plasma-Widget war nicht betroffen.

## [2.5.0] — 2026-10-06

### English

Choose the look of Plasmai while setting it up.

#### New
- Setup wizard: a new "Look" step after the system check lets you choose System, Kante or Kante Light. The wizard changes with your choice, with a preview and the colours of the look; the choice is saved and can be changed later in the settings.

#### Note
- Do not use: the app (Android, Windows, Linux) does not start in this version. Use 2.5.1. The Plasma widget works.

All changes: https://github.com/shrippen/Plasmai/compare/v2.4.0...v2.5.0

### Deutsch

Das Aussehen von Plasmai schon bei der Einrichtung wählen.

#### Neu
- Einrichtungsassistent: Ein neuer Schritt „Aussehen“ nach der Systemprüfung lässt zwischen System, Kante und Kante Light wählen. Der Assistent wechselt mit der Wahl, mit Vorschau und den Farben des Aussehens; die Wahl wird gespeichert und lässt sich später in den Einstellungen ändern.

#### Hinweis
- Nicht verwenden: Die App (Android, Windows, Linux) startet in dieser Version nicht. Nimm 2.5.1. Das Plasma-Widget funktioniert.

## [2.4.0] — 2026-10-06

### English

A setup wizard for the first start, and a Windows popup that fits scaled screens. Updating resets the old configuration once.

#### New
- First start: a setup wizard in the widget and the app instead of the "Configure" hint. It checks the system (widget: secret-tool and KWallet, with the install command for your distribution), lets you pick the service (Clockify, Toggl Track and SolidTime marked experimental), tests address and token before storing the token, and asks for work hours, the place for the sun arcs and the start reminder (all optional).
- Windows: the popup can be resized by dragging its border; the size is kept for the next start.

#### Improved
- Server addresses are cleaned when set up: https is added, a Kimai page or API address is cut back to the instance, plain http outside the machine is warned about; a pasted token loses blanks and "Bearer ".

#### Fixed
- Windows: with display scaling (e.g. 250 % on a full HD screen) the popup was taller than the screen and its lower part, with the buttons, was cut off. It now fits the screen.
- App (Android, Windows, macOS): small text (hints, durations, secondary lines) was larger than the normal text; it is now smaller, as in the widget.

#### Note
- The old configuration is deleted. On the first start after updating from 2.3.x or older, Plasmai (widget and app) resets every setting to its default and removes the stored API tokens of all profiles, then the setup wizard starts. Profiles, favourites, display and behaviour settings, work hours and place have to be set up again. Sync offline changes before updating: unsynced entries of an old profile are only sent again if the new profile has the same id.

All changes: https://github.com/shrippen/Plasmai/compare/v2.3.1...v2.4.0

### Deutsch

Ein Einrichtungsassistent für den ersten Start und ein Windows-Fenster, das auf skalierte Bildschirme passt. Das Update setzt die alte Konfiguration einmal zurück.

#### Neu
- Erster Start: ein Einrichtungsassistent in Widget und App statt des Hinweises „Einrichten“. Er prüft das System (Widget: secret-tool und KWallet, mit dem Installationsbefehl für deine Distribution), lässt den Dienst wählen (Clockify, Toggl Track und SolidTime als experimentell markiert), testet Adresse und Token, bevor er das Token speichert, und fragt Arbeitszeiten, den Ort für die Sonnenbögen und die Start-Erinnerung ab (alles optional).
- Windows: Das Fenster lässt sich am Rand größer und kleiner ziehen; die Größe bleibt für den nächsten Start.

#### Verbessert
- Serveradressen werden beim Einrichten bereinigt: https wird ergänzt, eine Kimai-Seiten- oder API-Adresse auf die Instanz gekürzt, vor unverschlüsseltem http außerhalb des Rechners wird gewarnt; ein eingefügtes Token verliert Leerzeichen und „Bearer “.

#### Behoben
- Windows: Mit Anzeigeskalierung (z. B. 250 % auf einem Full-HD-Bildschirm) war das Fenster höher als der Bildschirm und sein unterer Teil mit den Knöpfen abgeschnitten. Jetzt passt es auf den Bildschirm.
- App (Android, Windows, macOS): Kleine Schrift (Hinweise, Dauern, Nebenzeilen) war größer als die normale; jetzt ist sie kleiner, wie im Widget.

#### Hinweis
- Die alte Konfiguration wird gelöscht. Beim ersten Start nach einem Update von 2.3.x oder älter setzt Plasmai (Widget und App) jede Einstellung auf ihren Standard zurück und entfernt die gespeicherten API-Tokens aller Profile, danach startet der Einrichtungsassistent. Profile, Favoriten, Anzeige- und Verhaltenseinstellungen, Arbeitszeiten und Ort müssen neu eingerichtet werden. Offline-Änderungen vor dem Update synchronisieren: Nicht gesendete Einträge eines alten Profils gehen nur dann erneut raus, wenn das neue Profil dieselbe ID hat.

## [2.3.1] — 2026-10-05

### English

The running time and its notification stay right after the app was away.

#### Fixed
- App: the running time is right as soon as the app is opened again, no longer stuck at the value from when it was closed until the server answers.
- App (Android, Plasma Mobile): the notification follows an edit of the running entry, e.g. an earlier start time.

All changes: https://github.com/shrippen/Plasmai/compare/v2.3.0...v2.3.1

### Deutsch

Laufzeit und Benachrichtigung stimmen, sobald die App zurück ist.

#### Behoben
- App: Die Laufzeit stimmt, sobald die App wieder geöffnet wird, statt bis zur Antwort des Servers auf dem Wert vom Schließen stehen zu bleiben.
- App (Android, Plasma Mobile): Die Benachrichtigung folgt einer Änderung am laufenden Eintrag, etwa einer früheren Startzeit.

## [2.3.0] — 2026-10-02

### English

Catering on a film day follows the engagement.

#### Improved
- Film day: a day without saved details starts with catering on when the engagement's catering default in the Drehzettel plugin says so.

#### Note
- Needs the updated Drehzettel plugin.

All changes: https://github.com/shrippen/Plasmai/compare/v2.2.0...v2.3.0

### Deutsch

Das Catering am Drehtag folgt dem Engagement.

#### Verbessert
- Drehtag: Ein Tag ohne gespeicherte Angaben beginnt mit Catering, wenn die Catering-Vorgabe des Engagements im Drehzettel-Plugin das sagt.

#### Hinweis
- Braucht das aktualisierte Drehzettel-Plugin.

## [2.2.0] — 2026-10-02

### English

A notification while the timer runs, the film day note on the Kimai entry, and the Kante styles built from Kante's own components.

#### New
- App (Android, Plasma Mobile): a permanent notification while a timer runs, with the project, activity and start time (on Android with the running time). A tap opens the app.

#### Improved
- Film day: the note is the Kimai entry's description, no longer a second field in the Drehzettel plugin. Typed before the entry exists, it goes with Start or Save.
- Kante styles: charts, the day strip, time lines, pick lists, chips, colour swatches, date and time fields and the offline notice now come from Kante's own components, so widget and app look and behave alike.

#### Fixed
- Widget: a right click on a Recent entry opened the widget's menu instead of the entry menu.
- Statistics (Kante styles): the chosen filter segment was beige text on yellow and hard to read; it is now marked by a yellow bar under the label.
- Styles System and Kante Light: text in the system accent colour (headings, the film day date, chips) is lightened until it reads, also with a dark Plasma accent.
- Film day: the note was lost when leaving the page (or closing the popup) right after typing, and on Android the last word held back by the keyboard's predictive text was not saved.

All changes: https://github.com/shrippen/Plasmai/compare/v2.1.0...v2.2.0

### Deutsch

Eine Benachrichtigung, solange der Timer läuft, die Drehtag-Notiz am Kimai-Eintrag und Kante-Stile aus Kantes eigenen Bausteinen.

#### Neu
- App (Android, Plasma Mobile): eine dauerhafte Benachrichtigung, solange ein Timer läuft, mit Projekt, Tätigkeit und Startzeit (unter Android mit der Laufzeit). Ein Tippen öffnet die App.

#### Verbessert
- Drehtag: Die Notiz ist die Beschreibung des Kimai-Eintrags, kein zweites Feld im Drehzettel-Plugin mehr. Vor dem Eintrag getippt, geht sie mit Start oder Speichern mit.
- Kante-Stile: Diagramme, Tagesleiste, Zeitzeilen, Auswahllisten, Chips, Farbfelder, Datums- und Zeitfelder und der Offline-Hinweis kommen jetzt aus Kantes eigenen Bausteinen, so sehen Widget und App gleich aus und verhalten sich gleich.

#### Behoben
- Widget: Ein Rechtsklick auf einen Eintrag unter Zuletzt öffnete das Widget-Menü statt des Eintragsmenüs.
- Statistik (Kante-Stile): Das gewählte Filtersegment war beiger Text auf Gelb und schwer lesbar; jetzt markiert es ein gelber Balken unter der Beschriftung.
- Stile System und Kante Light: Text in der Akzentfarbe des Systems (Überschriften, das Drehtag-Datum, Chips) wird aufgehellt, bis er lesbar ist, auch mit einem dunklen Plasma-Akzent.
- Drehtag: Die Notiz ging verloren, wenn man die Seite direkt nach dem Tippen verließ (oder das Fenster schloss), und unter Android wurde das letzte Wort, das die Wortvorschläge der Tastatur zurückhielten, nicht gespeichert.

## [2.1.0] — 2026-09-30

### English

Plasmai keeps working without a connection, and comes to Windows as a tray app.

#### New
- Offline mode (Kimai): with bad reception the widget and the app keep working from the last known state ("Offline · as of 12:04"). Starting and stopping the timer, adding, editing and deleting entries, film day details and trips are kept on the device and sent in order once the server answers again. A change the server does not accept, or an entry changed elsewhere meanwhile, waits in "Not synced" to retry, overwrite or discard; nothing is dropped silently. Creating customers, projects and activities, splitting and merging entries, discarding idle time and switching profiles need a connection.
- Windows (preview): Plasmai as a tray icon whose popup is the app, like the widget in the Plasma panel. The icon shows a running timer with a red dot, its menu stops the running entry or starts the last used one, and it can start at login. Installer (per user, no administrator rights) and zip. It follows the system's light or dark setting.

#### Improved
- Widget (Kante styles): a running timer no longer tints the whole panel entry in the accent colour. A small red indicator marks it instead; Display settings offer a red dot, a red bottom edge or a red side stripe, with a preview.
- Film day: switching days is instant. The last month is loaded in the background; a day opens from it and is then checked against the server, so what is shown can still change a moment later.
- App: after a lost connection the app refreshes as soon as the network is back, instead of at the next poll.
- App (desktop style): the statistics filter looks like the widget's (three segments side by side); in touch mode the segments get the larger touch height.
- Less work in the background: the widget no longer rewrites its files when nothing changed, reads the shared settings once a minute while collapsed, reloads work hours and absences every 10 minutes instead of every 30 seconds, and hidden views no longer update every second.

#### Fixed
- Times written by the widget and the app carry the device's offset, and Kimai converts them into the profile's time zone. With a Kimai profile in another zone than the device they used to land hours off.
- App (Android): plurals in Russian, Ukrainian and Polish use the right form, Japanese and Chinese no longer show English, French counts 0 as singular.
- App: the dialogs to create a customer, project or activity, to split an entry and after idle time showed only their title and buttons; their fields are back.
- App: text typed into the description is no longer replaced by the server's text when the entry refreshes while typing; the time picker opens at the field's time.
- Favourites pinned in the app show in the widget and the other way round.
- Widget: "continue last" offers the activity you switched to; the film day and trips buttons no longer disappear after stopping the timer; without GPU acceleration the day bar is shown instead of missing.
- App: the activity catalogue is loaded (favourites showed ids until a project was opened).
- Film day: only the activities the Drehzettel engagement counts make up the film day, its begin and end and the shooting day count, as in the plugin. A private commute on the same project no longer becomes the film day.

#### Note
- App: API tokens are now always kept in the platform's secure storage (Secret Service / KWallet, Android Keystore, Windows Credential Manager, macOS Keychain). Up to 2.0.1 the app stored them in plain files on Linux (AppImage, Flatpak) and on Android. Such a file moves into the secure storage on the next start and is deleted; without secure storage the token is not saved.
- Windows: the installer is not signed yet, so Windows warns on the first start.

All changes: https://github.com/shrippen/Plasmai/compare/v2.0.1...v2.1.0

### Deutsch

Plasmai arbeitet ohne Verbindung weiter und kommt als Tray-App auf Windows.

#### Neu
- Offline-Modus (Kimai): Bei schlechtem Empfang arbeiten Widget und App mit dem letzten bekannten Stand weiter („Offline · Stand 12:04“). Timer starten und stoppen, Einträge anlegen, bearbeiten und löschen, Drehtag-Angaben und Fahrten bleiben auf dem Gerät und gehen der Reihe nach raus, sobald der Server wieder antwortet. Eine Änderung, die der Server ablehnt, oder ein inzwischen anderswo geänderter Eintrag wartet unter „Nicht synchronisiert“ auf Wiederholen, Überschreiben oder Verwerfen; nichts geht still verloren. Kunden, Projekte und Tätigkeiten anlegen, Einträge teilen und zusammenführen, Leerlauf verwerfen und Profile wechseln braucht eine Verbindung.
- Windows (Vorschau): Plasmai als Tray-Symbol, dessen Fenster die App ist, wie das Widget im Plasma-Panel. Das Symbol zeigt einen laufenden Timer mit rotem Punkt, sein Menü stoppt den laufenden Eintrag oder startet den zuletzt genutzten, und es kann bei der Anmeldung starten. Installer (je Benutzer, ohne Administratorrechte) und Zip. Es folgt der hellen oder dunklen Einstellung des Systems.

#### Verbessert
- Widget (Kante-Stile): Ein laufender Timer färbt nicht mehr den ganzen Panel-Eintrag in der Akzentfarbe. Eine kleine rote Markierung zeigt ihn stattdessen; die Anzeige-Einstellungen bieten einen roten Punkt, eine rote Unterkante oder einen roten Seitenstreifen, mit Vorschau.
- Drehtag: Der Tageswechsel geht sofort. Der letzte Monat lädt im Hintergrund; ein Tag öffnet daraus und wird dann mit dem Server abgeglichen, das Gezeigte kann sich also einen Moment später noch ändern.
- App: Nach einem Verbindungsabbruch lädt die App neu, sobald das Netz zurück ist, statt erst bei der nächsten Abfrage.
- App (Desktop-Stil): Der Statistikfilter sieht aus wie im Widget (drei Segmente nebeneinander); im Touch-Modus bekommen die Segmente die größere Touch-Höhe.
- Weniger Arbeit im Hintergrund: Das Widget schreibt seine Dateien nicht mehr ohne Änderung neu, liest die gemeinsamen Einstellungen eingeklappt einmal pro Minute, lädt Arbeitszeiten und Abwesenheiten alle 10 Minuten statt alle 30 Sekunden, und verborgene Ansichten aktualisieren sich nicht mehr jede Sekunde.

#### Behoben
- Zeiten, die Widget und App schreiben, tragen den Versatz des Geräts, und Kimai rechnet sie in die Zeitzone des Profils um. Bei einem Kimai-Profil in einer anderen Zone als das Gerät landeten sie Stunden daneben.
- App (Android): Mehrzahlformen auf Russisch, Ukrainisch und Polnisch stimmen, Japanisch und Chinesisch zeigen kein Englisch mehr, Französisch zählt 0 als Einzahl.
- App: Die Dialoge zum Anlegen von Kunde, Projekt oder Tätigkeit, zum Teilen eines Eintrags und nach Leerlauf zeigten nur Titel und Knöpfe; ihre Felder sind zurück.
- App: Text in der Beschreibung wird nicht mehr vom Text des Servers ersetzt, wenn der Eintrag beim Tippen neu lädt; der Zeitwähler öffnet bei der Zeit des Felds.
- In der App angeheftete Favoriten erscheinen im Widget und umgekehrt.
- Widget: „Letzte fortsetzen“ bietet die Tätigkeit an, zu der gewechselt wurde; die Knöpfe für Drehtag und Fahrten verschwinden nach dem Stoppen nicht mehr; ohne GPU-Beschleunigung erscheint die Tagesleiste, statt zu fehlen.
- App: Der Tätigkeitskatalog wird geladen (Favoriten zeigten IDs, bis ein Projekt geöffnet wurde).
- Drehtag: Nur die Tätigkeiten, die das Drehzettel-Engagement zählt, bilden den Drehtag, seinen Beginn und sein Ende und die Zählung der Drehtage, wie im Plugin. Eine private Fahrt auf demselben Projekt wird nicht mehr zum Drehtag.

#### Hinweis
- App: API-Tokens liegen jetzt immer im sicheren Speicher der Plattform (Secret Service / KWallet, Android Keystore, Windows-Anmeldeinformationsverwaltung, macOS-Schlüsselbund). Bis 2.0.1 legte die App sie unter Linux (AppImage, Flatpak) und Android in einfachen Dateien ab. Eine solche Datei wandert beim nächsten Start in den sicheren Speicher und wird gelöscht; ohne sicheren Speicher wird das Token nicht gespeichert.
- Windows: Der Installer ist noch nicht signiert, Windows warnt deshalb beim ersten Start.

## [2.0.1] — 2026-09-28

### English

An About page, a reproducible Android build and fixes for the Android app.

#### New
- App: an About page in the menu, with the version and links to the source code and to shrippen.github.io.

#### Improved
- App (Android, AppImage): Qt 6.11 and KF6 6.30; Android bundles OpenSSL 3.5 (LTS), built from source.
- The film day is hidden when the Kimai instance has no Drehzettel plugin (or you lack its view permission), like trips without the Anfahrten plugin.
- App (Android): the release APK is built reproducibly, so F-Droid can publish it with the original signature.
- Every release carries the AppImage, the Flatpak bundle and the widget next to the APK.

#### Fixed
- App (Android): Back on the first page sends the app to the background again, and closes an open menu first.
- App (Android): opening a drop-down no longer triggers "Plasmai pasted from your clipboard".
- App: the menu button has a name for screen readers (12 languages).

All changes: https://github.com/shrippen/Plasmai/compare/v2.0.0...v2.0.1

### Deutsch

Eine Über-Seite, ein reproduzierbarer Android-Build und Korrekturen für die Android-App.

#### Neu
- App: eine Über-Seite im Menü, mit der Version und Links zum Quellcode und zu shrippen.github.io.

#### Verbessert
- App (Android, AppImage): Qt 6.11 und KF6 6.30; Android bringt OpenSSL 3.5 (LTS) mit, aus dem Quellcode gebaut.
- Der Drehtag ist ausgeblendet, wenn die Kimai-Instanz kein Drehzettel-Plugin hat (oder dir die Ansichtsberechtigung fehlt), wie Fahrten ohne das Anfahrten-Plugin.
- App (Android): Das Release-APK wird reproduzierbar gebaut, so kann F-Droid es mit der ursprünglichen Signatur veröffentlichen.
- Jedes Release enthält neben dem APK das AppImage, das Flatpak-Paket und das Widget.

#### Behoben
- App (Android): Zurück auf der ersten Seite schickt die App wieder in den Hintergrund und schließt vorher ein offenes Menü.
- App (Android): Das Öffnen einer Auswahlliste löst nicht mehr „Plasmai hat aus der Zwischenablage eingefügt“ aus.
- App: Der Menüknopf hat einen Namen für Screenreader (12 Sprachen).

## [2.0.0] — 2026-09-27

### English

Plasmai becomes an app for Android and Plasma Mobile too, and learns film days and trips from the Kimai plugins Drehzettel and Anfahrten. Kimai is the reference backend; Clockify, Toggl Track and SolidTime stay experimental.

#### New
- App for Android and Plasma Mobile (Kirigami): timer, continue, switch, editing the running entry, adding entries, favourites, recent entries (edit, split, delete), statistics and settings, in 11 languages.
- Film day (Kimai with the Drehzettel plugin): start the shooting day with one button, see break, work time and pay so far, record catering, day category, surcharge day, extra pay and note; engagement and shooting day number come from Kimai.
- Trips (Kimai with the Anfahrten plugin): log, edit and delete trips linked to an entry, check start and destination on a map, accept Dawarich suggestions; trip km in the statistics.
- Kante style (optional, widget and app): Plasmai's own look; Kante Light keeps your theme's colours.
- The generic start sits right next to Continue (▶) and is never scrolled away; recent entries are grouped by day; an entry's menu opens with a long press.

#### Improved
- The "Connected to …" line only shows with several profiles or when something is wrong.
- Lists sort Aa→Zz; chart axes end on round values; full hours read "14h".
- A new icon.

#### Fixed
- Kimai: works for regular users again (`exported` is no longer sent, `billable` only when changed; without the edit_billable permission the entry is saved without it and a hint is shown).
- Kimai: Start uses Kimai's time, Continue keeps description and tags, totals no longer fail at exactly 100, 200 … entries, hidden customers, projects and activities are no longer offered, and the lists load in one request.
- Requests give up after 30 s instead of keeping the widget busy.
- Discarding idle time stops the entry where idle began; idle detection also asks the screen saver.
- Absences given in seconds are no longer read as hours; the day sparkline is right on DST days.
- The API token no longer appears on a command line while it is stored; large caches are saved in chunks and config files are written safely.

#### Note
- Colour distinction and its Maintenance tab are gone: Plasmai shows the Kimai colours as they are (a separate Kimai plugin handles similar colours).

All changes: https://github.com/shrippen/Plasmai/compare/1.6.3...v2.0.0

### Deutsch

Plasmai wird auch eine App für Android und Plasma Mobile und lernt Drehtage und Fahrten von den Kimai-Plugins Drehzettel und Anfahrten. Kimai ist das Referenz-Backend; Clockify, Toggl Track und SolidTime bleiben experimentell.

#### Neu
- App für Android und Plasma Mobile (Kirigami): Timer, Fortsetzen, Wechseln, den laufenden Eintrag bearbeiten, Einträge anlegen, Favoriten, letzte Einträge (bearbeiten, teilen, löschen), Statistik und Einstellungen, in 11 Sprachen.
- Drehtag (Kimai mit dem Drehzettel-Plugin): den Drehtag mit einem Knopf beginnen, Pause, Arbeitszeit und bisherige Gage sehen, Catering, Tageskategorie, Zuschlagstag, Zusatzgage und Notiz erfassen; Engagement und Drehtagnummer kommen aus Kimai.
- Fahrten (Kimai mit dem Anfahrten-Plugin): Fahrten zu einem Eintrag erfassen, bearbeiten und löschen, Start und Ziel auf einer Karte prüfen, Vorschläge aus Dawarich übernehmen; Fahrt-km in der Statistik.
- Kante-Stil (optional, Widget und App): das eigene Aussehen von Plasmai; Kante Light behält die Farben deines Designs.
- Der allgemeine Start sitzt direkt neben Fortsetzen (▶) und scrollt nie weg; letzte Einträge sind nach Tagen gruppiert; das Menü eines Eintrags öffnet mit langem Druck.

#### Verbessert
- Die Zeile „Verbunden mit …“ erscheint nur bei mehreren Profilen oder wenn etwas nicht stimmt.
- Listen sortieren Aa→Zz; Diagrammachsen enden auf runden Werten; volle Stunden lauten „14h“.
- Ein neues Symbol.

#### Behoben
- Kimai: funktioniert wieder für normale Benutzer (`exported` wird nicht mehr gesendet, `billable` nur bei Änderung; ohne die Berechtigung edit_billable wird der Eintrag ohne gespeichert und ein Hinweis erscheint).
- Kimai: Start nutzt die Zeit von Kimai, Fortsetzen behält Beschreibung und Tags, Summen scheitern nicht mehr bei genau 100, 200 … Einträgen, verborgene Kunden, Projekte und Tätigkeiten werden nicht mehr angeboten, und die Listen laden in einer Anfrage.
- Anfragen geben nach 30 s auf, statt das Widget zu blockieren.
- Leerlauf verwerfen stoppt den Eintrag dort, wo der Leerlauf begann; die Leerlauferkennung fragt auch den Bildschirmschoner.
- In Sekunden angegebene Abwesenheiten werden nicht mehr als Stunden gelesen; die Tageskurve stimmt an Tagen mit Zeitumstellung.
- Das API-Token erscheint beim Speichern nicht mehr auf einer Kommandozeile; große Zwischenspeicher werden in Teilen gesichert und Konfigurationsdateien sicher geschrieben.

#### Hinweis
- Die Farbunterscheidung und ihr Reiter Wartung sind entfallen: Plasmai zeigt die Kimai-Farben, wie sie sind (ähnliche Farben behandelt ein eigenes Kimai-Plugin).

## [1.6.3] — 2026-08-19

### English

A new icon, billable left to Kimai, and a check before a start lands in the previous entry.

#### New
- Behaviour option (on by default): asks before saving a running entry's start that falls inside the previous entry; the editor shows that previous end time.

#### Improved
- A new shatter-clock icon that follows Breeze and other icon themes.
- Billable defaults to automatic: Kimai decides it from the activity, project and customer instead of Plasmai forcing it on.
- The location search in the display settings waits briefly after typing instead of asking Nominatim on every key.

All changes: https://github.com/shrippen/Plasmai/compare/v1.6.2...1.6.3

### Deutsch

Ein neues Symbol, abrechenbar entscheidet Kimai, und eine Rückfrage, bevor ein Start im vorigen Eintrag landet.

#### Neu
- Verhaltensoption (standardmäßig an): fragt nach, bevor ein Start des laufenden Eintrags gespeichert wird, der in den vorigen Eintrag fällt; der Editor zeigt dessen Ende.

#### Verbessert
- Ein neues Symbol (zersprungene Uhr), das Breeze und anderen Symbolthemen folgt.
- Abrechenbar steht standardmäßig auf automatisch: Kimai entscheidet nach Tätigkeit, Projekt und Kunde, statt dass Plasmai es einschaltet.
- Die Ortssuche in den Anzeige-Einstellungen wartet nach dem Tippen kurz, statt Nominatim bei jeder Taste zu fragen.

## [1.6.2] — 2026-08-18

### English

Favourites switch like recent entries.

#### Improved
- A click on a favourite while tracking uses the same switch dialog and "already running" hint as recent entries; the same activity is not stopped.

All changes: https://github.com/shrippen/Plasmai/compare/v1.6.1...v1.6.2

### Deutsch

Favoriten wechseln wie letzte Einträge.

#### Verbessert
- Ein Klick auf einen Favoriten während der Erfassung nutzt denselben Wechseldialog und Hinweis „läuft bereits“ wie die letzten Einträge; dieselbe Tätigkeit wird nicht gestoppt.

## [1.6.1] — 2026-08-18

### English

Shutdown is no longer held while tracking.

#### Note
- The shutdown and reboot hold from 1.6.0 is removed again: a restart from the launcher ends plasmashell first, so the hold never delayed it.

All changes: https://github.com/shrippen/Plasmai/compare/v1.6.0...v1.6.1

### Deutsch

Das Herunterfahren wird während der Erfassung nicht mehr aufgehalten.

#### Hinweis
- Die Sperre für Herunterfahren und Neustart aus 1.6.0 ist wieder entfernt: Ein Neustart aus dem Starter beendet zuerst plasmashell, die Sperre hielt ihn also nie auf.

## [1.6.0] — 2026-08-18

### English

The remaining week time knows a second absence plugin, and every language is complete.

#### New
- Week remaining detects kimai-holiday-bundle or the official WorkContractBundle (checked again hourly) and subtracts approved absences and public holidays for either; WorkContract's automatic bookings are not counted twice.
- Opening the widget while a timer runs sends one "Tracking in progress" notification.
- While tracking, shutdown and reboot wait like for an unsaved file (closing the lid and sleep are not blocked).

#### Improved
- All 12 bundled languages cover the current interface; the KDE Store description is translated into each of them.

All changes: https://github.com/shrippen/Plasmai/compare/v1.5.0...v1.6.0

### Deutsch

Die Restzeit der Woche kennt ein zweites Abwesenheits-Plugin, und jede Sprache ist vollständig.

#### Neu
- Die Wochen-Restzeit erkennt kimai-holiday-bundle oder das offizielle WorkContractBundle (stündlich neu geprüft) und zieht genehmigte Abwesenheiten und Feiertage beider ab; automatische Buchungen von WorkContract zählen nicht doppelt.
- Das Öffnen des Widgets bei laufendem Timer sendet eine Benachrichtigung „Erfassung läuft“.
- Während der Erfassung warten Herunterfahren und Neustart wie bei einer ungespeicherten Datei (Deckel schließen und Ruhezustand werden nicht blockiert).

#### Verbessert
- Alle 12 mitgelieferten Sprachen decken die aktuelle Oberfläche ab; die Beschreibung im KDE Store ist in jede davon übersetzt.

## [1.5.0] — 2026-08-18

### English

Tags, billable, editing past entries and creating customers, projects and activities from the widget.

#### New
- Tags on Add entry and Edit running (Kimai: searchable picker with colour pills and create-new; Toggl when the API allows names).
- Billable on Add entry and Edit running.
- Edit, delete and split stopped recent entries from their menu; editing one fills in project and activity.
- Create a customer, project or activity from the picker's menu.
- Week remaining subtracts approved absences and public holidays (kimai-holiday-bundle).
- Idle dialog: keep the time, discard the idle time, or discard and continue; on Wayland idle detection asks the session first.
- Optional reminder when you forgot to start during work hours (once a day).

#### Improved
- Profiles: Apply saves an added or edited profile; duplicate names are refused; Clear token is off when none is stored.
- Favourites show a loading indicator and stay responsive.
- The profile switcher stays on the main and statistics views, not on the add and edit screens.
- The desktop widget uses the theme's standard background, so the blur matches other widgets.

#### Fixed
- Switching settings tabs reset Connection to the default profile.

All changes: https://github.com/shrippen/Plasmai/compare/v1.4.2...v1.5.0

### Deutsch

Tags, abrechenbar, vergangene Einträge bearbeiten und Kunden, Projekte und Tätigkeiten aus dem Widget anlegen.

#### Neu
- Tags bei Eintrag hinzufügen und Laufenden bearbeiten (Kimai: durchsuchbare Auswahl mit farbigen Pillen und Neu anlegen; Toggl, wenn die API Namen erlaubt).
- Abrechenbar bei Eintrag hinzufügen und Laufenden bearbeiten.
- Beendete letzte Einträge aus ihrem Menü bearbeiten, löschen und teilen; beim Bearbeiten sind Projekt und Tätigkeit vorausgefüllt.
- Kunde, Projekt oder Tätigkeit aus dem Menü der Auswahl anlegen.
- Die Wochen-Restzeit zieht genehmigte Abwesenheiten und Feiertage ab (kimai-holiday-bundle).
- Leerlaufdialog: Zeit behalten, Leerlauf verwerfen oder verwerfen und weitermachen; unter Wayland fragt die Erkennung zuerst die Sitzung.
- Optionale Erinnerung, wenn während der Arbeitszeit kein Timer gestartet wurde (einmal am Tag).

#### Verbessert
- Profile: Anwenden speichert ein neues oder geändertes Profil; doppelte Namen werden abgelehnt; Token löschen ist aus, wenn keins gespeichert ist.
- Favoriten zeigen eine Ladeanzeige und bleiben bedienbar.
- Der Profilwechsler bleibt auf Haupt- und Statistikansicht, nicht auf den Seiten zum Anlegen und Bearbeiten.
- Das Desktop-Widget nutzt den Standardhintergrund des Designs, so passt die Unschärfe zu anderen Widgets.

#### Behoben
- Ein Wechsel der Einstellungsreiter setzte Verbindung auf das Standardprofil zurück.

## [1.4.2] — 2026-08-17

### English

Display settings apply again, and customer and project colours can show on the panel.

#### New
- Optional customer and project colour pills on the panel chip (off by default).

#### Improved
- A stronger, longer checkmark after saving the description; the panel chip has a name for screen readers.

#### Fixed
- Ticking Display options (panel labels, flyout, desktop widget) enables Apply and OK again.

All changes: https://github.com/shrippen/Plasmai/compare/v1.4.1...v1.4.2

### Deutsch

Anzeige-Einstellungen lassen sich wieder anwenden, und Kunden- und Projektfarben können im Panel erscheinen.

#### Neu
- Optionale farbige Pillen für Kunde und Projekt im Panel (standardmäßig aus).

#### Verbessert
- Ein deutlicheres, längeres Häkchen nach dem Speichern der Beschreibung; der Panel-Eintrag hat einen Namen für Screenreader.

#### Behoben
- Das Ankreuzen von Anzeigeoptionen (Panel-Beschriftung, Ausklappfenster, Desktop-Widget) schaltet Anwenden und OK wieder frei.

## [1.4.1] — 2026-08-13

### English

Less redrawing and settings pages that fit.

#### Improved
- The day sparkline no longer redraws for the sun's rotation; the now marker moves every 30 s instead of every second, and the loading pulse runs only while visible.
- Display, Connection, Behaviour and Maintenance settings wrap instead of clipping; Maintenance and Favourites show their lists at once from the shared cache.
- Reloading the catalogue no longer reshuffles the distinction colours; Favourites' Reload sits beside the project header.

#### Fixed
- Plasma no longer floods the journal with warnings from Plasmai's settings pages.

All changes: https://github.com/shrippen/Plasmai/compare/v1.4.0...v1.4.1

### Deutsch

Weniger Neuzeichnen und Einstellungsseiten, die passen.

#### Verbessert
- Die Tageskurve zeichnet sich für die Drehung der Sonne nicht mehr neu; die Jetzt-Markierung rückt alle 30 s statt jede Sekunde vor, und das Pulsieren beim Laden läuft nur, solange es sichtbar ist.
- Die Einstellungen Anzeige, Verbindung, Verhalten und Wartung brechen um, statt abzuschneiden; Wartung und Favoriten zeigen ihre Listen sofort aus dem gemeinsamen Zwischenspeicher.
- Neu laden des Katalogs mischt die Unterscheidungsfarben nicht mehr neu; Neu laden bei den Favoriten sitzt neben der Projektüberschrift.

#### Behoben
- Plasma füllt das Journal nicht mehr mit Warnungen aus den Einstellungsseiten von Plasmai.

## [1.4.0] — 2026-08-12

### English

Plasmai for touch screens.

#### New
- Display setting for touch mode: automatic (Plasma tablet mode), on or off. Touch mode gives larger tap targets for buttons, rows, favourites, pickers and date and time controls, a bigger panel icon and flyout, and chart tooltips on tap.

#### Improved
- A compact header: title and connection status in one block, action icons centred.
- The flyout uses the full width when no scroll bar is needed; the project and activity list scrolls when it is taller than the space; the statistics billable filter fills the width.

All changes: https://github.com/shrippen/Plasmai/compare/v1.3.1...v1.4.0

### Deutsch

Plasmai für Touchscreens.

#### Neu
- Anzeige-Einstellung für den Touch-Modus: automatisch (Plasma-Tablet-Modus), an oder aus. Der Touch-Modus bringt größere Tippflächen für Knöpfe, Zeilen, Favoriten, Auswahllisten und Datums- und Zeitfelder, ein größeres Panel-Symbol und Ausklappfenster und Diagramm-Tooltips per Tippen.

#### Verbessert
- Ein kompakter Kopf: Titel und Verbindungsstatus in einem Block, Aktionssymbole zentriert.
- Das Ausklappfenster nutzt die volle Breite, wenn keine Bildlaufleiste nötig ist; die Liste der Projekte und Tätigkeiten scrollt, wenn sie höher als der Platz ist; der Abrechenbar-Filter der Statistik füllt die Breite.

## [1.3.1] — 2026-08-12

### English

Week navigation in the statistics and one picker everywhere.

#### New
- Week navigation for the statistics charts.
- Tapping a recent entry that is already running shows a short "already running" hint with the elapsed time.

#### Improved
- The main view, manual entry and the running entry's editor share one project and activity picker; it opens upwards only when the space below is tight and closes when the view scrolls.

All changes: https://github.com/shrippen/Plasmai/compare/v1.3.0...v1.3.1

### Deutsch

Wochennavigation in der Statistik und überall dieselbe Auswahl.

#### Neu
- Wochennavigation für die Statistikdiagramme.
- Ein Tippen auf einen letzten Eintrag, der schon läuft, zeigt kurz „läuft bereits“ mit der verstrichenen Zeit.

#### Verbessert
- Hauptansicht, manueller Eintrag und der Editor des laufenden Eintrags teilen sich eine Auswahl für Projekt und Tätigkeit; sie öffnet nur nach oben, wenn unten zu wenig Platz ist, und schließt, wenn die Ansicht scrollt.

## [1.3.0] — 2026-08-11

### English

Switch to a recent entry while a timer runs.

#### New
- Clicking a recent entry while a timer runs asks first, then stops the current activity and starts the chosen one in one step. The dialog shows current → target with the customer, project and activity colours.

All changes: https://github.com/shrippen/Plasmai/compare/v1.2.2...v1.3.0

### Deutsch

Zu einem letzten Eintrag wechseln, während ein Timer läuft.

#### Neu
- Ein Klick auf einen letzten Eintrag bei laufendem Timer fragt erst nach, stoppt dann die aktuelle Tätigkeit und startet die gewählte in einem Schritt. Der Dialog zeigt aktuell → Ziel mit den Farben von Kunde, Projekt und Tätigkeit.

## [1.2.2] — 2026-08-11

### English

A calmer day sparkline.

#### Improved
- The sun sits exactly on its arc and turns smoothly (once every three minutes, at 25 frames a second); the moon icon is gone to avoid clutter.

All changes: https://github.com/shrippen/Plasmai/compare/v1.2.1...v1.2.2

### Deutsch

Eine ruhigere Tageskurve.

#### Verbessert
- Die Sonne sitzt genau auf ihrem Bogen und dreht sich gleichmäßig (einmal in drei Minuten, mit 25 Bildern pro Sekunde); das Mondsymbol ist weg, damit es nicht überladen wirkt.

## [1.2.1] — 2026-08-10

### English

Display settings that fit narrow windows.

#### Improved
- The usual work hours fields are compact, and the display settings (labels, checkboxes, location search) wrap in narrow settings windows instead of being cut off.

All changes: https://github.com/shrippen/Plasmai/compare/v1.2.0...v1.2.1

### Deutsch

Anzeige-Einstellungen, die in schmale Fenster passen.

#### Verbessert
- Die Felder für die üblichen Arbeitszeiten sind kompakt, und die Anzeige-Einstellungen (Beschriftungen, Kontrollkästchen, Ortssuche) brechen in schmalen Einstellungsfenstern um, statt abgeschnitten zu werden.

## [1.2.0] — 2026-08-10

### English

Edit the running entry.

#### New
- An edit button beside Stop opens an editor for the running entry: change its start time, project and activity with the same pickers as for a new activity. On narrow layouts Edit and Stop move below the work summary.

All changes: https://github.com/shrippen/Plasmai/compare/v1.1.0...v1.2.0

### Deutsch

Den laufenden Eintrag bearbeiten.

#### Neu
- Ein Bearbeiten-Knopf neben Stopp öffnet einen Editor für den laufenden Eintrag: Startzeit, Projekt und Tätigkeit ändern, mit derselben Auswahl wie für eine neue Tätigkeit. In schmalen Layouts rücken Bearbeiten und Stopp unter die Arbeitsübersicht.

## [1.1.0] — 2026-08-09

### English

More services than Kimai, manual entries, statistics and ten more languages.

#### New
- Clockify, Toggl Track and SolidTime next to Kimai, chosen per profile.
- Manual entries: + in the main view opens a compact editor with project and activity pickers and begin and end.
- A statistics screen (today and week totals, projects, charts) next to the timer.
- The day sparkline zooms to your working hours and shows sun, moon and work arcs (can be turned off).
- Optional colour distinction for similar customer, project or activity colours, with a Maintenance page listing them.
- French, Spanish, Italian, Dutch, Portuguese (Brazil), Polish, Ukrainian, Russian, Japanese and Chinese (Simplified) next to English and German.

All changes: https://github.com/shrippen/Plasmai/compare/v1.0.0...v1.1.0

### Deutsch

Mehr Dienste als Kimai, manuelle Einträge, Statistik und zehn weitere Sprachen.

#### Neu
- Clockify, Toggl Track und SolidTime neben Kimai, je Profil wählbar.
- Manuelle Einträge: + in der Hauptansicht öffnet einen kompakten Editor mit Auswahl für Projekt und Tätigkeit und Beginn und Ende.
- Eine Statistikseite (Summen für heute und die Woche, Projekte, Diagramme) neben dem Timer.
- Die Tageskurve zoomt auf deine Arbeitszeit und zeigt Sonnen-, Mond- und Arbeitsbögen (abschaltbar).
- Optionale Farbunterscheidung für ähnliche Kunden-, Projekt- oder Tätigkeitsfarben, mit einer Seite Wartung, die sie auflistet.
- Französisch, Spanisch, Italienisch, Niederländisch, Portugiesisch (Brasilien), Polnisch, Ukrainisch, Russisch, Japanisch und Chinesisch (vereinfacht) neben Englisch und Deutsch.

## [1.0.0] — 2026-08-09

### English

The first stable release of Plasmai, a Kimai time tracker in the Plasma panel.

#### New
- Start, stop and switch activities from the panel popup or the desktop widget, with a live timer, the running entry's description, Continue last, recent entries and pinned favourites.
- Today and week totals and the time remaining against the Kimai work contract.
- A 24-hour day sparkline with usual work hours, overtime and sunrise and sunset, for a searched place or your own coordinates.
- Several Kimai profiles, API tokens in KWallet, settings shared by all widgets.
- Searchable project and activity pickers grouped by customer, with keyboard navigation.
- Notifications on start, stop and idle stop; automatic stop when idle (X11/XWayland).
- English and German.

### Deutsch

Die erste stabile Version von Plasmai, einer Kimai-Zeiterfassung im Plasma-Panel.

#### Neu
- Tätigkeiten aus dem Panel oder dem Desktop-Widget starten, stoppen und wechseln, mit laufendem Timer, der Beschreibung des laufenden Eintrags, Letzte fortsetzen, letzten Einträgen und angehefteten Favoriten.
- Summen für heute und die Woche und die Restzeit gegenüber dem Kimai-Arbeitsvertrag.
- Eine 24-Stunden-Tageskurve mit üblicher Arbeitszeit, Überstunden und Sonnenauf- und -untergang, für einen gesuchten Ort oder eigene Koordinaten.
- Mehrere Kimai-Profile, API-Tokens in KWallet, Einstellungen für alle Widgets gemeinsam.
- Durchsuchbare Auswahl für Projekte und Tätigkeiten, nach Kunden gruppiert, mit Tastatursteuerung.
- Benachrichtigungen bei Start, Stopp und Stopp nach Leerlauf; automatischer Stopp bei Leerlauf (X11/XWayland).
- Englisch und Deutsch.
