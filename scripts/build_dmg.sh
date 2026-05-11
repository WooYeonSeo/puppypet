#!/usr/bin/env bash
#
# 미서명(ad-hoc 사인) DMG 빌더.
#
# Developer ID 없이도 동작합니다. 받는 사람은 처음 한 번
#   System Settings → Privacy & Security → "Open Anyway"
# 또는 터미널에서
#   xattr -dr com.apple.quarantine /Applications/puppy.app
# 가 필요할 수 있습니다.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${SCHEME:-puppy}"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="build"
DD_DIR="${BUILD_DIR}/DerivedData"
STAGE_DIR="${BUILD_DIR}/dmg-stage"
DMG_PATH="${BUILD_DIR}/PuppyPet.dmg"
VOLNAME="PuppyPet"

echo "▸ clean build dir"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "▸ xcodebuild (${SCHEME}, ${CONFIG}, code-signing off)"
xcodebuild \
    -project puppy.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -derivedDataPath "${DD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build \
    | xcbeautify 2>/dev/null || \
xcodebuild \
    -project puppy.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -derivedDataPath "${DD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

APP_SRC="${DD_DIR}/Build/Products/${CONFIG}/${SCHEME}.app"
if [[ ! -d "${APP_SRC}" ]]; then
    echo "✘ build product not found at ${APP_SRC}" >&2
    exit 1
fi

echo "▸ ad-hoc sign (required for arm64 to launch)"
codesign --force --deep --sign - "${APP_SRC}"

echo "▸ stage for DMG"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_SRC}" "${STAGE_DIR}/"
ln -sf /Applications "${STAGE_DIR}/Applications"

echo "▸ hdiutil create"
rm -f "${DMG_PATH}"
hdiutil create \
    -volname "${VOLNAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

SIZE=$(du -h "${DMG_PATH}" | cut -f1)
echo ""
echo "✓ DMG built: ${DMG_PATH} (${SIZE})"
echo ""
echo "처음 여는 사람에게:"
echo "  1) DMG 마운트 → puppy.app을 Applications로 드래그"
echo "  2) 첫 실행 시 Gatekeeper 경고가 뜨면 우클릭 → 열기"
echo "     또는: xattr -dr com.apple.quarantine /Applications/puppy.app"
