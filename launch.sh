#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/DerivedData/Build/Products/Debug/2FA.app"
if [[ ! -d "$APP" ]]; then
  APP="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Menu_2FA-*/Build/Products/Debug/2FA.app 2>/dev/null | head -1 || true)"
fi
if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "Debug app not found. Build once in Xcode (or xcodebuild) first." >&2
  exit 1
fi
killall "2FA" 2>/dev/null || true
killall "Menu 2FA" 2>/dev/null || true
killall "Menu 2FA Widget" 2>/dev/null || true
killall chronod 2>/dev/null || true
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "/Applications/2FA.app" >/dev/null 2>&1 || true
while IFS= read -r other; do
  if [[ -n "$other" && "$other" != "$APP" ]]; then
    "$LSREGISTER" -u "$other" >/dev/null 2>&1 || true
  fi
done < <(mdfind "kMDItemCFBundleIdentifier == 'ga.sgroi.menu-2fa'" 2>/dev/null || true)
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
echo "Tip: Upgrade benutzt die lokale StoreKit-Datei und öffnet keine Apple-Account-Anmeldung." >&2
open "$APP"
