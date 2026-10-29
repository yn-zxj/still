#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
build_dir="${STILL_BUILD_DIR:-$project_dir/.build}"
app_dir="${STILL_APP_DIR:-$project_dir/dist/息间.app}"
swift build --package-path "$project_dir" --scratch-path "$build_dir" -c release
bin_dir="$(swift build --package-path "$project_dir" --scratch-path "$build_dir" -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Still" "$app_dir/Contents/MacOS/Still"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [ -f "$project_dir/Resources/AppIcon.icns" ]; then cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"; fi
cp "$project_dir/Resources/Lucide/LICENSE" "$app_dir/Contents/Resources/ThirdPartyNotices.txt"
codesign --force --sign - "$app_dir"
echo "Built: $app_dir"
