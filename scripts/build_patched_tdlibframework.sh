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
  # TDLib's OpenSSL 3 EVP path is unstable for Telegram's embedded
  # "BEGIN RSA PUBLIC KEY". Force the legacy RSA PEM reader, which matches
  # the actual PEM type and avoids the crashy EVP flow on-device.
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

old_reader = """#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
  EVP_PKEY *rsa = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
#else
  auto rsa = PEM_read_bio_RSAPublicKey(bio, nullptr, nullptr, nullptr);
#endif
"""
new_reader = """  auto *rsa = PEM_read_bio_RSAPublicKey(bio, nullptr, nullptr, nullptr);
"""

old_scope_exit = """  SCOPE_EXIT {
#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
    EVP_PKEY_free(rsa);
#else
    RSA_free(rsa);
#endif
  };
"""
new_scope_exit = """  SCOPE_EXIT {
    RSA_free(rsa);
  };
"""

old_size_check = """#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
  if (!EVP_PKEY_is_a(rsa, "RSA")) {
    return Status::Error("Key is not an RSA key");
  }
  if (EVP_PKEY_size(rsa) != 256) {
    return Status::Error("EVP_PKEY_size != 256");
  }
#else
  if (RSA_size(rsa) != 256) {
    return Status::Error("RSA_size != 256");
  }
#endif
"""
new_size_check = """  if (RSA_size(rsa) != 256) {
    return Status::Error("RSA_size != 256");
  }
"""

old_bn_block = """#if OPENSSL_VERSION_NUMBER >= 0x30000000L && !defined(LIBRESSL_VERSION_NUMBER)
  BIGNUM *n_num = nullptr;
  BIGNUM *e_num = nullptr;

  int res = EVP_PKEY_get_bn_param(rsa, "n", &n_num);
  CHECK(res == 1 && n_num != nullptr);
  res = EVP_PKEY_get_bn_param(rsa, "e", &e_num);
  CHECK(res == 1 && e_num != nullptr);

  auto n = static_cast<void *>(n_num);
  auto e = static_cast<void *>(e_num);
#else
  const BIGNUM *n_num;
  const BIGNUM *e_num;

#if OPENSSL_VERSION_NUMBER >= 0x10100000L
  RSA_get0_key(rsa, &n_num, &e_num, nullptr);
#else
  n_num = rsa->n;
  e_num = rsa->e;
#endif

  auto n = static_cast<void *>(BN_dup(n_num));
  auto e = static_cast<void *>(BN_dup(e_num));
  if (n == nullptr || e == nullptr) {
    return Status::Error("Cannot dup BIGNUM");
  }
#endif
"""
new_bn_block = """  const BIGNUM *n_num;
  const BIGNUM *e_num;

#if OPENSSL_VERSION_NUMBER >= 0x10100000L || defined(LIBRESSL_VERSION_NUMBER)
  RSA_get0_key(rsa, &n_num, &e_num, nullptr);
#else
  n_num = rsa->n;
  e_num = rsa->e;
#endif

  auto n = static_cast<void *>(BN_dup(n_num));
  auto e = static_cast<void *>(BN_dup(e_num));
  if (n == nullptr || e == nullptr) {
    return Status::Error("Cannot dup BIGNUM");
  }
"""

if old_includes not in text:
    raise SystemExit("Could not find OpenSSL include block in td/td/mtproto/RSA.cpp")
if old_reader not in text:
    raise SystemExit("Could not find RSA PEM reader block in td/td/mtproto/RSA.cpp")
if old_scope_exit not in text:
    raise SystemExit("Could not find RSA free block in td/td/mtproto/RSA.cpp")
if old_size_check not in text:
    raise SystemExit("Could not find RSA size validation block in td/td/mtproto/RSA.cpp")
if old_bn_block not in text:
    raise SystemExit("Could not find RSA BIGNUM extraction block in td/td/mtproto/RSA.cpp")

text = text.replace(old_includes, new_includes, 1)
text = text.replace(old_reader, new_reader, 1)
text = text.replace(old_scope_exit, new_scope_exit, 1)
text = text.replace(old_size_check, new_size_check, 1)
text = text.replace(old_bn_block, new_bn_block, 1)
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
