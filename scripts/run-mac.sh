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

mkdir -p "${module_cache_path}" "${clang_module_cache_path}"

export DEVELOPER_DIR="${developer_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${module_cache_path}"
export CLANG_MODULE_CACHE_PATH="${clang_module_cache_path}"
export DRSHARE_STORAGE_ROOT="${DRSHARE_STORAGE_ROOT:-${repo_root}/.drshare-state}"

exec "${swift_bin}" run \
  --scratch-path "${scratch_path}" \
  DrShareMac \
  "$@"
