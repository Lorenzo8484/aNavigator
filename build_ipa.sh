#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$PROJECT_DIR/build"
CLANG="/usr/bin/clang-19"
LLD="/usr/bin/ld64.lld-19"

VERSION="${1:-1.0}"
SDK="${SDK:-/home/alina/sdk/iPhoneOS16.5.sdk}"

echo "🔨 Building aNavigator v$VERSION..."
echo "   SDK: $SDK"

# Aggiorna versione in src/Info.plist per backup corretti
python3 -c "
import plistlib
path = '$SRC_DIR/Info.plist'
with open(path, 'rb') as f:
    pl = plistlib.load(f)
pl['CFBundleShortVersionString'] = '$VERSION'
pl['CFBundleVersion'] = '$VERSION'
with open(path, 'wb') as f:
    plistlib.dump(pl, f)
"

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

# Copy lib/ files (MapLibre locale)
if [ -d "$SRC_DIR/lib" ]; then
    mkdir -p "$APP_DIR/lib"
    cp "$SRC_DIR/lib/"* "$APP_DIR/lib/" 2>/dev/null || true
fi

# Copy assets
if [ -d "$PROJECT_DIR/assets" ]; then
    mkdir -p "$APP_DIR/assets"
    cp "$PROJECT_DIR/assets"/*.png "$APP_DIR/assets/" 2>/dev/null || true
    cp "$PROJECT_DIR/assets"/*.usdz "$APP_DIR/assets/" 2>/dev/null || true
    cp "$PROJECT_DIR/assets"/*.glb "$APP_DIR/assets/" 2>/dev/null || true
    # Copy 3D models also to root for sceneNamed: to find them
    cp "$PROJECT_DIR/assets"/brisbane_city_bus.usdz "$APP_DIR/" 2>/dev/null || true
    cp "$PROJECT_DIR/assets"/*.png "$APP_DIR/" 2>/dev/null || true
fi

# Copy any .stile tiles if present
if [ -d "$SRC_DIR/tiles" ]; then
    cp -r "$SRC_DIR/tiles" "$APP_DIR/" 2>/dev/null || true
fi

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

echo "📂 Backup automatico in backup/v$VERSION/..."
BACKUP_DIR="$PROJECT_DIR/backup/v$VERSION"
mkdir -p "$BACKUP_DIR"
cp "$SRC_DIR"/*.m "$BACKUP_DIR/" 2>/dev/null || true
cp "$SRC_DIR"/*.mm "$BACKUP_DIR/" 2>/dev/null || true
cp "$SRC_DIR"/*.html "$BACKUP_DIR/" 2>/dev/null || true
cp "$SRC_DIR"/*.js "$BACKUP_DIR/" 2>/dev/null || true
cp "$SRC_DIR"/Info.plist "$BACKUP_DIR/" 2>/dev/null || true
echo "   Backup locale: $BACKUP_DIR"

echo "☁️  Push backup su GitHub..."
cd "$PROJECT_DIR"
git add "backup/v$VERSION/" 2>/dev/null || true
git commit -m "Backup v$VERSION" 2>/dev/null || echo "   Niente da committare"
git push origin main 2>/dev/null && echo "   ✅ GitHub push OK" || echo "   ⚠️ GitHub push fallito (rete?)"
echo "   ✅ Backup su GitHub completato!"
