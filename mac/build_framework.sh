#!/bin/sh -
# xcodebuild -version

# Check if --release flag is passed
RELEASE_MODE=false
if [ "$1" = "--release" ]; then
  RELEASE_MODE=true
fi

echo "🧹 Clearing caches before building framework..."

# Clear Xcode derived data for any OpenMultitouchSupport projects
echo "Clearing Xcode derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/OpenMultitouchSupport*

echo ""
echo "🔨 Building framework..."

xcodebuild build \
  -project "Framework/OpenMultitouchSupportXCF.xcodeproj" \
  -scheme "OpenMultitouchSupportXCF" \
  -destination "generic/platform=macOS" \
  -configuration Release \
  -derivedDataPath "Framework/build"

FRAMEWORK_PATH="Framework/build/Build/Products/Release/OpenMultitouchSupportXCF.framework"
lipo -archs ${FRAMEWORK_PATH}/OpenMultitouchSupportXCF

XC_FRAMEWORK_PATH="OpenMultitouchSupportXCF.xcframework"
if [ -e $XC_FRAMEWORK_PATH ]; then
  rm -rf $XC_FRAMEWORK_PATH
fi
xcodebuild -create-xcframework \
  -framework $FRAMEWORK_PATH \
  -output $XC_FRAMEWORK_PATH

echo "✅ Local XCFramework updated for development: $XC_FRAMEWORK_PATH"

# Only create zip and remove xcframework in release mode
if [ "$RELEASE_MODE" = true ]; then
  echo "📦 Creating release package..."
  XC_FRAMEWORK_ZIP_PATH="${XC_FRAMEWORK_PATH}.zip"
  if [ -e $XC_FRAMEWORK_ZIP_PATH ]; then
    rm -rf $XC_FRAMEWORK_ZIP_PATH
  fi

  zip -Xyr $XC_FRAMEWORK_ZIP_PATH $XC_FRAMEWORK_PATH
  ls -Slh $XC_FRAMEWORK_ZIP_PATH | awk '{print $5, $9}'
  rm -rf $XC_FRAMEWORK_PATH

  CHECKSUM=$(swift package compute-checksum $XC_FRAMEWORK_ZIP_PATH)
  echo "Checksum: ${CHECKSUM}"
else
  echo "🚀 Ready for local development! You can now press play in Xcode."
  echo "💡 Use './build_framework.sh --release' to create a release package."
fi
