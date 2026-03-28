#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/build/PatchedTDLibFrameworkSource"
OUTPUT_DIR="${ROOT_DIR}/Vendor/PatchedTDLibFramework"
TDLIBFRAMEWORK_TAG="${TDLIBFRAMEWORK_TAG:-1.8.62-af0cb1d3}"
TUIST_VERSION="${TUIST_VERSION:-4.10.2}"
PLATFORMS=("iOS" "iOS-simulator")

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required"
  exit 1
fi

if ! command -v gperf >/dev/null 2>&1; then
  echo "gperf is required"
  exit 1
fi

rm -rf "${WORK_DIR}" "${OUTPUT_DIR}/TDLibFramework.xcframework"
mkdir -p "${ROOT_DIR}/build" "${OUTPUT_DIR}"

git clone --depth 1 --branch "${TDLIBFRAMEWORK_TAG}" https://github.com/Swiftgram/TDLibFramework "${WORK_DIR}"
(
  cd "${WORK_DIR}"
  git submodule update --init --recursive
  # TDLib aborts on OpenSSL 3 when it parses Telegram's embedded "BEGIN RSA PUBLIC KEY"
  # with PEM_read_bio_PUBKEY. Patch in a fallback reader before building the framework.
  python3 - <<'PY'
from pathlib import Path

path = Path("td/td/mtproto/RSA.cpp")
text = path.read_text()

old_includes = """#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/opensslv.h>
#include <openssl/pem.h>
#if OPENSSL_VERSION_NUMBER < 0x30000000L || defined(LIBRESSL_VERSION_NUMBER)
#include <openssl/rsa.h>
#endif
"""
new_includes = """#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/opensslv.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>
"""

old_block = """#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
  EVP_PKEY *rsa = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
#else
  auto rsa = PEM_read_bio_RSAPublicKey(bio, nullptr, nullptr, nullptr);
#endif
"""
new_block = """#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
  EVP_PKEY *rsa = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
  if (rsa == nullptr) {
    BIO_reset(bio);
    auto *legacy_rsa = PEM_read_bio_RSAPublicKey(bio, nullptr, nullptr, nullptr);
    if (legacy_rsa != nullptr) {
      auto *legacy_wrapper = EVP_PKEY_new();
      if (legacy_wrapper == nullptr) {
        RSA_free(legacy_rsa);
        return Status::Error("Cannot create EVP_PKEY");
      }
      if (EVP_PKEY_assign_RSA(legacy_wrapper, legacy_rsa) != 1) {
        EVP_PKEY_free(legacy_wrapper);
        RSA_free(legacy_rsa);
        return Status::Error("Cannot assign RSA public key");
      }
      rsa = legacy_wrapper;
    }
  }
#else
  auto rsa = PEM_read_bio_RSAPublicKey(bio, nullptr, nullptr, nullptr);
#endif
"""

if old_includes not in text:
    raise SystemExit("Could not find OpenSSL include block in td/td/mtproto/RSA.cpp")
if old_block not in text:
    raise SystemExit("Could not find RSA PEM reader block in td/td/mtproto/RSA.cpp")

text = text.replace(old_includes, new_includes, 1)
text = text.replace(old_block, new_block, 1)
path.write_text(text)
PY

  (
    cd td
    git apply ../builder/tdlib-patches/build-openssl.patch
    git apply ../builder/tdlib-patches/Python-Apple-Support-patch.patch
  )

  cp builder/tdlib-patches/build.sh td/example/ios

  python3 - <<'PY'
from pathlib import Path

path = Path("td/example/ios/build.sh")
text = path.read_text()

old = """rm -rf build
mkdir -p build
cd build
"""
new = """mkdir -p build
cd build
"""

if old not in text:
    raise SystemExit("Could not find build directory reset block in td/example/ios/build.sh")

path.write_text(text.replace(old, new, 1))
PY

  (
    cd td
    rm -rf native-build
    mkdir native-build
    cd native-build
    cmake -DTD_GENERATE_SOURCE_FILES=ON ..
    cmake --build .
  )

  for platform in "${PLATFORMS[@]}"; do
    (
      cd td/example/ios
      ./build-openssl.sh "${platform}"
      ./build.sh "${platform}" "$(python3 ../../../scripts/extract_os_version.py "${platform}")"
    )
  done

  for platform in "${PLATFORMS[@]}"; do
    tdlib_static_lib="td/example/ios/build/install-${platform}/lib/libtdactor.a"
    if [[ ! -f "${tdlib_static_lib}" ]]; then
      echo "Expected TDLib static library is missing after build: ${tdlib_static_lib}"
      exit 1
    fi
  done

  (
    cd builder
    ./patch-headers.sh

    if ! command -v tuist >/dev/null 2>&1; then
      tuist_dir="${ROOT_DIR}/build/tools/tuist-${TUIST_VERSION}"
      rm -rf "${tuist_dir}"
      mkdir -p "${tuist_dir}"
      curl -L "https://github.com/tuist/tuist/releases/download/${TUIST_VERSION}/tuist.zip" -o "${tuist_dir}/tuist.zip"
      unzip -q "${tuist_dir}/tuist.zip" -d "${tuist_dir}"
      chmod +x "${tuist_dir}/tuist"
      export PATH="${tuist_dir}:${PATH}"
    fi

    TUIST_PLATFORM="iOS,iOS-simulator" tuist generate
    ./build-framework.sh iOS
    ./build-framework.sh iOS-simulator
    ./merge-frameworks.sh "iOS iOS-simulator"
  )
)

cp -R "${WORK_DIR}/builder/build/TDLibFramework.xcframework" "${OUTPUT_DIR}/TDLibFramework.xcframework"
