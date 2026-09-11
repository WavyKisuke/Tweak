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

DYLIB="$(find .theos -type f -name 'TikTokPlus.dylib' -print -quit 2>/dev/null || true)"
if [ -z "$DYLIB" ]; then
  echo "ERROR: TikTokPlus.dylib was not produced" >&2
  find packages .theos -type f \( -name '*.dylib' -o -name '*.deb' \) -print 2>/dev/null || true
  exit 1
fi

cp "$DYLIB" dist/TikTokPlus.dylib
cp TikTokPlus.plist dist/TikTokPlus.plist
cp packages/*.deb dist/ 2>/dev/null || true

test -s dist/TikTokPlus.dylib
test -s dist/TikTokPlus.plist

echo "=== BUILD SUCCESS ==="
ls -lh dist/
