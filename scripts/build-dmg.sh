#!/bin/bash

# MeowOut One-Click DMG Builder
# ----------------------------

set -euo pipefail

APP_NAME="MeowOut"
BUILD_DIR=".build/dmg"
DERIVED_DATA=".build/derived_data"

# Architecture support: arm64, x86_64, or universal (default)
ARCH=${1:-"universal"}

# 架构白名单校验与产物命名映射
case "$ARCH" in
    arm64)
        BUILD_ARCHS="arm64"
        DMG_NAME="${APP_NAME}-arm64.dmg"
        ;;
    x86_64)
        BUILD_ARCHS="x86_64"
        DMG_NAME="${APP_NAME}-x86_64.dmg"
        ;;
    universal)
        BUILD_ARCHS="arm64 x86_64"
        DMG_NAME="${APP_NAME}.dmg"
        ;;
    *)
        echo "❌ Unsupported architecture: ${ARCH}. Supported: arm64, x86_64, universal"
        exit 1
        ;;
esac

echo "🚀 Starting build process for ${APP_NAME} (${ARCH})..."

# 1. Generate Xcode project and Build
if ! command -v xcodegen &> /dev/null; then
    echo "❌ xcodegen not found. Please install it via 'brew install xcodegen'."
    exit 1
fi

echo "📦 Generating Xcode project with XcodeGen..."
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "public let currentGitCommit = \"$COMMIT_HASH\"" > Sources/MeowOut/GitCommit.swift
xcodegen generate

echo "📦 Compiling in release mode with xcodebuild..."
rm -rf "${DERIVED_DATA}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

SIGN_FLAGS=(
    "CODE_SIGN_IDENTITY="
    "CODE_SIGNING_REQUIRED=NO"
    "CODE_SIGNING_ALLOWED=NO"
)

xcodebuild build \
    -scheme MeowOut \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    ARCHS="${BUILD_ARCHS}" \
    ONLY_ACTIVE_ARCH=NO \
    "${SIGN_FLAGS[@]}"

# 2. Locate and Copy App Bundle
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
echo "📀 Creating DMG disk image: ${DMG_NAME}..."
rm -f "${DMG_NAME}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${BUILD_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "✅ Done! Your DMG is ready: ${DMG_NAME}"
echo "💡 Architecture: ${ARCH}"
