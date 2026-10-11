#!/bin/bash
# 书悦 ShuYue —— 无签名 IPA 构建脚本（本地与 CI 共用）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="ShuYue"
PROJECT="ShuYue.xcodeproj"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${VERSION##*.}"

echo "==> Building $SCHEME (unsigned) for iOS device, version $VERSION ($BUILD_NUMBER)"

mkdir -p build

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi

echo "==> Generating Xcode project from project.yml"
xcodegen generate --spec project.yml

echo "==> xcodebuild"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  SWIFT_COMPILATION_MODE=incremental \
  build > build/xcodebuild.log 2>&1 || {
    echo "xcodebuild FAILED — error lines:"
    grep -n "error:" build/xcodebuild.log | head -60 || true
    echo "--- last 40 lines ---"
    tail -40 build/xcodebuild.log
    exit 1
  }

APP="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "ERROR: .app not found in build products"
  exit 1
fi
echo "==> App bundle: $APP"

rm -rf build/unsigned
rm -f build/ShuYue-*.ipa
mkdir -p build/unsigned/Payload
cp -R "$APP" build/unsigned/Payload/
(cd build/unsigned && zip -qry "../ShuYue-v${VERSION}.ipa" Payload)

echo "==> IPA created: $PROJECT_DIR/build/ShuYue-v${VERSION}.ipa"
ls -lh "build/ShuYue-v${VERSION}.ipa"