#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${repo_root}/dist"
app_root="${dist_dir}/DrShare.app"
version="${APP_VERSION:-0.1.0}"
archive_name="DrShare-${version}-macOS.zip"
archive_path="${dist_dir}/${archive_name}"
checksum_path="${archive_path}.sha256"

"${repo_root}/scripts/build-mac-app.sh"

rm -f "${archive_path}" "${checksum_path}"
ditto -c -k --keepParent "${app_root}" "${archive_path}"
shasum -a 256 "${archive_path}" > "${checksum_path}"

echo "[drshare] Archived ${archive_path}"
echo "[drshare] Checksum ${checksum_path}"
