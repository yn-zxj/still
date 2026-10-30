#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$project_dir/dist/息间.app}"
binary="$app/Contents/MacOS/Still"
test -x "$binary"
plutil -lint "$app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = 'local.still.app'
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
test "$minimum" = '13.0'
read -r -a architectures <<< "$(lipo -archs "$binary")"
test "${#architectures[@]}" -eq 2
for architecture in arm64 x86_64; do
    lipo "$binary" -verify_arch "$architecture"
    build_info="$(xcrun vtool -arch "$architecture" -show-build "$binary")"
    actual_minimum="$(awk '$1 == "minos" {print $2}' <<< "$build_info")"
    test "$actual_minimum" = "$minimum"
    echo "$architecture: minimum macOS $actual_minimum"
done
codesign --verify --strict --verbose=2 "$app"
test -s "$app/Contents/Resources/LICENSE-OpenPose.txt"
expected="$(plutil -extract modelSHA256 raw "$app/Contents/Resources/PoseModelSource.json")"
actual="$(shasum -a 256 "$app/Contents/Resources/StillPose.mlmodel" | awk '{print $1}')"
test "$expected" = "$actual"
echo 'Universal app, deployment targets, signature and model verified.'
