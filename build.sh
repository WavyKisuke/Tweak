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

for name in TikTokAudioMix TikTokPlus; do
  DYLIB="$(find .theos -type f -name "${name}.dylib" -print -quit 2>/dev/null || true)"
  if [ -z "$DYLIB" ]; then
    echo "ERROR: ${name}.dylib was not produced" >&2
    find packages .theos -type f \( -name '*.dylib' -o -name '*.deb' \) -print 2>/dev/null || true
    exit 1
  fi
  cp "$DYLIB" "dist/${name}.dylib"
  cp "${name}.plist" "dist/${name}.plist"
  test -s "dist/${name}.dylib"
  test -s "dist/${name}.plist"
done

cp packages/*.deb dist/ 2>/dev/null || true

echo "=== BUILD SUCCESS ==="
ls -lh dist/
