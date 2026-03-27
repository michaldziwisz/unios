#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TELEGRAM_IOS_URL="${TELEGRAM_IOS_URL:-https://github.com/TelegramMessenger/Telegram-iOS}"
TELEGRAM_IOS_REF="${TELEGRAM_IOS_REF:-7504a0f92694a3ccbb544e05f97304f8d0891ba9}"
TELEGRAM_BAZEL_VERSION="${TELEGRAM_BAZEL_VERSION:-8.4.2}"
WORK_DIR="${VOIP_WORK_DIR:-$ROOT_DIR/build/telegram-ios-voip}"
VENDOR_ROOT="${VOIP_VENDOR_ROOT:-$ROOT_DIR/Vendor/TgVoip}"
GENERATE_CONFIG_SCRIPT="$ROOT_DIR/scripts/generate_voip_engine_xcconfig.sh"

readonly ARCHIVE_DEPENDENCY_LABELS=(
  "//submodules/TgVoipWebrtc:TgVoipWebrtc"
  "//submodules/MtProtoKit:MtProtoKit"
  "//third-party/boringssl:crypto"
  "//third-party/boringssl:ssl"
  "//third-party/libyuv:libyuv"
  "//third-party/ogg:ogg"
  "//third-party/openh264:openh264"
  "//third-party/opusfile:opusfile"
  "//third-party/rnnoise:rnnoise"
  "//third-party/td:TdBinding"
  "//third-party/webrtc:webrtc"
  "//third-party/webrtc:webrtc_objc"
  "//third-party/webrtc/absl:absl"
  "//third-party/webrtc/crc32c:crc32c"
  "//third-party/webrtc/libsrtp:libsrtp"
  "//third-party/webrtc/pffft:pffft"
  "//third-party/webrtc/rnnoise:webrtc_rnnoise"
)

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
  build-system/bazel-rules/sourcekit-bazel-bsp \
  submodules/TgVoipWebrtc/tgcalls \
  third-party/td/td \
  third-party/webrtc/webrtc \
  third-party/libvpx/libvpx \
  third-party/dav1d/dav1d

mkdir -p "$WORK_DIR/build-input/configuration-repository/provisioning"
cat > "$WORK_DIR/build-input/configuration-repository/WORKSPACE" <<'EOF'
EOF
cat > "$WORK_DIR/build-input/configuration-repository/MODULE.bazel" <<'EOF'
module(
    name = "build_configuration",
)
EOF
cat > "$WORK_DIR/build-input/configuration-repository/BUILD" <<'EOF'
exports_files(["variables.bzl"])
EOF
cat > "$WORK_DIR/build-input/configuration-repository/variables.bzl" <<EOF
telegram_bazel_path = "$BAZEL_BIN"
telegram_use_xcode_managed_codesigning = True
telegram_bundle_id = "dev.unios.voip"
telegram_api_id = "0"
telegram_api_hash = ""
telegram_team_id = ""
telegram_app_center_id = "0"
telegram_is_internal_build = "true"
telegram_is_appstore_build = "false"
telegram_appstore_id = "0"
telegram_app_specific_url_scheme = "unios"
telegram_premium_iap_product_id = ""
telegram_aps_environment = ""
telegram_enable_siri = False
telegram_enable_icloud = False
telegram_enable_watch = True
EOF
cat > "$WORK_DIR/build-input/configuration-repository/provisioning/BUILD" <<'EOF'
exports_files([])
EOF
cat > "$WORK_DIR/build-input/bazel-${TELEGRAM_BAZEL_VERSION}-darwin-arm64" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export USE_BAZEL_VERSION="${TELEGRAM_BAZEL_VERSION}"
exec "$BAZEL_BIN" "\$@"
EOF
chmod +x "$WORK_DIR/build-input/bazel-${TELEGRAM_BAZEL_VERSION}-darwin-arm64"

rm -rf "$VENDOR_ROOT"
mkdir -p "$VENDOR_ROOT/lib/iphoneos" "$VENDOR_ROOT/lib/iphonesimulator" "$VENDOR_ROOT/include/TgVoipWebrtc"

platform_label_for_cpu() {
  local cpu="$1"

  case "$cpu" in
    ios_arm64)
      echo "@build_bazel_apple_support//platforms:ios_arm64"
      ;;
    ios_sim_arm64)
      echo "@build_bazel_apple_support//platforms:ios_sim_arm64"
      ;;
    *)
      echo "Unsupported TgVoipWebrtc target cpu=$cpu." >&2
      exit 1
      ;;
  esac
}

build_target_for_cpu() {
  local cpu="$1"
  local platform_label

  platform_label="$(platform_label_for_cpu "$cpu")"

  (
    cd "$WORK_DIR"
    USE_BAZEL_VERSION="$TELEGRAM_BAZEL_VERSION" "$BAZEL_BIN" build \
      --cpu="$cpu" \
      --platforms="$platform_label" \
      --objccopt=-Wno-deprecated-declarations \
      "${ARCHIVE_DEPENDENCY_LABELS[@]}"
  )
}

resolve_archive_path() {
  local archive_path="$1"
  local candidate
  local suffix="$archive_path"

  if [[ -f "$WORK_DIR/$archive_path" ]]; then
    printf '%s\n' "$WORK_DIR/$archive_path"
    return 0
  fi

  case "$archive_path" in
    bazel-out/*/bin/*)
      suffix="${archive_path#bazel-out/*/bin/}"
      candidate="$WORK_DIR/bazel-bin/$suffix"
      if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  candidate="$(find -L "$WORK_DIR/bazel-bin" -path "*/$suffix" -type f -print -quit)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

bundle_archives_for_cpu() {
  local cpu="$1"
  local output_dir="$2"
  local platform_label
  local archive_output="$output_dir/libTgVoipWebrtc.a"
  local -a archives=()
  local archive_path
  local resolved_path

  platform_label="$(platform_label_for_cpu "$cpu")"

  while IFS= read -r archive_path; do
    [[ "$archive_path" == *.a ]] || continue
    if ! resolved_path="$(resolve_archive_path "$archive_path")"; then
      echo "Skipping non-materialized archive path for $archive_path (cpu=$cpu)." >&2
      continue
    fi
    archives+=("$resolved_path")
  done < <(
    cd "$WORK_DIR"
    USE_BAZEL_VERSION="$TELEGRAM_BAZEL_VERSION" "$BAZEL_BIN" cquery \
      --cpu="$cpu" \
      --platforms="$platform_label" \
      "deps(//submodules/TgVoipWebrtc:TgVoipWebrtc)" \
      --output=files | sort -u
  )

  if [[ ${#archives[@]} -eq 0 ]]; then
    echo "Unable to locate transitive static archives for cpu=$cpu." >&2
    exit 1
  fi

  rm -f "$archive_output"
  /usr/bin/libtool -static -o "$archive_output" "${archives[@]}"
}

build_target_for_cpu "ios_arm64"
bundle_archives_for_cpu "ios_arm64" "$VENDOR_ROOT/lib/iphoneos"

build_target_for_cpu "ios_sim_arm64"
bundle_archives_for_cpu "ios_sim_arm64" "$VENDOR_ROOT/lib/iphonesimulator"

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
