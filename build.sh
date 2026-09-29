#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/cache
APP="$PWD/build/Work Lights.app"
mkdir -p "$APP/Contents/MacOS"
# Set the deployment target explicitly: never inherit the build host's OS.
for arch in arm64 x86_64; do
    xcrun swiftc -target "$arch-apple-macosx13.0" -module-cache-path build/cache \
        Sources/WorkLights.swift -o "build/WorkLights-$arch"
done
lipo -create build/WorkLights-arm64 build/WorkLights-x86_64 -output "$APP/Contents/MacOS/WorkLights"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>WorkLights</string>
<key>CFBundleIdentifier</key><string>org.worklights.app</string>
<key>CFBundleName</key><string>Work Lights</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSLocalNetworkUsageDescription</key><string>Discover the WiZ lights you choose and control your selected room.</string>
</dict></plist>
PLIST
# Finder metadata can be attached automatically in synced build folders.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
"$APP/Contents/MacOS/WorkLights" --self-test
printf 'Built %s\n' "$APP"
