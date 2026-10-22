#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=package-manager.sh
source "$script_dir/package-manager.sh"

if [ ! -f package.json ]; then
  echo "::error::No package.json found. The dependency updater expects a Node.js project."
  exit 1
fi

pm_ensure
pm_install
