#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_HOME="$ROOT_DIR/.tmp-home"
MODULE_CACHE="$ROOT_DIR/.build/ModuleCache.noindex"
SWIFT_BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
RUST_BUILD_DIR="$ROOT_DIR/rust/target/debug"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacTortoiseSVN"
LEGACY_APP_NAME="MacSVNWorkbench"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_INFO_PLIST="$ROOT_DIR/Apps/MacSVNApp/Info.plist"
APP_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNApp/MacSVNWorkbench.entitlements"
XPC_INFO_PLIST="$ROOT_DIR/Apps/MacSVNStatusService/Info.plist"
XPC_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNStatusService/MacSVNStatusService.entitlements"
XPC_BUNDLE_ID="com.morningstar.MacTortoiseSVN.StatusService"
XPC_BUNDLE="$APP_BUNDLE/Contents/XPCServices/$XPC_BUNDLE_ID.xpc"
FINDER_INFO_PLIST="$ROOT_DIR/Apps/MacSVNFinderSync/Info.plist"
FINDER_ENTITLEMENTS="$ROOT_DIR/Apps/MacSVNFinderSync/MacSVNFinderSync.entitlements"
FINDER_BUNDLE_ID="com.morningstar.MacTortoiseSVN.FinderSync"
FINDER_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$FINDER_BUNDLE_ID.appex"
WORKBENCH_EXECUTABLE="$SWIFT_BUILD_DIR/$APP_NAME"
WORKBENCH_RESOURCE_BUNDLE="$SWIFT_BUILD_DIR/MacTortoiseSVN_MacSVNWorkbench.bundle"
XPC_EXECUTABLE="$SWIFT_BUILD_DIR/MacSVNStatusXPCService"
FINDER_EXECUTABLE="$SWIFT_BUILD_DIR/MacSVNFinderSync"
QUICK_ACTIONS_EXECUTABLE="$SWIFT_BUILD_DIR/MacSVNQuickActions"
RUST_EXECUTABLE="$RUST_BUILD_DIR/mtsvn-rs"
ICONSET_DIR="$DIST_DIR/$APP_NAME.iconset"
ICON_FILE="$DIST_DIR/$APP_NAME.icns"
ICON_SOURCE="$ROOT_DIR/Sources/MacSVNWorkbench/Resources/MacTortoiseSVNIcon.png"

if [[ -n "${MACSVN_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$MACSVN_CODESIGN_IDENTITY"
else
    CODESIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Apple Development:/ { print $2; exit }'
    )"
    if [[ -z "$CODESIGN_IDENTITY" ]]; then
        CODESIGN_IDENTITY="-"
    fi
fi

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "warning: 使用 ad-hoc 签名（-）。每次重新构建后 macOS 会把它当成新应用，" >&2
    echo "warning: 桌面/文稿等文件夹的访问权限（TCC）会重新弹框。" >&2
    echo "warning: 建议安装 Apple Development 证书，或设置 MACSVN_CODESIGN_IDENTITY 指定稳定的签名身份。" >&2
fi

# Strip get-task-allow from entitlements for codesigning.
# This prevents debug-attach and avoids TCC re-prompting on ad-hoc signed builds.
strip_get_task_allow() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$dst" 2>/dev/null || true
}

STRIPPED_DIR="$DIST_DIR/.entitlements-stripped"
mkdir -p "$STRIPPED_DIR"
strip_get_task_allow "$APP_ENTITLEMENTS"    "$STRIPPED_DIR/App.entitlements"
strip_get_task_allow "$FINDER_ENTITLEMENTS" "$STRIPPED_DIR/Finder.entitlements"
strip_get_task_allow "$XPC_ENTITLEMENTS"    "$STRIPPED_DIR/XPC.entitlements"

mkdir -p "$BUILD_HOME" "$MODULE_CACHE" "$DIST_DIR"

if [[ ! -f "$ICON_SOURCE" ]]; then
    swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$ICON_SOURCE"
fi

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product "$APP_NAME"

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product MacSVNStatusXPCService

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product MacSVNFinderSync

env \
    HOME="$BUILD_HOME" \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build --product MacSVNQuickActions

(
    cd "$ROOT_DIR/rust"
    /opt/homebrew/bin/cargo build -q -p mtsvn-rs
)

rm -rf \
    "$APP_BUNDLE" \
    "$DIST_DIR/$LEGACY_APP_NAME.app" \
    "$ICONSET_DIR" \
    "$DIST_DIR/$LEGACY_APP_NAME.iconset" \
    "$ICON_FILE" \
    "$DIST_DIR/$LEGACY_APP_NAME.icns"

mkdir -p \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources/bin" \
    "$APP_BUNDLE/Contents/PlugIns" \
    "$APP_BUNDLE/Contents/XPCServices" \
    "$FINDER_BUNDLE/Contents/MacOS" \
    "$XPC_BUNDLE/Contents/MacOS" \
    "$XPC_BUNDLE/Contents/Resources/bin"

cp "$APP_INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$WORKBENCH_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$WORKBENCH_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
cp "$RUST_EXECUTABLE" "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs"
cp "$QUICK_ACTIONS_EXECUTABLE" "$APP_BUNDLE/Contents/Resources/bin/MacSVNQuickActions"
chmod +x \
    "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs" \
    "$APP_BUNDLE/Contents/Resources/bin/MacSVNQuickActions"

mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    retina_size=$((size * 2))
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z "$retina_size" "$retina_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"

cp "$FINDER_INFO_PLIST" "$FINDER_BUNDLE/Contents/Info.plist"
cp "$FINDER_EXECUTABLE" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
chmod +x "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"

cp "$XPC_INFO_PLIST" "$XPC_BUNDLE/Contents/Info.plist"
cp "$XPC_EXECUTABLE" "$XPC_BUNDLE/Contents/MacOS/MacSVNStatusXPCService"
cp "$RUST_EXECUTABLE" "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"
chmod +x \
    "$XPC_BUNDLE/Contents/MacOS/MacSVNStatusXPCService" \
    "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"

/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE/Contents/Resources/bin/mtsvn-rs"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE/Contents/Resources/bin/MacSVNQuickActions"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$XPC_BUNDLE/Contents/Resources/bin/mtsvn-rs"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$STRIPPED_DIR/Finder.entitlements" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --preserve-metadata=entitlements "$FINDER_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$STRIPPED_DIR/XPC.entitlements" "$XPC_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$STRIPPED_DIR/App.entitlements" "$APP_BUNDLE"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --generate-entitlement-der --entitlements "$STRIPPED_DIR/Finder.entitlements" "$FINDER_BUNDLE/Contents/MacOS/MacSVNFinderSync"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --preserve-metadata=entitlements "$FINDER_BUNDLE"

# Clean up temporary stripped entitlements
rm -rf "$STRIPPED_DIR"

echo "Built app bundle:"
echo "$APP_BUNDLE"
