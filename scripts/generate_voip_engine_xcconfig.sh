#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Config/VoIPEngine.xcconfig}"
VENDOR_ROOT="${VOIP_VENDOR_ROOT:-$ROOT_DIR/Vendor/TgVoip}"
INCLUDE_ROOT="$VENDOR_ROOT/include"
IOS_LIB_PATH="$VENDOR_ROOT/lib/iphoneos/libTgVoipWebrtc.a"
SIM_LIB_PATH="$VENDOR_ROOT/lib/iphonesimulator/libTgVoipWebrtc.a"
MODULE_MAP_PATH="$INCLUDE_ROOT/module.modulemap"

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ -f "$IOS_LIB_PATH" && -f "$SIM_LIB_PATH" && -f "$MODULE_MAP_PATH" ]]; then
  cat > "$OUTPUT_PATH" <<'EOF'
VOIP_ENGINE_ENABLED = YES
HEADER_SEARCH_PATHS = $(inherited) "$(SRCROOT)/Vendor/TgVoip/include"
LIBRARY_SEARCH_PATHS[sdk=iphoneos*] = $(inherited) "$(SRCROOT)/Vendor/TgVoip/lib/iphoneos"
LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*] = $(inherited) "$(SRCROOT)/Vendor/TgVoip/lib/iphonesimulator"
OTHER_LDFLAGS = $(inherited) -lTgVoipWebrtc -lc++ -lz -framework AudioToolbox -framework VideoToolbox -framework CoreTelephony -framework CoreMedia -framework GLKit -framework AVFoundation
EOF
else
  cat > "$OUTPUT_PATH" <<'EOF'
VOIP_ENGINE_ENABLED = NO
EOF
fi

echo "Wrote $(basename "$OUTPUT_PATH")."
