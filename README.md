# Menu 2FA

macOS menu bar app for **TOTP** two-factor codes. Left-click copies a code; right-click opens Settings / Launch at Login / Quit / App Lock.

Forked in spirit from **Menu Launcher** (same settings-list UX), but accounts store secrets instead of launch targets.

## Quick facts

| | |
| --- | --- |
| Bundle ID | `ga.sgroi.menu-2fa` |
| Team | `AUP84ZCD2B` |
| Deployment | macOS 15.0+ |
| App Store | App ID `6806774047` |
| Storage | `UserDefaults` key `authItems` (local only) |
| Site | https://sgroi.ga/src/projects/menu-2fa/ |
| Privacy / Terms | https://sgroi.ga/src/legal/privacy/ · https://sgroi.ga/src/legal/terms/ |
| Support | https://sgroi.ga/src/Support/#menu-2fa |

## Open & run

1. Open `Menu 2FA.xcodeproj` in Xcode.
2. Confirm Signing Team `AUP84ZCD2B`.
3. Build & Run (menu bar accessory — no Dock window on launch).
4. Add an account via Settings → `+`.

Optional local launch after a Debug build:

```bash
./launch.sh
```

## AI / agent handoff

Read **[AGENTS.md](./AGENTS.md)** before changing code. It is the source of truth for architecture, UX rules, App Store notes, and related website paths.

## License

Proprietary — Gabriel Sgroi. All rights reserved.
