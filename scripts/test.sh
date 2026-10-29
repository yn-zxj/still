#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
build_dir="${STILL_BUILD_DIR:-$project_dir/.build}"
testing_plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
plugin_options=()
if [ -f "$testing_plugin" ]; then
    plugin_options=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test --disable-xctest --package-path "$project_dir" --scratch-path "$build_dir" "${plugin_options[@]}" "$@"
