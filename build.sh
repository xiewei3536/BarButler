#!/bin/bash
# BarButler 一鍵建置:Universal Binary → .app（含 Sparkle 自動更新）→ .dmg
# CI 用法:VERSION=1.2.3 bash build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="BarButler"
VERSION="${VERSION:-1.2.0}"
BUNDLE_ID="com.bowei.barbutler"
DIST="dist"
FEED_URL="https://raw.githubusercontent.com/xiewei3536/BarButler/main/appcast.xml"
ED_PUBLIC_KEY="Cc2juUNzCKlh6jINBZb2TJOmZCVscTQuO87AfdbSiGA="

echo "▸ 編譯 Universal Binary (x86_64 + arm64)…  版本 $VERSION"
rm -rf "$DIST"
mkdir -p "$DIST"

if swift build -c release --arch x86_64 --arch arm64 2>/dev/null; then
    UNIVERSAL="$(swift build -c release --arch x86_64 --arch arm64 --show-bin-path)/$APP"
else
    echo "  （合併模式不支援，改用分別編譯 + lipo）"
    swift build -c release --triple x86_64-apple-macosx
    BIN_X86="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)/$APP"
    swift build -c release --triple arm64-apple-macosx
    BIN_ARM="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)/$APP"
    UNIVERSAL="$DIST/$APP-universal"
    lipo -create "$BIN_X86" "$BIN_ARM" -output "$UNIVERSAL"
fi
lipo -info "$UNIVERSAL"

echo "▸ 產生圖示…"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$DIST/icon_1024.png"
for SZ in 16 32 128 256 512; do
    sips -z $SZ $SZ "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
    DBL=$((SZ * 2))
    sips -z $DBL $DBL "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"

echo "▸ 組裝 $APP.app…"
BUNDLE="$DIST/$APP.app"
RES="$BUNDLE/Contents/Resources"
FRAMEWORKS="$BUNDLE/Contents/Frameworks"
mkdir -p "$BUNDLE/Contents/MacOS" "$RES" "$FRAMEWORKS"
cp "$UNIVERSAL" "$BUNDLE/Contents/MacOS/$APP"
cp "$DIST/AppIcon.icns" "$RES/"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

echo "▸ 嵌入 Sparkle.framework…"
SPARKLE_FRAMEWORK=$(find .build/artifacts -type d -name "Sparkle.framework" -path "*macos*" | head -1)
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUNDLE/Contents/MacOS/$APP" 2>/dev/null || true

# 本地化顯示名稱
declare -a LOCS=("en:BarButler" "zh-Hant:選單列管家" "zh-Hans:菜单栏管家")
for PAIR in "${LOCS[@]}"; do
    LOC="${PAIR%%:*}"; NAME="${PAIR#*:}"
    mkdir -p "$RES/$LOC.lproj"
    cat > "$RES/$LOC.lproj/InfoPlist.strings" <<EOF
CFBundleDisplayName = "$NAME";
CFBundleName = "$NAME";
EOF
done

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>LSHasLocalizedDisplayName</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Bowei</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$ED_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
PLIST

# 簽名身分:CI 以 SIGN_ID 傳入固定自簽憑證（保住輔助使用授權）；本機預設 ad-hoc
SIGN_ID="${SIGN_ID:--}"
echo "▸ 簽名（identity: $SIGN_ID）…"
codesign --force -s "$SIGN_ID" "$FRAMEWORKS/Sparkle.framework"
codesign --force --deep -s "$SIGN_ID" "$BUNDLE"
codesign --verify --deep "$BUNDLE" && echo "  簽名驗證通過"

echo "▸ 製作 DMG…"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -format UDZO -ov "$DIST/$APP.dmg" >/dev/null
rm -rf "$STAGE" "$ICONSET" "$DIST/icon_1024.png"

echo ""
echo "✅ 完成:"
echo "   $DIST/$APP.app   （可直接拖進「應用程式」）"
echo "   $DIST/$APP.dmg   （可分享給其他 Intel / Apple Silicon Mac）"
