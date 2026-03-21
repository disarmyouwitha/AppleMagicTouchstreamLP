#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/release-config.env}"

PROJECT_PATH="GlassToKey/GlassToKey.xcodeproj"
SCHEME="GlassToKey"
CONFIGURATION="Release"
TEAM_ID="N9XQZJR4EP"
APP_NAME="GlassToKey"
EXECUTABLE_NAME="GlassToKey"
EXPECTED_BUNDLE_ID="ink.ranna.glasstokey"
ENTITLEMENTS_PATH="GlassToKey/GlassToKey/GlassToKey.entitlements"

DERIVED_DATA_PATH="$SCRIPT_DIR/release-output/DerivedData"
RELEASE_ROOT="$SCRIPT_DIR/release-output"

log_step() {
    printf '[STEP] %s\n' "$1"
}

log_pass() {
    printf '[PASS] %s\n' "$1"
}

log_warn() {
    printf '[WARN] %s\n' "$1"
}

log_fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || log_fail "Required tool not found: $1"
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_fail "Missing config file: $CONFIG_FILE (start from release-config.env.template)"
    fi

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${MARKETING_VERSION:?MARKETING_VERSION is required}"
    : "${BUILD_NUMBER:?BUILD_NUMBER is required}"
    : "${DEVELOPER_ID_APPLICATION_CERT:?DEVELOPER_ID_APPLICATION_CERT is required}"
}

resolve_notary_args() {
    NOTARY_ARGS=()

    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        NOTARY_ARGS=(
            --keychain-profile "$NOTARY_KEYCHAIN_PROFILE"
        )
        if [[ -n "${NOTARY_KEYCHAIN_PATH:-}" ]]; then
            NOTARY_ARGS+=(
                --keychain "$NOTARY_KEYCHAIN_PATH"
            )
        fi
        return
    fi

    if [[ -n "${APPLE_ID:-}" || -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
        : "${APPLE_ID:?APPLE_ID is required for Apple ID auth}"
        : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required for Apple ID auth}"
        : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for Apple ID auth}"
        NOTARY_ARGS=(
            --apple-id "$APPLE_ID"
            --password "$APPLE_APP_SPECIFIC_PASSWORD"
            --team-id "$APPLE_TEAM_ID"
        )
        return
    fi

    if [[ -n "${NOTARY_API_KEY_PATH:-}" || -n "${NOTARY_API_KEY_ID:-}" || -n "${NOTARY_API_ISSUER:-}" ]]; then
        : "${NOTARY_API_KEY_PATH:?NOTARY_API_KEY_PATH is required for API key auth}"
        : "${NOTARY_API_KEY_ID:?NOTARY_API_KEY_ID is required for API key auth}"
        : "${NOTARY_API_ISSUER:?NOTARY_API_ISSUER is required for API key auth}"
        NOTARY_ARGS=(
            --key "$NOTARY_API_KEY_PATH"
            --key-id "$NOTARY_API_KEY_ID"
            --issuer "$NOTARY_API_ISSUER"
        )
        return
    fi

    log_fail "No notarization credentials configured. Set Apple ID or App Store Connect API key values in $CONFIG_FILE."
}

preflight() {
    log_step "Checking local release prerequisites"
    require_tool xcodebuild
    require_tool codesign
    require_tool xcrun
    require_tool hdiutil
    require_tool ditto
    require_tool lipo
    require_tool spctl
    require_tool security
    require_tool /usr/libexec/PlistBuddy

    local identities
    identities="$(security find-identity -v -p codesigning || true)"
    if ! grep -Fq "\"$DEVELOPER_ID_APPLICATION_CERT\"" <<<"$identities"; then
        printf '%s\n' "$identities"
        log_fail "Developer ID Application certificate not found in the keychain: $DEVELOPER_ID_APPLICATION_CERT"
    fi

    if [[ ! -f "$SCRIPT_DIR/$PROJECT_PATH/project.pbxproj" ]]; then
        log_fail "Project not found: $PROJECT_PATH"
    fi

    if [[ ! -f "$SCRIPT_DIR/$ENTITLEMENTS_PATH" ]]; then
        log_fail "Entitlements file not found: $ENTITLEMENTS_PATH"
    fi

    log_pass "Local prerequisites look sane"
}

build_release() {
    log_step "Building unsigned Release app"
    rm -rf "$DERIVED_DATA_PATH"
    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        clean build \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        PRODUCT_BUNDLE_IDENTIFIER="$EXPECTED_BUNDLE_ID" \
        MARKETING_VERSION="$MARKETING_VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        ENABLE_HARDENED_RUNTIME=YES

    APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
    [[ -d "$APP_PATH" ]] || log_fail "Built app not found: $APP_PATH"
    APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
    [[ -f "$APP_EXECUTABLE" ]] || log_fail "Built executable not found: $APP_EXECUTABLE"

    log_pass "Release build completed"
}

verify_bundle_metadata() {
    log_step "Verifying bundle metadata"
    local bundle_id
    local short_version
    local build_version
    local executable_name

    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
    short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
    build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"

    [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || log_fail "Unexpected bundle ID: $bundle_id"
    [[ "$short_version" == "$MARKETING_VERSION" ]] || log_fail "Unexpected marketing version: $short_version"
    [[ "$build_version" == "$BUILD_NUMBER" ]] || log_fail "Unexpected build number: $build_version"
    [[ "$executable_name" == "$EXECUTABLE_NAME" ]] || log_fail "Unexpected executable name: $executable_name"

    log_pass "Bundle metadata matches the release config"
}

verify_universal_binary() {
    log_step "Verifying universal app binary"
    local archs
    archs="$(lipo -archs "$APP_EXECUTABLE")"

    [[ "$archs" == *"arm64"* ]] || log_fail "Universal binary is missing arm64: $archs"
    [[ "$archs" == *"x86_64"* ]] || log_fail "Universal binary is missing x86_64: $archs"

    log_pass "Universal binary contains arm64 and x86_64"
}

collect_nested_code() {
    mapfile -t NESTED_CODE_OBJECTS < <(
        find "$APP_PATH/Contents" \
            \( -name '*.app' -o -name '*.appex' -o -name '*.xpc' -o -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) \
            -print \
            | awk -F/ '{ print NF ":" $0 }' \
            | sort -rn \
            | cut -d: -f2-
    )
}

sign_nested_code() {
    log_step "Signing nested frameworks and helper code"
    collect_nested_code
    if [[ "${#NESTED_CODE_OBJECTS[@]}" -eq 0 ]]; then
        log_warn "No nested code objects found under $APP_PATH"
        return
    fi

    local code_path
    for code_path in "${NESTED_CODE_OBJECTS[@]}"; do
        codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION_CERT" "$code_path"
        codesign --verify --strict --verbose=2 "$code_path"
    done

    log_pass "Nested code signing verified"
}

sign_app() {
    log_step "Signing app bundle with hardened runtime"
    xattr -cr "$APP_PATH" || true
    codesign \
        --force \
        --timestamp \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$DEVELOPER_ID_APPLICATION_CERT" \
        "$APP_PATH"

    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    log_pass "App signing verified"
}

notarize() {
    local artifact_path="$1"
    local label="$2"
    log_step "Submitting $label for notarization"
    xcrun notarytool submit "$artifact_path" --wait "${NOTARY_ARGS[@]}"
    log_pass "$label notarization accepted"
}

staple_and_validate() {
    local artifact_path="$1"
    local label="$2"
    log_step "Stapling notarization ticket to $label"
    xcrun stapler staple "$artifact_path"
    xcrun stapler validate "$artifact_path"
    log_pass "$label staple validation succeeded"
}

gatekeeper_assess() {
    log_step "Running Gatekeeper assessment"
    spctl --assess --type execute --verbose=4 "$APP_PATH"
    if [[ -n "${FINAL_DMG_PATH:-}" ]]; then
        spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG_PATH"
    fi
    log_pass "Gatekeeper checks passed"
}

create_mountless_dmg() {
    local source_root="$1"
    local hybrid_base_path="$2"
    local output_dmg_path="$3"
    local hybrid_image_path="$hybrid_base_path"

    rm -f "$hybrid_base_path" "${hybrid_base_path}.dmg" "$output_dmg_path"

    if ! hdiutil makehybrid \
        -hfs \
        -hfs-volume-name "$APP_NAME" \
        -ov \
        -o "$hybrid_base_path" \
        "$source_root"; then
        return 1
    fi

    # makehybrid commonly appends .dmg to the requested output path.
    if [[ ! -f "$hybrid_image_path" && -f "${hybrid_base_path}.dmg" ]]; then
        hybrid_image_path="${hybrid_base_path}.dmg"
    fi

    if [[ ! -f "$hybrid_image_path" ]]; then
        log_warn "Mountless DMG fallback did not produce an intermediate image"
        return 1
    fi

    if ! hdiutil convert \
        "$hybrid_image_path" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$output_dmg_path"; then
        return 1
    fi

    rm -f "$hybrid_image_path"
    return 0
}

create_dmg() {
    local version_dir="$RELEASE_ROOT/$MARKETING_VERSION-$BUILD_NUMBER"
    local dmg_staging="$version_dir/dmg-root"
    local hybrid_base_path="$version_dir/$APP_NAME-$MARKETING_VERSION.cdr"
    FINAL_DMG_PATH="$version_dir/$APP_NAME-$MARKETING_VERSION.dmg"

    log_step "Creating DMG artifact"
    rm -rf "$version_dir"
    mkdir -p "$dmg_staging"
    ditto "$APP_PATH" "$dmg_staging/$APP_NAME.app"
    ln -s /Applications "$dmg_staging/Applications"

    if hdiutil create -volname "$APP_NAME" -srcfolder "$dmg_staging" -ov -format UDZO "$FINAL_DMG_PATH"; then
        log_pass "DMG created at $FINAL_DMG_PATH"
        return 0
    fi

    log_warn "Direct DMG creation failed, trying mountless fallback"
    if create_mountless_dmg "$dmg_staging" "$hybrid_base_path" "$FINAL_DMG_PATH"; then
        log_pass "DMG created at $FINAL_DMG_PATH"
        return 0
    fi

    log_warn "DMG creation failed, switching to ZIP fallback"
    FINAL_DMG_PATH=""
    return 1
}

sign_dmg() {
    log_step "Signing DMG container"
    codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION_CERT" "$FINAL_DMG_PATH"
    codesign --verify --strict --verbose=2 "$FINAL_DMG_PATH"
    log_pass "DMG signing verified"
}

create_zip_fallback() {
    local version_dir="$RELEASE_ROOT/$MARKETING_VERSION-$BUILD_NUMBER"
    FINAL_ZIP_PATH="$version_dir/$APP_NAME-$MARKETING_VERSION.zip"

    mkdir -p "$version_dir"
    log_step "Creating ZIP fallback artifact"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP_PATH"
    log_pass "ZIP created at $FINAL_ZIP_PATH"
}

create_app_notary_zip() {
    APP_NOTARY_ZIP_PATH="$RELEASE_ROOT/$APP_NAME-$MARKETING_VERSION-$BUILD_NUMBER-notarization.zip"
    log_step "Creating app ZIP for notarization submission"
    mkdir -p "$RELEASE_ROOT"
    rm -f "$APP_NOTARY_ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_NOTARY_ZIP_PATH"
    log_pass "App notarization ZIP created at $APP_NOTARY_ZIP_PATH"
}

main() {
    load_config
    resolve_notary_args
    preflight
    build_release
    verify_bundle_metadata
    verify_universal_binary
    sign_nested_code
    sign_app
    create_app_notary_zip
    notarize "$APP_NOTARY_ZIP_PATH" "app bundle ZIP"
    staple_and_validate "$APP_PATH" "app bundle"

    if create_dmg; then
        sign_dmg
        notarize "$FINAL_DMG_PATH" "DMG"
        staple_and_validate "$FINAL_DMG_PATH" "DMG"
    else
        create_zip_fallback
    fi

    gatekeeper_assess

    printf '\n'
    log_pass "Release pipeline completed"
    printf 'Version: %s (%s)\n' "$MARKETING_VERSION" "$BUILD_NUMBER"
    printf 'App: %s\n' "$APP_PATH"
    if [[ -n "${FINAL_DMG_PATH:-}" ]]; then
        printf 'Artifact: %s\n' "$FINAL_DMG_PATH"
    else
        printf 'Artifact: %s\n' "$FINAL_ZIP_PATH"
    fi
}

main "$@"
