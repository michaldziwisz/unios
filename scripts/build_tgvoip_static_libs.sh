#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TELEGRAM_IOS_URL="${TELEGRAM_IOS_URL:-https://github.com/TelegramMessenger/Telegram-iOS}"
TELEGRAM_IOS_REF="${TELEGRAM_IOS_REF:-7504a0f92694a3ccbb544e05f97304f8d0891ba9}"
WORK_DIR="${VOIP_WORK_DIR:-$ROOT_DIR/build/telegram-ios-voip}"
VENDOR_ROOT="${VOIP_VENDOR_ROOT:-$ROOT_DIR/Vendor/TgVoip}"
GENERATE_CONFIG_SCRIPT="$ROOT_DIR/scripts/generate_voip_engine_xcconfig.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "TgVoipWebrtc can only be built on macOS. Writing a disabled VoIP xcconfig instead."
  "$GENERATE_CONFIG_SCRIPT"
  exit 0
fi

if command -v bazelisk >/dev/null 2>&1; then
  BAZEL_BIN="$(command -v bazelisk)"
elif command -v bazel >/dev/null 2>&1; then
  BAZEL_BIN="$(command -v bazel)"
else
  echo "Neither bazelisk nor bazel was found in PATH." >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
git clone --depth 1 "$TELEGRAM_IOS_URL" "$WORK_DIR"
git -C "$WORK_DIR" fetch --depth 1 origin "$TELEGRAM_IOS_REF"
git -C "$WORK_DIR" checkout --detach "$TELEGRAM_IOS_REF"
git -C "$WORK_DIR" submodule update --init --depth 1 \
  build-system/bazel-rules/rules_apple \
  build-system/bazel-rules/rules_swift \
  build-system/bazel-rules/apple_support \
  build-system/bazel-rules/rules_xcodeproj \
  submodules/TgVoipWebrtc/tgcalls \
  third-party/webrtc/webrtc \
  third-party/libvpx/libvpx \
  third-party/dav1d/dav1d

rm -rf "$VENDOR_ROOT"
mkdir -p "$VENDOR_ROOT/lib/iphoneos" "$VENDOR_ROOT/lib/iphonesimulator" "$VENDOR_ROOT/include/TgVoipWebrtc"

copy_library() {
  local cpu="$1"
  local output_dir="$2"
  local library_path

  "$BAZEL_BIN" build --cpu="$cpu" //submodules/TgVoipWebrtc:TgVoipWebrtc
  library_path="$(find "$WORK_DIR/bazel-bin" -path '*submodules/TgVoipWebrtc*' -name 'libTgVoipWebrtc.a' -print -quit)"
  if [[ -z "$library_path" ]]; then
    echo "Unable to locate libTgVoipWebrtc.a for cpu=$cpu." >&2
    exit 1
  fi

  cp "$library_path" "$output_dir/libTgVoipWebrtc.a"
}

copy_library "ios_arm64" "$VENDOR_ROOT/lib/iphoneos"
copy_library "ios_sim_arm64" "$VENDOR_ROOT/lib/iphonesimulator"

cp "$WORK_DIR/submodules/TgVoipWebrtc/PublicHeaders/TgVoipWebrtc/"*.h "$VENDOR_ROOT/include/TgVoipWebrtc/"
cat > "$VENDOR_ROOT/include/TgVoipWebrtc/TgVoipWebrtc.h" <<'EOF'
#import <TgVoipWebrtc/OngoingCallThreadLocalContext.h>
#import <TgVoipWebrtc/MediaStreaming.h>
EOF
cat > "$VENDOR_ROOT/include/module.modulemap" <<'EOF'
module TgVoipWebrtc {
  umbrella header "TgVoipWebrtc/TgVoipWebrtc.h"
  export *
}
EOF

"$GENERATE_CONFIG_SCRIPT"
echo "Built TgVoipWebrtc static libraries into $VENDOR_ROOT."
