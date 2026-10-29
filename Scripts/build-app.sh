#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${ISLA_OUTPUT_ROOT:-$project_root/outputs}"
build_root="${ISLA_BUILD_ROOT:-${TMPDIR:-/tmp}/isla-swift-build}"
source_root="$(mktemp -d /tmp/isla-source.XXXXXX)"
stage_root="$(mktemp -d /tmp/isla-package.XXXXXX)"
trap 'rm -rf "$source_root" "$stage_root"' EXIT
# Compile a local source snapshot: cloud sync can change input metadata mid-build.
python3 - "$project_root" "$source_root" <<'PYTHON'
from pathlib import Path
import shutil
import sys
source, snapshot = map(Path, sys.argv[1:])
shutil.copy2(source / 'Package.swift', snapshot / 'Package.swift')
for directory in ('Sources', 'Vendor'):
    shutil.copytree(source / directory, snapshot / directory,
                    ignore=shutil.ignore_patterns('.build', '.swiftpm', '.git', '.DS_Store'))
PYTHON
swift build --scratch-path "$build_root/main" --build-system native --package-path "$source_root" -c release --arch arm64
swift build --scratch-path "$build_root/adapter" --build-system native --package-path "$source_root/Vendor/MediaRemoteAdapter" -c release --arch arm64
adapter_binary_root="$(swift build --scratch-path "$build_root/adapter" --build-system native --package-path "$source_root/Vendor/MediaRemoteAdapter" -c release --arch arm64 --show-bin-path)"
binary_root="$(swift build --scratch-path "$build_root/main" --build-system native --package-path "$source_root" -c release --arch arm64 --show-bin-path)"
app_path="$stage_root/Isla.app"
mkdir -p "$output_root" "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_root/Isla" "$app_path/Contents/MacOS/Isla"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/Isla.icns" "$app_path/Contents/Resources/Isla.icns"
cp "$project_root/THIRD-PARTY-NOTICES.md" "$app_path/Contents/Resources/THIRD-PARTY-NOTICES.md"
mkdir -p "$app_path/Contents/Resources/MediaRemoteAdapter"
cp "$adapter_binary_root/libIslaMediaRemoteAdapter.dylib" "$app_path/Contents/Resources/MediaRemoteAdapter/"
cp "$project_root/Vendor/MediaRemoteAdapter/run.pl" "$app_path/Contents/Resources/MediaRemoteAdapter/"
xattr -cr "$app_path"
python3 "$project_root/Scripts/sign-app.py" "$app_path"
codesign --verify --deep --strict "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_root/Isla.zip"
ditto --noextattr "$app_path" "$output_root/Isla.app"
xattr -cr "$output_root/Isla.app"
codesign --verify --deep --strict "$output_root/Isla.app"
