#!/bin/bash
set -euo pipefail

# Keep downloaded packages and build products beside this source checkout.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(dirname "$project_dir")"

xcodebuild \
    -project "$project_dir/Whisky.xcodeproj" \
    -scheme Whisky \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$work_dir/build-dev" \
    -clonedSourcePackagesDirPath "$work_dir/packages-dev" \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_SWIFTLINT="${SKIP_SWIFTLINT:-NO}" \
    build

codesign --force --deep --sign - "$work_dir/build-dev/Build/Products/Debug/Whisky Dev.app"

echo "Built app: $work_dir/build-dev/Build/Products/Debug/Whisky Dev.app"
