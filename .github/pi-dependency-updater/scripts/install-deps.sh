#!/usr/bin/env bash
set -euo pipefail

if [ ! -f package.json ]; then
  echo "::error::No package.json found. The dependency updater expects a Node.js project."
  exit 1
fi

if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
  npm ci --no-audit --no-fund
else
  echo "No package-lock.json or npm-shrinkwrap.json found; using npm install."
  npm install --no-audit --no-fund
fi
