#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SRC_DIR="$PROJECT_DIR/scenekit-italy"
BUILD_DIR="$PROJECT_DIR/build"
CLANG="/usr/bin/clang-19"
LLD="/usr/bin/ld64.lld-19"

VERSION="${1:-1.0}"
SDK="${SDK:-/home/alina/sdk/iPhoneOS16.5.sdk}"

echo "🔨 Building scenekit-italy v$VERSION..."
echo "   SDK: $SDK"

BUILD_TMP=$(mktemp -d)
OBJ_DIR="$BUILD_TMP/objects"
APP_DIR="$BUILD_TMP/scenekit-italy.app"
mkdir -p "$OBJ_DIR" "$APP_DIR"

# Compiler flags (same approach as aNavigator)
CFLAGS=(\
  -target arm64-apple-ios14.0 \
  -isysroot "$SDK" \
  -iframework "$SDK/System/Library/Frameworks" \
  -fobjc-arc -fno-modules -fvisibility=hidden \
  -x objective-c++ -std=c++17 -O2 \
  -I"$SRC_DIR" \
  -I"$SRC_DIR/Scene3DEngine" \
  -c)

echo "📦 Compiling sources..."
cd "$OBJ_DIR"

for f in "AppDelegate.m" "main.m" "Map3DViewController.mm" \
         "Scene3DEngine/TileManager.mm" \
         "Scene3DEngine/CameraController.mm" \
         "Scene3DEngine/TextureAtlas.mm"; do
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
  -framework SceneKit \
  -framework ModelIO \
  -framework SpriteKit \
  *.o \
  -o "$APP_DIR/scenekit-italy"

echo "📱 Creating .app bundle..."
cp "$SRC_DIR/Info.plist" "$APP_DIR/"

# Copy .stile tile files from preprocessor output
TILES_SRC="$PROJECT_DIR/../preprocessor/output/tiles"
if [ -d "$TILES_SRC" ]; then
    echo "📁 Copying tile files..."
    mkdir -p "$APP_DIR/tiles"
    cp "$TILES_SRC"/*.stile "$APP_DIR/tiles/" 2>/dev/null || true
    echo "   $(ls -1 "$APP_DIR/tiles/"*.stile 2>/dev/null | wc -l) tiles copied"
fi
# Also copy tiles to app root for easy access
cp "$APP_DIR/tiles/"*.stile "$APP_DIR/" 2>/dev/null || true

# Copy textures from preprocessor output
TEXTURES_SRC="$PROJECT_DIR/../preprocessor/output/textures"
if [ -d "$TEXTURES_SRC" ]; then
    echo "📁 Copying texture files..."
    mkdir -p "$APP_DIR/textures"
    cp "$TEXTURES_SRC"/*.png "$APP_DIR/textures/" 2>/dev/null || true
    cp "$TEXTURES_SRC"/*.png "$APP_DIR/" 2>/dev/null || true
    echo "   $(ls -1 "$APP_DIR/textures/"*.png 2>/dev/null | wc -l) textures copied"
fi

# Also try assets/textures directory
ASSETS_TEXTURES="$PROJECT_DIR/../assets/textures"
if [ -d "$ASSETS_TEXTURES" ]; then
    echo "📁 Copying from assets/textures..."
    cp "$ASSETS_TEXTURES"/*.png "$APP_DIR/textures/" 2>/dev/null || true
    cp "$ASSETS_TEXTURES"/*.png "$APP_DIR/" 2>/dev/null || true
fi

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Info.plist" 2>/dev/null || true
plutil -replace CFBundleVersion -string "$VERSION" "$APP_DIR/Info.plist" 2>/dev/null || true

echo "📦 Creating IPA..."
mkdir -p "$BUILD_DIR" "$BUILD_TMP/Payload"
cp -R "$APP_DIR" "$BUILD_TMP/Payload/"
cd "$BUILD_TMP"
python3 <<PYEOF
import zipfile, os
ipa_path = "$BUILD_DIR/scenekit-italy_v$VERSION.ipa"
with zipfile.ZipFile(ipa_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk("Payload"):
        for f in files:
            filepath = os.path.join(root, f)
            zf.write(filepath, filepath)
print("IPA creata:", ipa_path)
PYEOF

rm -rf "$BUILD_TMP"

echo "✅ Build completata!"
echo "   IPA: $BUILD_DIR/scenekit-italy_v$VERSION.ipa"
ls -lh "$BUILD_DIR/scenekit-italy_v$VERSION.ipa"
