#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --release ) ]]; then
    echo "Usage: $0 [--release]" >&2; exit 2
fi
DERIVED="$ROOT/build/FrameworkDerivedData"
xcodebuild -project "$ROOT/Framework/OpenMultitouchSupportXCF.xcodeproj" -scheme OpenMultitouchSupportXCF -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" build
FRAMEWORK="$DERIVED/Build/Products/Release/OpenMultitouchSupportXCF.framework"
lipo -archs "$FRAMEWORK/OpenMultitouchSupportXCF"
STAGING="$(mktemp -d "$ROOT/build/xcframework.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$STAGING/OpenMultitouchSupportXCF.xcframework"
rm -rf "$ROOT/OpenMultitouchSupportXCF.xcframework"
mv "$STAGING/OpenMultitouchSupportXCF.xcframework" "$ROOT/"
if [[ "${1:-}" == --release ]]; then
    rm -f OpenMultitouchSupportXCF.xcframework.zip
    zip -Xyr OpenMultitouchSupportXCF.xcframework.zip OpenMultitouchSupportXCF.xcframework
    "$ROOT/checksum.sh"
fi
