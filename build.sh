#!/usr/bin/env bash
set -euo pipefail
export THEOS="${THEOS:-$HOME/theos}"
cd "$(dirname "$0")"
if [ ! -d "$THEOS" ]; then
  echo "Theos is not installed at $THEOS" >&2
  exit 1
fi
make clean package FINALPACKAGE=1 STRIP=1
mkdir -p ../dist
cp -f packages/*.deb ../dist/ 2>/dev/null || true
cp -f .theos/obj/arm64/*.dylib ../dist/TikTokAudioMix.dylib 2>/dev/null || true
cp -f TikTokAudioMix.plist ../dist/TikTokAudioMix.plist

echo
printf 'Build output:\n'
ls -lh ../dist
