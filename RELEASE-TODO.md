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
- **CI-Lücke geschlossen**: `.github/workflows/android.yml` baute bisher ohne KF6 (nicht die
  App, die im Repo liegt — `~/kf6-android` existierte nur lokal, nicht reproduzierbar). Neues
  `scripts/build-kf6-android.sh` baut ECM + KCoreAddons + Kirigami für Android aus den
  KDE-Quellen (Tag `v6.8.0`) in unter einer Minute — end-to-end getestet: frisch gebaut, die
  App erfolgreich dagegen gelinkt, resultierende APK mit `readelf` geprüft. Workflow nutzt das
  jetzt. Details und ein dabei gefundener Bug (fehlendes `libomp.so` in der APK, hätte auf dem
  Gerät gecrasht) in `RELEASING.md` §4.1.

## Zu klären, bevor es weitergeht
- [ ] **App-ID für Flatpak**: aktuell `com.github.shrippen.plasmai` (wie Plasmoid/Android).
      Flathub-Konvention für GitHub-Projekte wäre eher `io.github.shrippen.Plasmai`. Die ID
      lässt sich nach der ersten Flathub-Veröffentlichung nicht mehr ändern — vorher entscheiden.
- [ ] **versionCode-Schema**: aktuell `Major*100+Minor*10+Patch` (200 für 2.0.0). Reicht das für
      alle künftigen Patch-Releases, oder lieber mehr Spielraum (`Major*10000+Minor*100+Patch`)?
      versionCode darf bei Play Store/F-Droid nie sinken — vor dem ersten 2.x-Release entscheiden.
- [ ] **F-Droid überhaupt anstreben?** Der größte Unsicherheitsfaktor (KF6-für-Android-Toolchain)
      ist jetzt gelöst und reproduzierbar (s. o.). Offen bleibt: F-Droids Sandbox erlaubt keinen
      Live-Netzwerkzugriff beim Bauen — das `git clone` in `build-kf6-android.sh` muss als
      F-Droid-`srclibs:`-Eintrag umgebaut werden. Machbar, aber noch nicht gemacht (Punkt 4).

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

## 4. F-Droid-Recipe (nur falls Punkt „Zu klären" oben mit Ja beantwortet)
- [ ] `RELEASING.md` §4.5 lesen, `srclibs:`-Umbau für den KF6-Teil, Recipe schreiben, PR gegen
      `fdroiddata` öffnen.

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
