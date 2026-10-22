#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 /path/to/Campfire.app /path/to/Campfire.dmg" >&2
  exit 1
fi
if [[ ! -f "$1/Contents/Info.plist" ]]; then
  echo "App bundle not found: $1" >&2
  exit 1
fi
if [[ -e "$2" ]]; then
  echo "Output already exists: $2" >&2
  exit 1
fi
if ! command -v uvx >/dev/null; then
  echo "Install uv (which includes uvx) before running this script." >&2
  exit 1
fi

app=$(cd "$1" && pwd)
mkdir -p "$(dirname "$2")"
output="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
cd "$(dirname "$0")/.."
uvx --from dmgbuild==1.6.7 dmgbuild \
  -s Packaging/dmg-settings.py -D "app=$app" Campfire "$output"
hdiutil verify "$output"
