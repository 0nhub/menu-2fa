# AGENTS.md — Arbeitsregeln für AI-Sessions

Zuerst [`README.md`](./README.md) lesen (Was / Wo / Architektur).  
Diese Datei ergänzt **operative Regeln**, die man nicht aus dem Code raten soll.

## Harte Grenzen

1. Nur in `/Users/gabriel/Menu 2FA` arbeiten. **Nie** Menu Launcher überschreiben.
2. Keine echten TOTP-Secrets, Recovery-Codes oder `.env` committen.
3. Keine Screenshots/Videos erfinden — Medien liefert der Mensch.
4. Marketing/Privacy: Speicherung ist **UserDefaults (`authItems`)**, nicht Keychain (solange der Code das nicht ändert).
5. Nach Strukturänderungen: `README.md` und diese Datei aktualisieren.

## Was die App tun muss (Nicht-Regression)

### Menüleiste

- Idle: SF Symbol `lock.fill` (Template).
- Linksklick + Konten → Codes-Menü; Auswahl **kopiert** 6-stelligen TOTP.
- Erfolgreiches Copy → kurz Checkmark-Feedback.
- App Lock an → vor Codes-Menü `LocalAuthentication` (`deviceOwnerAuthentication`).
- Rechtsklick / Control-Klick / leere Liste → Kontext: Settings, Require Authentication, Launch at Login, Quit.
- Codes-Menü offen → Countdown-Ring ab 12 Uhr, **im Uhrzeigersinn**, Lücke = Restzeit (30 s).

### Settings

- Liste mit Pfeilen (Reorder), `+`, `…` (Edit/Delete).
- Sheet: Bild (Choose/Remove + Drop), optional Emoji, optional URL (Favicon), Titel, Token.
- Token-Feld: **kein Placeholder**, kein Beispielsecret.
- Token: Base32 oder `otpauth://`.

### Persistenz

- Konten: `UserDefaults` → `authItems` (JSON `[LaunchItem]`).
- App Lock: `requireAuthentication`.
- Kein Cloud-Sync für Secrets.

### Icon-Priorität

Custom image → Emoji → URL-Favicon → Lock-Placeholder.

## Datei → Verantwortung (Kurz)

| Datei | Verantwortung |
| --- | --- |
| `Menu_2FAApp.swift` | Entry, Accessory, Status Item installieren |
| `StatusItemController.swift` | Menüleiste / Menüs / Ring / Copy-Feedback / Lock-Gate |
| `TOTP.swift` | Crypto + Restzeit |
| `LaunchItem.swift` | Modell + Icon zeichnen |
| `LaunchItemStore.swift` | CRUD + Pasteboard |
| `EditorView.swift` | Settings-Liste |
| `EditorWindowController.swift` | Fenster |
| `ItemEditorView.swift` | Add/Edit |
| `AppLock.swift` | LAContext-Gate |
| `LaunchAtLogin.swift` | Login Item |
| `IconURLFetcher.swift` | Netzwerk nur für Favicons |
| `Localizable.xcstrings` | Strings |
| `launch.sh` | Debug-App neu öffnen |

Xcode: Ordner `Menu 2FA/` ist **PBXFileSystemSynchronizedRootGroup** — neue Swift-Dateien dort werden auto-inkludiert.

## IDs

- Bundle: `ga.sgroi.menu-2fa`
- Team: `AUP84ZCD2B`
- Deployment: macOS 15.0+
- ASC App: `6806774047`
- GitHub (privat): `https://github.com/0nhub/menu-2fa`

## Website (separates Repo `sgroi.ga`)

Bei geänderten Produktaussagen mitpflegen:

- `src/pages/menu-2fa.html` + DE-Variante
- Privacy `#authenticator`, Terms (Secrets/Codes)
- `src/data/support-overrides.json`, `src/data/projects.json`
- Build: `python3 src/scripts/build.py`

## App-Store-Kontext (Stand)

Frühere Ablehnung: Guideline **2.1 Information Needed** (Screen Recording + Review-Notes), kein Crash-Bug. Review-Video hängt der Mensch an die ASC-Antwort.

## Smoke nach Änderungen

- [ ] Lock-Icon in der Menüleiste
- [ ] Account mit Base32 und mit `otpauth://` anlegen
- [ ] Linksklick kopiert Code + Checkmark
- [ ] Countdown-Ring bei offenem Codes-Menü
- [ ] Rechtsklick: Settings / Lock / Login / Quit
- [ ] App Lock blockiert Codes bis Auth OK
- [ ] Edit/Delete/Reorder überlebt Neustart
- [ ] Icon-Priorität stimmt
