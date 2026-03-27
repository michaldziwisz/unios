#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Config/VoIPEngine.xcconfig}"
VENDOR_ROOT="${VOIP_VENDOR_ROOT:-$ROOT_DIR/Vendor/TgVoip}"
INCLUDE_ROOT="$VENDOR_ROOT/include"
IOS_LIB_DIR="$VENDOR_ROOT/lib/iphoneos"
SIM_LIB_DIR="$VENDOR_ROOT/lib/iphonesimulator"
MODULE_MAP_PATH="$INCLUDE_ROOT/module.modulemap"

mkdir -p "$(dirname "$OUTPUT_PATH")"

srcroot_path_for() {
  local path="$1"

  if [[ "$path" != "$ROOT_DIR/"* ]]; then
    echo "Path $path is outside of repo root $ROOT_DIR." >&2
    exit 1
  fi

  printf '$(SRCROOT)/%s' "${path#"$ROOT_DIR/"}"
}

force_load_flags_for_dir() {
  local dir="$1"
  local -a flags=()
  local archive_path

  while IFS= read -r archive_path; do
    flags+=("-force_load \"$(srcroot_path_for "$archive_path")\"")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.a' | sort)

  printf '%s' "${flags[*]}"
}

has_static_archives() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f -name '*.a' -print -quit | grep -q .
}

if has_static_archives "$IOS_LIB_DIR" && has_static_archives "$SIM_LIB_DIR" && [[ -f "$MODULE_MAP_PATH" ]]; then
  IOS_FORCE_LOADS="$(force_load_flags_for_dir "$IOS_LIB_DIR")"
  SIM_FORCE_LOADS="$(force_load_flags_for_dir "$SIM_LIB_DIR")"

  cat > "$OUTPUT_PATH" <<EOF
VOIP_ENGINE_ENABLED = YES
HEADER_SEARCH_PATHS = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/include"
LIBRARY_SEARCH_PATHS[sdk=iphoneos*] = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/lib/iphoneos"
LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*] = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/lib/iphonesimulator"
VOIP_COMMON_LDFLAGS = \$(inherited) -ObjC -lc++ -lbz2 -liconv -lz -framework AudioToolbox -framework AVFoundation -framework CFNetwork -framework CoreAudio -framework CoreGraphics -framework CoreMedia -framework CoreTelephony -framework CoreVideo -framework GLKit -framework QuartzCore -framework Security -framework SystemConfiguration -framework VideoToolbox -weak_framework Metal -weak_framework Network
OTHER_LDFLAGS[sdk=iphoneos*] = \$(VOIP_COMMON_LDFLAGS) $IOS_FORCE_LOADS
OTHER_LDFLAGS[sdk=iphonesimulator*] = \$(VOIP_COMMON_LDFLAGS) $SIM_FORCE_LOADS
EOF
else
  cat > "$OUTPUT_PATH" <<'EOF'
VOIP_ENGINE_ENABLED = NO
EOF
fi

echo "Wrote $(basename "$OUTPUT_PATH")."
