#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export THEOS="${THEOS:-$HOME/theos}"

if [ ! -d "$THEOS" ]; then
  echo "ERROR: Theos is not installed at $THEOS" >&2
  exit 1
fi

rm -rf dist
mkdir -p dist

make clean package FINALPACKAGE=1 STRIP=1

DYLIB="$(find .theos -type f -name 'TikTokAudioMix.dylib' -print -quit 2>/dev/null || true)"
if [ -z "$DYLIB" ]; then
  echo "ERROR: TikTokAudioMix.dylib was not produced" >&2
  find packages .theos -type f \( -name '*.dylib' -o -name '*.deb' \) -print 2>/dev/null || true
  exit 1
fi

cp "$DYLIB" dist/TikTokAudioMix.dylib
cp TikTokAudioMix.plist dist/TikTokAudioMix.plist
cp packages/*.deb dist/ 2>/dev/null || true

test -s dist/TikTokAudioMix.dylib
test -s dist/TikTokAudioMix.plist

echo "=== BUILD SUCCESS ==="
ls -lh dist/
