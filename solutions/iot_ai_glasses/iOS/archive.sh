#!/bin/bash
set -e
cd "$(dirname "$0")"

PROJECT="IoTAIGlasses"
BUILD_DIR="build"

rm -rf "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR" "$BUILD_DIR/export"

xcodebuild archive \
    -workspace "$PROJECT.xcworkspace" \
    -scheme "$PROJECT" \
    -arch arm64 \
    -sdk iphoneos \
    -configuration Release \
    ENABLE_BITCODE=NO \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$PROJECT.xcarchive"

echo "====== archive success, exporting... ======"

xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$PROJECT.xcarchive" \
    -exportOptionsPlist "$PROJECT.plist" \
    -exportPath "$BUILD_DIR/export"

if [ ! -f "$BUILD_DIR/export/$PROJECT.ipa" ]; then
    echo "====== $PROJECT.ipa generated failed!!! ======"
    exit 1
fi

echo "====== $PROJECT.ipa has generated at $(pwd)/$BUILD_DIR/export/ ======"

cp "$BUILD_DIR/export/$PROJECT.ipa" ../
echo "====== $PROJECT.ipa copied to $(cd .. && pwd)/ ======"
