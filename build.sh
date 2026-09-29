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

find .theos -type f -name 'YouTubeAudioMix.dylib' -exec cp {} dist/YouTubeAudioMix.dylib \;
cp YouTubeAudioMix.plist dist/YouTubeAudioMix.plist

test -s dist/YouTubeAudioMix.dylib
test -s dist/YouTubeAudioMix.plist

file dist/YouTubeAudioMix.dylib
lipo -info dist/YouTubeAudioMix.dylib
plutil -lint dist/YouTubeAudioMix.plist

echo "=== YOUTUBE BUILD SUCCESS ==="
ls -lh dist/YouTubeAudioMix.*
