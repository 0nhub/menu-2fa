# AGENTS.md — Menu 2FA handoff for future AI sessions

Read this file before editing. Prefer facts here over inventing product behavior.

## What this project is

**Menu 2FA** is a native **macOS menu bar** TOTP authenticator (SwiftUI + AppKit).

- Same overall UX pattern as **Menu Launcher** (settings list + menu bar), but copies codes instead of opening apps.
- **Do not overwrite** `/Users/gabriel/Menu Launcher`. Work only in `/Users/gabriel/Menu 2FA`.
- Website marketing/support lives in `/Users/gabriel/sgroi.ga` (separate repo/site).

## Paths & IDs

| Item | Value |
| --- | --- |
| Project root | `/Users/gabriel/Menu 2FA` |
| Xcode | `Menu 2FA.xcodeproj` |
| Sources | `Menu 2FA/*.swift` (PBXFileSystemSynchronizedRootGroup — files auto-picked up) |
| Bundle ID | `ga.sgroi.menu-2fa` |
| Team | `AUP84ZCD2B` |
| Deployment target | macOS 15.0 |
| App Store Connect app | `6806774047` |
| GitHub | `https://github.com/0nhub/menu-2fa` |
| iCloud backup copy (may lag) | `~/Library/Mobile Documents/com~apple~CloudDocs/Menu 2FA` |

## Product behavior (do not regress)

### Menu bar

- Closed: **lock** SF Symbol (`lock.fill`), template image.
- Left-click with accounts: show account list → selecting an item **copies** the current 6-digit TOTP to the clipboard. Brief **checkmark** feedback on success.
- If **App Lock** is enabled, left-click codes require LocalAuthentication (`deviceOwnerAuthentication` — Touch ID or Mac password) before showing the codes menu.
- Left-click with empty list / right-click / Control-click: context menu — **Settings**, **Require Authentication** (App Lock toggle), **Launch at Login**, **Quit**.
- While the codes menu is open: status icon becomes a **countdown ring**. Starts at 12 o’clock, fills **clockwise**, full circle = period elapsed; open gap = remaining time (30s TOTP).

### Settings window

- List of accounts with reorder (arrows), `+`, and `…` (Edit / Delete).
- Add/Edit dialog (`ItemEditorView`): icon (Choose Image / Remove Icon + drag & drop), optional **emoji**, optional **URL** (favicon fetch), title, token.
- Token field: **no placeholder**, no example secret in the field.
- Token accepts Base32 secrets and `otpauth://` URIs (`TOTP.fields(from:)`).

### TOTP

- `TOTP.swift`: Base32 decode, HMAC-SHA1, 6 digits, 30s period.
- Invalid secrets → copy fails with a warning alert.

### Persistence

- Accounts: `UserDefaults` key **`authItems`** (JSON `[LaunchItem]`).
- App Lock preference: `requireAuthentication`.
- No cloud sync. Do **not** claim Keychain in marketing unless code actually moves there.

### Icons for an account (priority)

1. Custom image (`iconData`)
2. Emoji (`emoji`)
3. Favicon from URL (`urlIconData` via `IconURLFetcher`)
4. Default lock placeholder

### App identity

- Accessory app (`NSApp.setActivationPolicy(.accessory)`).
- Dock/reopen → Settings.
- Official logo resource: `Menu2FALogo.png` applied as `NSApp.applicationIconImage`.
- Asset catalogs: `AppIcon` + `ApplicationIcon`.

## Important source files

| File | Role |
| --- | --- |
| `Menu_2FAApp.swift` | App entry, accessory policy, status item install |
| `StatusItemController.swift` | Menu bar, copy, countdown ring, App Lock gate, copy checkmark |
| `TOTP.swift` | Base32 + TOTP generation / remaining / progress |
| `LaunchItem.swift` | Account model + icon rendering |
| `LaunchItemStore.swift` | CRUD + clipboard copy (+ async pasteboard retry) |
| `ItemEditorView.swift` | Add/Edit sheet |
| `EditorView.swift` / `EditorWindowController.swift` | Settings UI / window |
| `LaunchAtLogin.swift` | Login item helper |
| `AppLock.swift` | LocalAuthentication gate + preference |
| `IconURLFetcher.swift` | Favicon / URL icon download |
| `Localizable.xcstrings` | Strings (many locales) |
| `launch.sh` | Kill + reopen Debug build from DerivedData |

## Naming debt (intentional)

Types still say **LaunchItem** / **LaunchItemStore** from the Menu Launcher fork. Prefer keeping names unless doing a deliberate rename refactor (touches many files + UserDefaults migration care).

## Build / run notes

- Prefer Xcode GUI if `xcodebuild -license` is not accepted on the machine.
- Ignore `DerivedData/` (local builds); never commit it.
- `launch.sh` points at a local DerivedData Debug app path — update if build location changes.

## App Store / review (context)

- Rejection seen: **Guideline 2.1 Information Needed** (screen recording + review notes), not a code crash.
- Reply + Notes should describe: menu bar launch, add account, copy code, countdown, no login, local-only, no external TOTP backend.
- Tested hardware example: iMac (Mac16,3) M4, macOS 26.5.2.
- Review screen recording is attached by the human in App Store Connect (**Datei anhängen** on the reply), not as optional App Preview only.
- Marketing text must not say **Keychain** while storage is UserDefaults.

## Related website (`sgroi.ga`)

Update these when product claims change:

- Project: `src/pages/menu-2fa.html` + `src/pages/de/menu-2fa.html` → build to `/src/projects/menu-2fa/`
- Privacy: authenticator section (`#authenticator`)
- Terms: secrets / one-time code responsibility
- Support: local overrides in `src/data/support-overrides.json` (merged over AppBackend feed for Menu 2FA)
- Project meta: `src/data/projects.json`
- Rebuild: `python3 src/scripts/build.py` from the site repo

## Rules for agents

1. **Never** modify Menu Launcher when working on Menu 2FA.
2. **Never** commit secrets, real TOTP seeds, or `.env` files.
3. Do not invent screenshots/video assets; user supplies App Store / site media.
4. Match existing Swift style; keep menu bar UX snappy and local-first.
5. If adding network features beyond favicon fetch, update Privacy + App Review notes.
6. After structural changes, update this file and `README.md`.

## Smoke checklist after changes

- [ ] App appears in menu bar as lock icon
- [ ] Add account with Base32 and with `otpauth://`
- [ ] Left-click copies 6-digit code; checkmark feedback
- [ ] Countdown ring while codes menu open
- [ ] Right-click: Settings, App Lock, Launch at Login, Quit
- [ ] App Lock blocks codes until auth succeeds
- [ ] Edit/delete/reorder accounts persist after relaunch
- [ ] Icon priority: image → emoji → URL favicon → default
