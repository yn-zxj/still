#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK directory}"
: "${JAVA_HOME:?Set JAVA_HOME to a JDK 17+ directory}"
"${GRADLE_BIN:-gradle}" -p "$project_dir/watch-companion" --no-daemon assembleDebug
mkdir -p "$project_dir/dist"
cp "$project_dir/watch-companion/app/build/outputs/apk/debug/app-debug.apk" "$project_dir/dist/Still-Link-debug.apk"
echo "Built: $project_dir/dist/Still-Link-debug.apk"
