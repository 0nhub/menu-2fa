#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/DerivedData/Build/Products/Debug/Menu 2FA.app"
if [[ ! -d "$APP" ]]; then
  echo "Debug app not found at: $APP" >&2
  echo "Build once in Xcode (or xcodebuild) first." >&2
  exit 1
fi
killall "Menu 2FA" 2>/dev/null || true
open "$APP"
