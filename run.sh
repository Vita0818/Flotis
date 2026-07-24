#!/bin/bash
set -e

APP_BUNDLE_ID="com.Vita0818.FlotisMac"
APP_NAME="Flotis.app"

echo "🧹 Cleaning up old builds and TCC permissions..."
killall Flotis 2>/dev/null || true
rm -rf ~/Library/Developer/Xcode/DerivedData/Flotis-*
tccutil reset Accessibility $APP_BUNDLE_ID || true

echo "🛠 Generating and building project..."
xcodegen
xcodebuild -project Flotis.xcodeproj -scheme Flotis build | grep -v "not found"

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Flotis-*/Build/Products/Debug -name "Flotis.app" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Build failed, cannot find Flotis.app"
    exit 1
fi

echo "🚀 Opening $APP_PATH"
echo "⚠️ IMPORTANT: macOS will prompt for Accessibility permissions. Please grant them in System Settings."
open "$APP_PATH"
