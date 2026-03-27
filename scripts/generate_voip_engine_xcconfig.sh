#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Config/VoIPEngine.xcconfig}"
VENDOR_ROOT="${VOIP_VENDOR_ROOT:-$ROOT_DIR/Vendor/TgVoip}"
INCLUDE_ROOT="$VENDOR_ROOT/include"
IOS_LIB_DIR="$VENDOR_ROOT/lib/iphoneos"
SIM_LIB_DIR="$VENDOR_ROOT/lib/iphonesimulator"
MODULE_MAP_PATH="$INCLUDE_ROOT/module.modulemap"
readonly LINK_ORDER=(
  "libTgVoipWebrtc.a"
  "libwebrtc_objc.a"
  "libTdBinding.a"
  "libMtProtoKit.a"
  "libwebrtc.a"
  "libwebrtc_rnnoise.a"
  "libtde2e.a"
  "libtdutils.a"
  "libavformat.a"
  "libavcodec.a"
  "libswresample.a"
  "libavutil.a"
  "libopusfile.a"
  "libogg.a"
  "librnnoise.a"
  "liblibyuv.a"
  "libVPX.a"
  "libopenh264.a"
  "libdav1d.a"
  "libpffft.a"
  "liblibsrtp.a"
  "libcrc32c.a"
  "libabsl.a"
  "libopus.a"
  "libssl.a"
  "libcrypto.a"
)

mkdir -p "$(dirname "$OUTPUT_PATH")"

srcroot_path_for() {
  local path="$1"

  if [[ "$path" != "$ROOT_DIR/"* ]]; then
    echo "Path $path is outside of repo root $ROOT_DIR." >&2
    exit 1
  fi

  printf '$(SRCROOT)/%s' "${path#"$ROOT_DIR/"}"
}

link_inputs_for_dir() {
  local dir="$1"
  local -a ordered_inputs=()
  local -a seen=()
  local archive_name
  local archive_path

  for archive_name in "${LINK_ORDER[@]}"; do
    archive_path="$dir/$archive_name"
    if [[ -f "$archive_path" ]]; then
      ordered_inputs+=("\"$(srcroot_path_for "$archive_path")\"")
      seen+=("$archive_name")
    fi
  done

  while IFS= read -r archive_path; do
    archive_name="$(basename "$archive_path")"
    if printf '%s\n' "${seen[@]}" | grep -Fxq "$archive_name"; then
      continue
    fi

    ordered_inputs+=("\"$(srcroot_path_for "$archive_path")\"")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.a' | sort)

  printf '%s' "${ordered_inputs[*]}"
}

has_static_archives() {
  local dir="$1"

  find "$dir" -maxdepth 1 -type f -name '*.a' -print -quit | grep -q .
}

if has_static_archives "$IOS_LIB_DIR" && has_static_archives "$SIM_LIB_DIR" && [[ -f "$MODULE_MAP_PATH" ]]; then
  IOS_LINK_INPUTS="$(link_inputs_for_dir "$IOS_LIB_DIR")"
  SIM_LINK_INPUTS="$(link_inputs_for_dir "$SIM_LIB_DIR")"

  cat > "$OUTPUT_PATH" <<EOF
VOIP_ENGINE_ENABLED = YES
HEADER_SEARCH_PATHS = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/include"
LIBRARY_SEARCH_PATHS[sdk=iphoneos*] = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/lib/iphoneos"
LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*] = \$(inherited) "\$(SRCROOT)/Vendor/TgVoip/lib/iphonesimulator"
VOIP_COMMON_LDFLAGS = \$(inherited) -ObjC -lc++ -lbz2 -liconv -lz -framework AudioToolbox -framework AVFoundation -framework CFNetwork -framework CoreAudio -framework CoreGraphics -framework CoreMedia -framework CoreTelephony -framework CoreVideo -framework GLKit -framework QuartzCore -framework Security -framework SystemConfiguration -framework VideoToolbox -weak_framework Metal -weak_framework Network
OTHER_LDFLAGS[sdk=iphoneos*] = \$(VOIP_COMMON_LDFLAGS) $IOS_LINK_INPUTS
OTHER_LDFLAGS[sdk=iphonesimulator*] = \$(VOIP_COMMON_LDFLAGS) $SIM_LINK_INPUTS
EOF
else
  cat > "$OUTPUT_PATH" <<'EOF'
VOIP_ENGINE_ENABLED = NO
EOF
fi

echo "Wrote $(basename "$OUTPUT_PATH")."
