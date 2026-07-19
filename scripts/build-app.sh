#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="${APP_OUTPUT_DIR:-$project_dir/dist/Capture Codex.app}"
icon_source="$project_dir/Resources/AppIcon.png"
iconset_dir="$project_dir/.build/CaptureCodex.iconset"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")
signing_identity="${SIGNING_IDENTITY:--}"
architectures="${ARCHS:-$(uname -m)}"
build_root="$project_dir/.build/distribution"
binary_output="$build_root/CaptureCodex"

cd "$project_dir"

arch_binaries=()
for architecture in ${(z)architectures}; do
    scratch_path="$build_root/$architecture"
    swift build \
        -c release \
        --arch "$architecture" \
        --scratch-path "$scratch_path"
    arch_binaries+=("$scratch_path/$architecture-apple-macosx/release/CaptureCodex")
done

mkdir -p "$build_root"
if (( ${#arch_binaries[@]} == 1 )); then
    cp "$arch_binaries[1]" "$binary_output"
else
    lipo -create "${arch_binaries[@]}" -output "$binary_output"
fi

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$binary_output" "$app_dir/Contents/MacOS/CaptureCodex"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"

sparkle_framework=$(find "$project_dir/.build" -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print -quit)
if [[ -z "$sparkle_framework" ]]; then
    print -u2 "missing Sparkle.framework from Swift Package artifacts"
    exit 1
fi
mkdir -p "$app_dir/Contents/Frameworks"
ditto "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"

if [[ -f "$icon_source" ]]; then
    mkdir -p "$iconset_dir"
    sips -z 16 16 "$icon_source" --out "$iconset_dir/icon_16x16.png" >/dev/null
    sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_32x32.png" >/dev/null
    sips -z 64 64 "$icon_source" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$icon_source" --out "$iconset_dir/icon_128x128.png" >/dev/null
    sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_256x256.png" >/dev/null
    sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$icon_source" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
fi

sign_sparkle_components() {
    local identity="$1"
    local use_timestamp="$2"
    local framework="$app_dir/Contents/Frameworks/Sparkle.framework"
    local base="$framework/Versions/B"
    local args=(--force --options runtime --sign "$identity")
    if [[ "$use_timestamp" == "1" ]]; then
        args+=(--timestamp)
    fi

    codesign "${args[@]}" "$base/XPCServices/Installer.xpc"
    codesign "${args[@]}" --preserve-metadata=entitlements "$base/XPCServices/Downloader.xpc"
    codesign "${args[@]}" "$base/Autoupdate"
    codesign "${args[@]}" "$base/Updater.app"
    codesign "${args[@]}" "$framework"
}

if [[ "$signing_identity" == "-" ]]; then
    sign_sparkle_components "-" 0
    codesign \
        --force \
        --sign - \
        --requirements "=designated => identifier \"$bundle_id\"" \
        "$app_dir"
else
    sign_sparkle_components "$signing_identity" 1
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$app_dir"
fi

echo "$app_dir"
