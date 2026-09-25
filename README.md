# Menu 2FA

Private macOS-App (Swift / Xcode). Menüleisten-Authenticator: speichert TOTP-Konten lokal und kopiert Codes in die Zwischenablage.

Dieses README erklärt **was** die App ist, **wo** der Code liegt und **wie** die Teile zusammenhängen. Für Agent-/AI-Arbeit zusätzlich [`AGENTS.md`](./AGENTS.md) lesen.

---

## 1. Was ist das?

Menu 2FA ist eine **Accessory-App** (kein Dock-Fenster beim Start). Sie lebt in der **Menüleiste**.

| Aktion | Ergebnis |
| --- | --- |
| Linksklick (Konten vorhanden) | Liste der Accounts → Klick kopiert den aktuellen 6-stelligen TOTP-Code |
| Linksklick (keine Konten) / Rechtsklick | Kontextmenü: Settings, App Lock, Launch at Login, Support, More Apps, Quit |
| Menü offen | Schloss-Icon wird zum **Zeitradius** (30-Sekunden-TOTP) |
| Settings | Liste der Accounts, Reihenfolge per Drag-and-Drop der Zeile, `+` hinzufügen, `…` bearbeiten/löschen |

Technisch: SwiftUI für Settings/Dialoge, AppKit für Status Item und Menüs. Secrets liegen standardmäßig lokal in `UserDefaults` (`authItems`). **2FA Pro** schaltet Desktop-Widgets frei. Optionaler iCloud-Sync (Konten inkl. Tokens über `NSUbiquitousKeyValueStore`) läuft nur, wenn Pro aktiv ist, der Schalter an ist und auf dem Mac schon ein iCloud-Konto existiert. Die App fordert keine iCloud-Anmeldung an. Der Kauf liegt im Einstellungsfenster.

Die UI-Struktur ist an **Menu Launcher** angelehnt (gleiche Settings-Listen-Idee). Menu Launcher ist ein **separates** Projekt und darf hier nicht überschrieben werden.

---

## 2. Repository-Layout (wo liegt was?)

```
Menu 2FA/                          ← Git-Root / Arbeitsordner
    ├── README.md                      ← dieses Dokument (Produkt + Struktur)
    ├── AGENTS.md                      ← Regeln & Checklisten für AI/Agents
    ├── .gitignore
    ├── launch.sh                      ← Debug-App aus DerivedData neu öffnen
    ├── Menu 2FA.xcodeproj/            ← Xcode-Projekt
    │   ├── project.pbxproj
    │   └── xcshareddata/xcschemes/
    │       ├── Menu 2FA.xcscheme
    │       └── Menu 2FA Widget.xcscheme
    ├── Shared/                        ← Code für App + Widget + Intents (App Group, TOTP)
    ├── Menu 2FA Widget/             ← WidgetKit-Extension (Schreibtisch / Mitteilungszentrum)
    ├── Menu 2FA Intents/            ← Intents-Extension: Account-Liste für „Edit 2FA…“
    └── Menu 2FA/                      ← Source-Root (App-Dateien)
        ├── Menu_2FAApp.swift          ← @main, AppDelegate, Status Item startet hier
        ├── StatusItemController.swift ← Menüleiste, Menüs, Countdown, Copy-Feedback
        ├── LaunchItem.swift           ← Account-Modell + Icon-Rendering
        ├── LaunchItemStore.swift      ← Persistenz + Clipboard
        ├── SettingsView.swift         ← Settings-Tabs (2FA / General / Upgrade)
        ├── GeneralSettings.swift      ← Allgemein: Login, Lock, iCloud
        ├── ProStore.swift             ← StoreKit 2 — IAP „2FA Pro“
        ├── iCloudListSync.swift       ← iCloud KV + Sync-Flags
        ├── AuthItemCloudSchema.swift  ← iCloud-Payload für Konten
        ├── EditorView.swift           ← Tab „2FA“ — Kontenliste
        ├── EditorWindowController.swift
        ├── ItemEditorView.swift       ← Add/Edit-Sheet
        ├── QRCodeImport.swift         ← QR aus Kamera, Bild und Bildschirmausschnitt
        ├── AppLock.swift              ← Touch ID / Passwort-Gate
        ├── LaunchAtLogin.swift
        ├── IconURLFetcher.swift       ← Favicon von URL laden
        ├── Localizable.xcstrings
        ├── Menu_2FA.entitlements
        ├── Menu2FALogo.png
        └── Assets.xcassets/           ← AppIcon, ApplicationIcon, AccentColor
```

**Wichtig zur Xcode-Struktur:** Der Ordner `Menu 2FA/` ist eine **File System Synchronized Root Group**. Neue `.swift`-Dateien in diesem Ordner werden vom Projekt automatisch mitgebaut — kein manuelles Hinzufügen in der pbxproj nötig (außer Assets/Entitlements, die schon drin sind). `Shared/` gehört zu App, Widget und Intents-Extension; `Menu 2FA Widget/` nur zum Widget-Target; `Menu 2FA Intents/` nur zur Intents-Extension.

`DerivedData/` ist lokal und **nicht** im Repo.

---

## 3. Wie ist die Architektur aufgebaut?

Datenfluss von außen nach innen:

```
Menüleiste (StatusItemController)
    │  Linksklick → Codes-Menü / Rechtsklick → Kontextmenü
    │  optional AppLock.authenticate
    ▼
LaunchItemStore.shared  ←── App Group + UserDefaults["authItems"]
    │  copyCode / CRUD
    ▼
TOTP.code(for:)  →  Zwischenablage

Widget (Menu 2FA Widget)
    │  Pro Widget ein Konto; Galerie-Vorschau zeigt das erste Konto
    │  Nur mit 2FA Pro. Ohne Pro zeigt die Kachel „Pro“ und kopiert nicht.
    │  Ganze Kachel ist der Knopf. Klick schreibt nur eine Anfrage.
    │  Die Menüleisten-App kopiert den Code einmal (die Extension darf die Zwischenablage nicht halten).
    │  Kachel zeigt „Copied“. Settings bleiben zu.
    ▼
SharedAccountStore + TOTP  →  App schreibt die Zwischenablage

Settings-Fenster (EditorWindowController → EditorView)
    │  + / … → ItemEditorView (Sheet)
    ▼
LaunchItemStore.add / update / remove
```

### Schicht: App-Start

1. `Menu_2FAApp` (`@main`) + `AppDelegate`
2. `NSApp.setActivationPolicy(.accessory)` — nur Menüleiste
3. `StatusItemController.install()` hängt das Status Item ein
4. Settings-`Window`-Scene existiert, startet aber unterdrückt (`.defaultLaunchBehavior(.suppressed)`)

### Schicht: Menüleiste

`StatusItemController` besitzt das `NSStatusItem`.

- Idle-Icon: `lock.fill`
- Codes-Menü: ein Eintrag pro `LaunchItem` (Name + Icon)
- Nach erfolgreichem Copy: kurz `checkmark`
- Während Codes-Menü: `CountdownRingView` (Kreis ab 12 Uhr, im Uhrzeigersinn)
- App Lock an → vor Codes-Menü LocalAuthentication

### Schicht: Daten

| Typ / Key | Bedeutung |
| --- | --- |
| `LaunchItem` | Ein Account: `id`, `name`, `secret`, optional `iconData`, `emoji`, `url`, `urlIconData` |
| `LaunchItemStore` | `@Observable` Singleton, lädt/speichert JSON unter `authItems` (App Group `AUP84ZCD2B.ga.sgroi.menu-2fa` + Standard-Defaults) |
| `AppLock` / `requireAuthentication` | Ob Codes hinter System-Auth liegen (Flag ebenfalls im App Group, fürs Widget) |
| Widget | Mehrere Desktop-Widgets; jedes wählt im Edit-Modus sein Konto (Logo + Name); Klick kopiert den Code |

Icon-Priorität eines Accounts: **eigenes Bild → Emoji → Favicon von URL → Standard-Schloss**.

### Schicht: Settings UI

| Datei | Aufgabe |
| --- | --- |
| `EditorWindowController` | Fenster zeigen/aktivieren |
| `EditorView` | Liste, leerer Zustand, Toolbar (`+`, Quit) |
| `ItemEditorView` | Sheet: Icon/Emoji/URL, Titel, Token (ohne Placeholder), QR-Menü |
| `QRCodeImport` | Lokale QR-Erkennung via Vision, Kamera und Bildschirmaufnahme |

Token darf Base32 oder `otpauth://` sein (`TOTP.fields(from:)`). Das QR-Symbol neben
dem Token-Feld importiert denselben Wert aus der Kamera, einer Bilddatei oder einem
direkt mit dem Fadenkreuz markierten Bildschirmbereich. Beim Loslassen wird der QR-Code
automatisch übernommen. QR-Inhalte werden lokal ausgewertet.

### Schicht: Crypto

`Shared/TOTP.swift` — Base32-Decode, HMAC-SHA1, 6 Stellen, Periode 30 s. Kein Netzwerk für Codes; nur `IconURLFetcher` holt optional Favicons (Sandbox: `network.client`).

### Schicht: Widgets

Die Extension `ga.sgroi.menu-2fa.widget` läuft unabhängig von der App. Es gibt nur **ein** Widget: ein Konto pro Instanz. Rechtsklick → **Edit 2FA…** dreht die Kachel; dort wählt man **Account** — nichts davon in Settings. Die Fläche zeigt Logo und Name, nicht den Code. Die ganze Fläche ist der Kopier-Knopf, und das nur mit **2FA Pro**. Ohne Pro zeigt die Kachel **Pro** und kopiert nicht. Mit Pro legt die Menüleisten-App den aktuellen Code **einmal** in die Zwischenablage (die Extension selbst hält die Zwischenablage nicht) und die Kachel wechselt kurz auf **Copied** — Settings öffnen sich dabei nicht. `SelectAccount.intentdefinition` liegt in `Shared/`; die Account-Liste kommt von `SelectAccountIntentHandler` in der Intents-Extension. Konten liegen in der App Group plus einem schlanken Widget-Snapshot (Keychain + Application-Support-Datei).

---

## 4. Identifiers & Build

| | |
| --- | --- |
| Bundle ID | `ga.sgroi.menu-2fa` |
| Development Team | `AUP84ZCD2B` |
| Deployment | macOS 15.0+ |
| App Store Connect | App ID `6806774047` |
| Entitlements | App Sandbox, Kamera, network client, user-selected files (read-only), App Group `AUP84ZCD2B.ga.sgroi.menu-2fa` |

Versionierung: öffentliche Releases verwenden ausschließlich `1.1`, `1.2`, `1.3` usw.
Keine Patch-Versionen wie `1.1.1`. Die interne Build-Nummer wird weiterhin bei jedem
Upload erhöht.

Lokal bauen:

1. `Menu 2FA.xcodeproj` in Xcode öffnen  
2. Team prüfen → Build & Run  
3. Optional danach: `./launch.sh` (öffnet Debug-Build aus `DerivedData`)

---

## 5. Benennung (historisch)

`LaunchItem` / `LaunchItemStore` heißen noch so wegen des Menu-Launcher-Forks. Inhaltlich sind es **Auth-Accounts**, nicht Launch-Targets. Umbenennen nur bewusst (viele Call-Sites + gespeicherte Daten).

---

## 6. Verwandte, aber getrennte Systeme

| Ort | Rolle |
| --- | --- |
| `/Users/gabriel/Menu Launcher` | Schwester-App — nicht anfassen |
| `/Users/gabriel/sgroi.ga` | Marketing, Privacy, Terms, Support |
| Produktseite | https://sgroi.ga/src/projects/menu-2fa/ |
| Support | https://sgroi.ga/src/Support/#menu-2fa |

---

## 7. Für AI / Agents

Kurz: dieses README = Struktur verstehen.  
[`AGENTS.md`](./AGENTS.md) = Do/Don’t, UX-Nicht-Regressionsregeln, App-Store-Kontext, Smoke-Checklist.

---

## Lizenz

Proprietary — Gabriel Sgroi. All rights reserved. Repository ist **privat**.
