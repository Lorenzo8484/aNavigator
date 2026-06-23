#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SRC_DIR="$PROJECT_DIR/anavigatore"
BUILD_DIR="$PROJECT_DIR/build"
CLANG="/usr/bin/clang-19"
LLD="/usr/bin/ld64.lld-19"

VERSION="${1:-1.0}"
SDK="${SDK:-/home/alina/sdk/iPhoneOS16.5.sdk}"

echo "🔨 Building aNavigator v$VERSION..."
echo "   SDK: $SDK"

BUILD_TMP=$(mktemp -d)
OBJ_DIR="$BUILD_TMP/objects"
APP_DIR="$BUILD_TMP/aNavigator.app"
mkdir -p "$OBJ_DIR" "$APP_DIR"

CFLAGS=(
  -target arm64-apple-ios14.0
  -isysroot "$SDK"
  -iframework "$SDK/System/Library/Frameworks"
  -fobjc-arc -fno-modules -fvisibility=hidden
  -x objective-c++ -std=c++17 -O2
  -I"$SRC_DIR"
  -c)

echo "📦 Compiling sources..."
cd "$OBJ_DIR"

for f in main.m AppDelegate.m \
         MapViewController.mm \
         SettingsViewController.mm \
         BusViewController.mm \
         SettingsStore.mm \
         LocalizationManager.mm; do
    echo "   $f"
    $CLANG "${CFLAGS[@]}" "$SRC_DIR/$f" -o "$(basename "${f%.*}").o"
done

echo "🔗 Linking..."
$LLD -demangle \
  -arch arm64 \
  -platform_version ios 14.0 16.5 \
  -syslibroot "$SDK" \
  -lobjc -lc++ -lc -lz \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -framework QuartzCore \
  -framework CoreLocation \
  -framework WebKit \
  -framework AVFoundation \
  -framework SceneKit \
  -framework ModelIO \
  *.o \
  -o "$APP_DIR/aNavigator"

echo "📱 Creating .app bundle..."
cp "$SRC_DIR/Info.plist" "$APP_DIR/"
cp "$SRC_DIR/map.html" "$APP_DIR/"

# Copy assets
if [ -d "$SRC_DIR/assets" ]; then
    cp -r "$SRC_DIR/assets" "$APP_DIR/"
fi

# Copy any .stile tiles if present
if [ -d "$SRC_DIR/tiles" ]; then
    cp -r "$SRC_DIR/tiles" "$APP_DIR/" 2>/dev/null || true
fi

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Info.plist" 2>/dev/null || true
plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Info.plist" 2>/dev/null || true

echo "📦 Creating IPA..."
mkdir -p "$BUILD_DIR" "$BUILD_TMP/Payload"
cp -R "$APP_DIR" "$BUILD_TMP/Payload/"
cd "$BUILD_TMP"
python3 <<PYEOF
import zipfile, os
ipa_path = "$BUILD_DIR/aNavigator_v$VERSION.ipa"
with zipfile.ZipFile(ipa_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk("Payload"):
        for f in files:
            filepath = os.path.join(root, f)
            zf.write(filepath, filepath)
print("IPA:", ipa_path)
PYEOF

rm -rf "$BUILD_TMP"

echo "✅ Build completata!"
echo "   IPA: $BUILD_DIR/aNavigator_v$VERSION.ipa"
ls -lh "$BUILD_DIR/aNavigator_v$VERSION.ipa"
