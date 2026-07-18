#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
mode="${1:-local}"
app_name="Capture Codex"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")
release_dir="$project_dir/dist/releases/$version"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/capture-codex-release.XXXXXX")
app_path="$work_dir/$app_name.app"
stable_archive_path=""

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$release_dir"

case "$mode" in
    local)
        SIGNING_IDENTITY=- \
        APP_OUTPUT_DIR="$app_path" \
        ARCHS="${ARCHS:-arm64}" \
            "$project_dir/scripts/build-app.sh"

        archive_path="$release_dir/Capture-Codex-$version-macOS-development.zip"
        rm -f "$archive_path"
        ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
        ;;

    notarized)
        : "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
        : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

        APP_OUTPUT_DIR="$app_path" \
        ARCHS="${ARCHS:-arm64 x86_64}" \
            "$project_dir/scripts/build-app.sh"

        codesign --verify --deep --strict --verbose=2 "$app_path"

        archive_path="$release_dir/Capture-Codex-$version-macOS.dmg"
        "$project_dir/scripts/create-dmg.sh" \
            "$app_path" \
            "$app_name" \
            "$archive_path"

        expected_team_id=$(codesign -dv --verbose=4 "$app_path" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
        "$project_dir/scripts/verify-dmg.sh" \
            "$archive_path" \
            "$app_name" \
            "jp.local.CaptureCodex.v2" \
            "$expected_team_id"

        codesign \
            --force \
            --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$archive_path"

        xcrun notarytool submit \
            "$archive_path" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$archive_path"
        xcrun stapler validate "$archive_path"

        stable_archive_path="$release_dir/Capture-Codex-macOS.dmg"
        rm -f "$stable_archive_path"
        ditto "$archive_path" "$stable_archive_path"
        ;;

    *)
        print -u2 "Usage: $0 [local|notarized]"
        exit 64
        ;;
esac

(
    cd "${archive_path:h}"
    shasum -a 256 "${archive_path:t}" > "${archive_path:t}.sha256"
)
if [[ -n "$stable_archive_path" ]]; then
    (
        cd "${stable_archive_path:h}"
        shasum -a 256 "${stable_archive_path:t}" > "${stable_archive_path:t}.sha256"
    )
fi
print "$archive_path"
