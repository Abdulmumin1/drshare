#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_root="${repo_root}/dist/DrShare.app"
install_root="/Applications/DrShare.app"

"${repo_root}/scripts/build-mac-app.sh"

rm -rf "${install_root}"
cp -R "${app_root}" "${install_root}"

echo "[drshare] Installed ${install_root}"
