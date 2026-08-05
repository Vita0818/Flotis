#!/bin/bash
set -euo pipefail

FLOTIS_TEMP_ROOT="${TMPDIR:-/tmp}"
DERIVED_DATA_PATH="${FLOTIS_TEMP_ROOT%/}/FlotisRunDerivedData"

echo "🧹 Closing the previous Flotis process..."
killall Flotis 2>/dev/null || true

echo "🛠 Generating and building project..."
xcodegen generate
xcodebuild \
  -project Flotis.xcodeproj \
  -scheme Flotis \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build | grep -v "not found"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Flotis.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed, cannot find Flotis.app"
    exit 1
fi

echo "🚀 Opening $APP_PATH"
if codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -q "Signature=adhoc"; then
    echo "⚠️ This Debug build is ad-hoc signed. Accessibility approval may change after a rebuild."
    echo "   Select an Apple Development team in Xcode to keep a stable TCC identity."
fi
open "$APP_PATH"
