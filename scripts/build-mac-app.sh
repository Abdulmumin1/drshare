#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
default_developer_dir="$(xcode-select -p 2>/dev/null || true)"

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  developer_dir="${DEVELOPER_DIR}"
elif [[ "${default_developer_dir}" == "/Library/Developer/CommandLineTools" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  developer_dir="/Applications/Xcode.app/Contents/Developer"
else
  developer_dir="${default_developer_dir}"
fi

if [[ -z "${developer_dir}" ]] || [[ ! -x "${developer_dir}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
  echo "[drshare] Xcode Swift toolchain not found at ${developer_dir}" >&2
  echo "[drshare] Set DEVELOPER_DIR to your Xcode Developer directory and retry." >&2
  exit 1
fi

swift_bin="/usr/bin/swift"
swift_version="$(DEVELOPER_DIR="${developer_dir}" "${swift_bin}" --version | awk '/Apple Swift version/ { print $4; exit }')"

if [[ -z "${swift_version}" ]]; then
  echo "[drshare] Failed to determine the Xcode Swift version." >&2
  exit 1
fi

scratch_path="${repo_root}/.build/xcode-swift-${swift_version}"
module_cache_path="${scratch_path}/ModuleCache"
clang_module_cache_path="${scratch_path}/clang-module-cache"
release_dir="${scratch_path}/arm64-apple-macosx/release"
dist_dir="${repo_root}/dist"
app_name="DrShare"
bundle_name="${app_name}.app"
app_root="${dist_dir}/${bundle_name}"
contents_dir="${app_root}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
resource_bundle_name="drshare_DrShareWebAssets.bundle"
app_version="${APP_VERSION:-0.1.0}"
app_build="${APP_BUILD:-1}"

mkdir -p "${module_cache_path}" "${clang_module_cache_path}" "${dist_dir}"

export DEVELOPER_DIR="${developer_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_path}"
export CLANG_MODULE_CACHE_PATH="${clang_module_cache_path}"

"${swift_bin}" build \
  -c release \
  --scratch-path "${scratch_path}"

binary_path="$(find "${scratch_path}" -type f -path '*/release/DrShareMac' -print -quit)"
resource_bundle_path="$(find "${scratch_path}" -type d -path "*/release/${resource_bundle_name}" -print -quit)"

if [[ ! -x "${binary_path}" ]]; then
  echo "[drshare] Release binary not found at ${binary_path}" >&2
  exit 1
fi

if [[ ! -d "${resource_bundle_path}" ]]; then
  echo "[drshare] Resource bundle not found at ${resource_bundle_path}" >&2
  exit 1
fi

rm -rf "${app_root}"
mkdir -p "${macos_dir}" "${resources_dir}"

cp "${binary_path}" "${macos_dir}/DrShareMac"
cp -R "${resource_bundle_path}" "${resources_dir}/${resource_bundle_name}"

ln -sfn "Contents/Resources/${resource_bundle_name}" "${app_root}/${resource_bundle_name}"

cat > "${contents_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>DrShare</string>
  <key>CFBundleExecutable</key>
  <string>DrShareMac</string>
  <key>CFBundleIdentifier</key>
  <string>com.drshare.mac</string>
  <key>CFBundleName</key>
  <string>DrShare</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${app_version}</string>
  <key>CFBundleVersion</key>
  <string>${app_build}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  if ! codesign --force --deep --sign - "${app_root}" >/dev/null 2>&1; then
    echo "[drshare] warning: ad-hoc codesign failed, continuing with an unsigned app bundle" >&2
  fi
fi

echo "[drshare] Built ${app_root}"
