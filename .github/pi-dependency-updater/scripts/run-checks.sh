#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/install-deps.sh"

has_script() {
  node -e '
    const pkg = require("./package.json");
    process.exit(pkg.scripts && pkg.scripts[process.argv[1]] ? 0 : 1);
  ' "$1"
}

if has_script test; then
  npm test
else
  echo "::warning::No npm test script found; skipping tests."
fi

for script in build lint; do
  if has_script "$script"; then
    npm run "$script"
  fi
done
