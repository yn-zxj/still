#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
build_dir="${STILL_BUILD_DIR:-$project_dir/.build}"
app_dir="${STILL_APP_DIR:-$project_dir/dist/息间.app}"
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$project_dir/Resources/Info.plist")"
export MACOSX_DEPLOYMENT_TARGET="$minimum"
binaries=()
for architecture in arm64 x86_64; do
    arch_build_dir="$build_dir/universal-$architecture"
    triple="$architecture-apple-macosx$minimum"
    swift build --package-path "$project_dir" --scratch-path "$arch_build_dir" --triple "$triple" -c release
    bin_dir="$(swift build --package-path "$project_dir" --scratch-path "$arch_build_dir" --triple "$triple" -c release --show-bin-path)"
    binaries+=("$bin_dir/Still")
done
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/Still"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [ -f "$project_dir/Resources/AppIcon.icns" ]; then cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"; fi
cat "$project_dir/Resources/Lucide/LICENSE" "$project_dir/Resources/Models/LICENSE-OpenPose.txt" "$project_dir/Resources/VideoParser/LICENSE-media-parser.txt" > "$app_dir/Contents/Resources/ThirdPartyNotices.txt"
cp "$project_dir/Resources/Models/LICENSE-OpenPose.txt" "$app_dir/Contents/Resources/LICENSE-OpenPose.txt"
cp "$project_dir/Resources/Models/StillPose.mlmodel" "$app_dir/Contents/Resources/StillPose.mlmodel"
cp "$project_dir/Resources/Models/SOURCE.json" "$app_dir/Contents/Resources/PoseModelSource.json"
codesign --force --sign - "$app_dir"
bash "$project_dir/scripts/validate-app.sh" "$app_dir"
echo "Built: $app_dir"
