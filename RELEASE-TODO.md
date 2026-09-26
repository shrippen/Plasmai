# TODO: Release 2.0.0 veröffentlichen

Für dich vorbereitet, damit diese Aufgabe unbeaufsichtigt laufen kann. Heißt bewusst nicht
`todo.md` — die Datei gibt es schon und trackt den UI-Feinschliff von Android/Plasma Mobile
gegen das Plasmoid. Technische Details und Begründungen zu jedem Punkt hier stehen in
`RELEASING.md`.

## Stand (schon erledigt, lokal, nichts veröffentlicht)
- Stand 2026-09-27: noch kein Punkt unten erledigt, kein `v2.0.0`-Tag (letzter Tag `v1.6.2`). Seit dem ersten Stand sind Kante-Stil, Drehtag-Neugestaltung und Anfahrten dazugekommen; die Builds unten (APK, Tarball) sind deshalb veraltet und vor dem Release neu zu bauen. Gesamtliste aller offenen Punkte: `todo.md`.
- Version überall auf 2.0.0 gesetzt (`metadata.json`, `app/CMakeLists.txt`,
  `app/android/AndroidManifest.xml`, `STORE.md`, `docs/index.html`), Übersetzungen neu gebaut.
- `CHANGELOG.md`: Abschnitt „2.0.0" mit der Android/Plasma-Mobile-App als Hauptpunkt.
- Plasma-Mobile-App am Desktop getestet (offscreen, KDE-Theme statt Android/Material) — läuft
  genauso gut wie Android, ein Bug gefunden und gefixt (Zeilenmenü öffnete an falscher Stelle).
  Details in `todo.md`, Abschnitt „Plasma Mobile (Desktop-Test)".
- Android Release-Build läuft durch (unsigniert): `dist/android/plasmai-app-release.apk`.
- Linux-App-Tarball läuft durch: `dist/linux/plasmai-app-2.0.0-x86_64.tar.xz`, installiert und
  gestartet getestet.
- Flatpak-Manifest geschrieben (`packaging/flatpak/`), aber **nicht gebaut** — hier fehlt
  `flatpak-builder` und die KDE-Runtime.
- **CI-Lücke geschlossen**: `.github/workflows/android.yml` baute bisher ohne KF6 (nicht die
  App, die im Repo liegt — `~/kf6-android` existierte nur lokal, nicht reproduzierbar). Neues
  `scripts/build-kf6-android.sh` baut ECM + KCoreAddons + Kirigami für Android aus den
  KDE-Quellen (Tag `v6.8.0`) in unter einer Minute — end-to-end getestet: frisch gebaut, die
  App erfolgreich dagegen gelinkt, resultierende APK mit `readelf` geprüft. Workflow nutzt das
  jetzt. Details und ein dabei gefundener Bug (fehlendes `libomp.so` in der APK, hätte auf dem
  Gerät gecrasht) in `RELEASING.md` §4.1.

## Entschieden (2026-09-27)
- [x] **Zweites Backend** ist kein 2.0-Kriterium mehr, sondern das Ziel für 3.0 (`ROADMAP.md`).
- [x] **App-ID für Linux/Flathub**: `io.github.shrippen.Plasmai` (Dateien in `packaging/`, Desktop-Dateiname,
      Flatpak-`app-id`). Intern bleibt `com.github.shrippen.plasmai` (Keychain, gemeinsamer Konfigordner mit dem
      Widget, Android-Paketname).
- [x] **versionCode**: `Major*10000+Minor*100+Patch`, 2.0.0 = 20000.
- [x] **F-Droid-Weg**: IzzyOnDroid (nimmt die signierte APK aus dem GitHub-Release). Das Haupt-F-Droid-Repo
      bleibt für später (Qt und OpenSSL müssten dort aus dem Quellcode gebaut werden, `RELEASING.md` §4.6).

## 1. Android-Keystore anlegen (ich habe das nicht gemacht — Passwort muss von dir kommen)
- [ ] `keytool -genkeypair ...` (genauer Befehl in `RELEASING.md` §4.3), Passwort in einen
      Passwortmanager, `.jks`-Datei sicher und getrennt vom Repo aufbewahren.
- [ ] **Wichtig:** Dieser Keystore signiert alle künftigen Updates. Verloren = Play-Store-Listing
      kann nie wieder aktualisiert werden (bei GitHub/F-Droid nur ärgerlich, nicht fatal).
- [ ] Als GitHub-Secrets hinterlegen, falls CI später signieren soll (Namen in `RELEASING.md`).

## 2. CI verifizieren
- [ ] Den überarbeiteten Workflow einmal wirklich auf GitHub laufen lassen (push auf `main`
      oder `workflow_dispatch`) — bisher nur lokal (Build-Server dieser Maschine) validiert,
      nicht auf einem echten GitHub-Actions-Runner.

## 3. Android-Release signieren und hochladen
- [ ] `PLASMAI_KEYSTORE_*`-Umgebungsvariablen setzen, `./scripts/build-android.sh release`.
- [ ] Signierte APK prüfen (`adb install -r`, kurzer Funktionstest wie in `todo.md`).
- [ ] An GitHub Release anhängen (siehe Punkt 6).

## 4. IzzyOnDroid
- [x] Store-Texte und Icon in `fastlane/metadata/android/` (en-US, de-DE), Changelog `20000.txt`.
- [x] Screenshots aus dem Demo-Modus (en-US, de-DE) in `fastlane/metadata/android/*/images/phoneScreenshots/`.
- [ ] Nach dem GitHub-Release (Punkt 6): Aufnahme bei IzzyOnDroid beantragen (`RELEASING.md` §4.5).

## 5. Flatpak verifizieren
- [x] Manifest korrigiert: baut jetzt aus dem ganzen Repo (`subdir: app`; vorher fehlten `contents/code` und `translate`), App-Icon statt Chronometer-Symbol, neue App-ID. Metainfo mit Mobil-Angaben (Touch, Mindestbreite 360 px), validiert mit `appstreamcli`.
- [ ] `flatpak-builder` + `org.kde.Platform//6.9` + `org.kde.Sdk//6.9` installieren.
- [ ] `packaging/flatpak/com.github.shrippen.plasmai.yml` bauen, App testen (genauer Ablauf in
      der Datei selbst und `RELEASING.md` §5.2). Manifest-Kommentare abarbeiten (Runtime-Version
      aktuell? QtKeychain schon in der Runtime? qtkeychain-Tag aktuell?).
- [x] Screenshots in die Metainfo (`packaging/screenshots/`, per raw.githubusercontent.com verlinkt; erst nach dem Push erreichbar).
- [ ] Quelle auf `type: git` mit Tag umstellen.
- [ ] Falls gewünscht: PR gegen `flathub/flathub`.

## 6. GitHub Release erstellen
- [ ] Tag setzen und pushen (Befehle in `RELEASING.md` §6) — **macht das Release nach außen
      sichtbar**, vorher alles oben abschließen, was mit rein soll.
- [ ] Release-Assets anhängen: `.plasmoid` (+ `install-linux.sh`), signierte Android-APK,
      Linux-Tarball (+ `install-app-linux.sh`). Alle vier liegen nach den Builds oben in `dist/`.
- [ ] `store.kde.org`-Listing aktualisieren (Version, Changelog) — Ablauf in `STORE.md`.

## Aarch64 für Plasma Mobile
- [ ] Der lokal gebaute Linux-Tarball ist `x86_64` (diese Maschine). Für echte Plasma-Mobile-
      Geräte (meist `aarch64`) fehlt noch ein zweiter Tarball-Build für diese Architektur.
