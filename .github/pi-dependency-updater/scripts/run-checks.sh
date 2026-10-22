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
bash "$script_dir/install-deps.sh"

has_script() {
  node -e '
    const pkg = require("./package.json");
    process.exit(pkg.scripts && pkg.scripts[process.argv[1]] ? 0 : 1);
  ' "$1"
}

if has_script test; then
  pm_run_script test
else
  echo "::warning::No test script found; skipping tests."
fi

for script in build lint; do
  if has_script "$script"; then
    pm_run_script "$script"
  fi
done
