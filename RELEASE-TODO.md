# TODO: Release 2.0.0 veröffentlichen

Für dich vorbereitet, damit diese Aufgabe unbeaufsichtigt laufen kann. Heißt bewusst nicht
`todo.md` — die Datei gibt es schon und trackt den UI-Feinschliff von Android/Plasma Mobile
gegen das Plasmoid. Technische Details und Begründungen zu jedem Punkt hier stehen in
`RELEASING.md`.

## Stand (schon erledigt, lokal, nichts veröffentlicht)
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

## Zu klären, bevor es weitergeht
- [ ] **App-ID für Flatpak**: aktuell `com.github.shrippen.plasmai` (wie Plasmoid/Android).
      Flathub-Konvention für GitHub-Projekte wäre eher `io.github.shrippen.Plasmai`. Die ID
      lässt sich nach der ersten Flathub-Veröffentlichung nicht mehr ändern — vorher entscheiden.
- [ ] **versionCode-Schema**: aktuell `Major*100+Minor*10+Patch` (200 für 2.0.0). Reicht das für
      alle künftigen Patch-Releases, oder lieber mehr Spielraum (`Major*10000+Minor*100+Patch`)?
      versionCode darf bei Play Store/F-Droid nie sinken — vor dem ersten 2.x-Release entscheiden.
- [ ] **F-Droid überhaupt anstreben?** F-Droid baut selbst aus dem Quellcode, nicht aus einer
      APK. Das braucht denselben KF6-für-Android-Toolchain wie unten (Punkt 2) — unklar, ob
      F-Droids Build-Server das mitmacht. Das ist der größte offene Blocker in diesem Release.

## 1. Android-Keystore anlegen (ich habe das nicht gemacht — Passwort muss von dir kommen)
- [ ] `keytool -genkeypair ...` (genauer Befehl in `RELEASING.md` §4.3), Passwort in einen
      Passwortmanager, `.jks`-Datei sicher und getrennt vom Repo aufbewahren.
- [ ] **Wichtig:** Dieser Keystore signiert alle künftigen Updates. Verloren = Play-Store-Listing
      kann nie wieder aktualisiert werden (bei GitHub/F-Droid nur ärgerlich, nicht fatal).
- [ ] Als GitHub-Secrets hinterlegen, falls CI später signieren soll (Namen in `RELEASING.md`).

## 2. CI kann noch keine echte Android-App bauen (größte offene Baustelle)
- [ ] `.github/workflows/android.yml` baut aktuell **ohne KF6** — nicht die App, die im Repo
      liegt. Lokal funktioniert `scripts/build-android.sh`, weil `~/kf6-android` auf dieser
      Maschine schon existiert (von früher, nicht reproduzierbar dokumentiert).
- [ ] Vor dem ersten „echten" CI-Release: Reproduzierbaren Weg finden, KF6 für Android zu bauen
      (siehe `RELEASING.md` §4.1 für drei mögliche Ansätze) und in CI einbinden.
- [ ] Bis dahin: Release-APKs kommen von einer lokalen Maschine mit `~/kf6-android`.

## 3. Android-Release signieren und hochladen
- [ ] `PLASMAI_KEYSTORE_*`-Umgebungsvariablen setzen, `./scripts/build-android.sh release`.
- [ ] Signierte APK prüfen (`adb install -r`, kurzer Funktionstest wie in `todo.md`).
- [ ] An GitHub Release anhängen (siehe Punkt 6).

## 4. F-Droid-Recipe (nur falls Punkt „Zu klären" oben mit Ja beantwortet)
- [ ] Erst Punkt 2 lösen (F-Droids Buildserver braucht denselben Toolchain).
- [ ] `RELEASING.md` §4.5 lesen, Recipe schreiben, PR gegen `fdroiddata` öffnen.

## 5. Flatpak verifizieren
- [ ] `flatpak-builder` + `org.kde.Platform//6.9` + `org.kde.Sdk//6.9` installieren.
- [ ] `packaging/flatpak/com.github.shrippen.plasmai.yml` bauen, App testen (genauer Ablauf in
      der Datei selbst und `RELEASING.md` §5.2). Manifest-Kommentare abarbeiten (Runtime-Version
      aktuell? QtKeychain schon in der Runtime? qtkeychain-Tag aktuell?).
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
