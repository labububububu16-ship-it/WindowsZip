#!/bin/zsh
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLED_APP="/Applications/WindowsZip.app/Contents/MacOS/WindowsZip"
LOCAL_BUILD="$TOOL_DIR/WindowsZip-build-copy/Contents/MacOS/WindowsZip"
if [[ -x "$INSTALLED_APP" ]]; then
  exec "$INSTALLED_APP" "$@"
fi
exec "$LOCAL_BUILD" "$@"
