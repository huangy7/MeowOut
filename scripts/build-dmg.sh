#!/bin/bash

# MeowOut One-Click DMG Builder
# ----------------------------

APP_NAME="MeowOut"
BUILD_DIR=".build/dmg"
DERIVED_DATA=".build/derived_data"

# Architecture support: arm64, x86_64, or universal (default)
ARCH=${1:-"universal"}

echo "🚀 Starting build process for ${APP_NAME} (${ARCH})..."

# 1. Generate Xcode project and Build
echo "📦 Generating Xcode project with XcodeGen..."
xcodegen generate

echo "📦 Compiling in release mode with xcodebuild..."
rm -rf "${DERIVED_DATA}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

if [ "$ARCH" == "arm64" ]; then
    xcodebuild build -scheme MeowOut -configuration Release -derivedDataPath "${DERIVED_DATA}" ARCHS="arm64" ONLY_ACTIVE_ARCH=NO
elif [ "$ARCH" == "x86_64" ]; then
    xcodebuild build -scheme MeowOut -configuration Release -derivedDataPath "${DERIVED_DATA}" ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO
else
    xcodebuild build -scheme MeowOut -configuration Release -derivedDataPath "${DERIVED_DATA}" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO
fi

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# 2. Locate and Copy App Bundle
# Note: xcodebuild places the output in Build/Products/Release/
SRC_APP_PATH="${DERIVED_DATA}/Build/Products/Release/MeowOut.app"

if [ ! -d "${SRC_APP_PATH}" ]; then
    echo "❌ Could not find app bundle at ${SRC_APP_PATH}"
    exit 1
fi

echo "🚚 Copying app bundle..."
cp -R "${SRC_APP_PATH}" "${BUILD_DIR}/"

# 3. Create Applications Shortcut (For DMG)
echo "🔗 Creating Applications folder shortcut..."
ln -s /Applications "${BUILD_DIR}/Applications"

# 4. Create DMG
echo "📀 Creating DMG disk image..."
rm -f "${APP_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" -srcfolder "${BUILD_DIR}" -ov -format UDZO "${APP_NAME}.dmg"

echo "✅ Done! Your DMG is ready: ${APP_NAME}.dmg"
echo "💡 Architecture: ${ARCH}"
