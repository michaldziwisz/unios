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
VOIP_COMMON_LDFLAGS = $(inherited) -ObjC -lc++ -lbz2 -liconv -lz -framework AudioToolbox -framework AVFoundation -framework CFNetwork -framework CoreAudio -framework CoreGraphics -framework CoreMedia -framework CoreTelephony -framework CoreVideo -framework GLKit -framework QuartzCore -framework Security -framework SystemConfiguration -framework VideoToolbox -weak_framework Metal -weak_framework Network
OTHER_LDFLAGS[sdk=iphoneos*] = $(VOIP_COMMON_LDFLAGS) -force_load "$(SRCROOT)/Vendor/TgVoip/lib/iphoneos/libTgVoipWebrtc.a"
OTHER_LDFLAGS[sdk=iphonesimulator*] = $(VOIP_COMMON_LDFLAGS) -force_load "$(SRCROOT)/Vendor/TgVoip/lib/iphonesimulator/libTgVoipWebrtc.a"
EOF
else
  cat > "$OUTPUT_PATH" <<'EOF'
VOIP_ENGINE_ENABLED = NO
EOF
fi

echo "Wrote $(basename "$OUTPUT_PATH")."
