#!/usr/bin/env bash
set -euo pipefail

# Detects the package manager used by the target repository and provides
# helpers for installing dependencies and running package scripts.
#
# Detection order:
#   1. PACKAGE_MANAGER_OVERRIDE / PACKAGE_MANAGER environment variable
#   2. packageManager field in package.json
#   3. Lockfile: pnpm-lock.yaml, yarn.lock, package-lock.json / npm-shrinkwrap.json
#   4. npm
#
# Pnpm and Yarn are provisioned with Corepack, which is bundled with Node.js.
# This keeps the package manager version aligned with packageManager when the
# target repo pins one.

pm_detect() {
  PM="${PACKAGE_MANAGER_OVERRIDE:-${PACKAGE_MANAGER:-}}"
  PM_VERSION="${PACKAGE_MANAGER_VERSION_OVERRIDE:-${PACKAGE_MANAGER_VERSION:-}}"
  PM_LOCKFILE=""
  PM_YARN_MAJOR=""

  local pkg_manager=""
  local pkg_version=""

  if [ -f package.json ]; then
    local pm_info=""
    pm_info="$(
      node -e '
        const fs = require("node:fs");
        try {
          const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
          if (!pkg.packageManager) process.exit(0);
          const raw = String(pkg.packageManager);
          const at = raw.indexOf("@");
          const name = at === -1 ? raw : raw.slice(0, at);
          const version = at === -1 ? "" : raw.slice(at + 1).split("+")[0];
          process.stdout.write(`${name}|${version}`);
        } catch {}
      ' 2>/dev/null || true
    )"

    if [ -n "$pm_info" ]; then
      IFS='|' read -r pkg_manager pkg_version <<< "$pm_info"
    fi
  fi

  if [ -z "$PM" ] && [ -n "$pkg_manager" ]; then
    case "$pkg_manager" in
      npm | pnpm | yarn)
        PM="$pkg_manager"
        if [ -z "$PM_VERSION" ]; then
          PM_VERSION="$pkg_version"
        fi
        ;;
      *)
        echo "::warning::Unsupported packageManager '$pkg_manager'; falling back to lockfile detection." >&2
        ;;
    esac
  fi

  if [ -n "$PM" ] && [ "$pkg_manager" = "$PM" ] && [ -z "$PM_VERSION" ]; then
    PM_VERSION="$pkg_version"
  fi

  if [ -z "$PM" ]; then
    if [ -f pnpm-lock.yaml ]; then
      PM="pnpm"
    elif [ -f yarn.lock ]; then
      PM="yarn"
    elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
      PM="npm"
    else
      PM="npm"
    fi
  fi

  case "$PM" in
    npm | pnpm | yarn) ;;
    *)
      echo "::error::Unsupported package manager '$PM'. Use npm, pnpm, or yarn." >&2
      exit 1
      ;;
  esac

  # packageManager may include a hash suffix, and users may write v9.15.0.
  PM_VERSION="${PM_VERSION#v}"
  PM_VERSION="${PM_VERSION%%+*}"

  if [ -z "$PM_VERSION" ]; then
    case "$PM" in
      npm)
        PM_VERSION="$(npm --version 2>/dev/null || true)"
        ;;
      pnpm)
        PM_VERSION="latest"
        ;;
      yarn)
        if [ -f .yarnrc.yml ] || [ -d .yarn/releases ]; then
          PM_VERSION="stable"
        else
          PM_VERSION="1.22.22"
        fi
        ;;
    esac
  fi

  if [ "$PM" = "yarn" ]; then
    case "$PM_VERSION" in
      1 | 1.*) PM_YARN_MAJOR="1" ;;
      *) PM_YARN_MAJOR="berry" ;;
    esac
  fi

  case "$PM" in
    npm)
      if [ -f npm-shrinkwrap.json ]; then
        PM_LOCKFILE="npm-shrinkwrap.json"
      elif [ -f package-lock.json ]; then
        PM_LOCKFILE="package-lock.json"
      fi
      ;;
    pnpm)
      if [ -f pnpm-lock.yaml ]; then
        PM_LOCKFILE="pnpm-lock.yaml"
      fi
      ;;
    yarn)
      if [ -f yarn.lock ]; then
        PM_LOCKFILE="yarn.lock"
      fi
      ;;
  esac

  local found=()
  if [ -f pnpm-lock.yaml ]; then found+=("pnpm-lock.yaml"); fi
  if [ -f yarn.lock ]; then found+=("yarn.lock"); fi
  if [ -f package-lock.json ]; then found+=("package-lock.json"); fi
  if [ -f npm-shrinkwrap.json ]; then found+=("npm-shrinkwrap.json"); fi
  if [ "${#found[@]}" -gt 1 ]; then
    echo "::warning::Multiple lockfiles found (${found[*]}); using $PM with ${PM_LOCKFILE:-no lockfile}." >&2
  fi

  pm_set_command_vars
}

pm_set_command_vars() {
  case "$PM" in
    npm)
      PM_CI_COMMAND="npm ci --no-audit --no-fund"
      PM_INSTALL_COMMAND="npm install --no-audit --no-fund"
      PM_VERSION_DISCOVERY="Run \`npm outdated --json || true\` to collect current, wanted, and latest versions. Use \`npm view <package> versions --json\` for details."
      PM_ADD_COMMAND="npm install <package>@<version> --save-exact"
      PM_ADD_DEV_COMMAND="npm install <package>@<version> --save-exact --save-dev"
      ;;
    pnpm)
      PM_CI_COMMAND="pnpm install --frozen-lockfile"
      PM_INSTALL_COMMAND="pnpm install"
      PM_VERSION_DISCOVERY="Run \`pnpm outdated --format json || true\` to collect current, wanted, and latest versions. Use \`pnpm view <package> versions --json\` for details."
      PM_ADD_COMMAND="pnpm add <package>@<version> --save-exact"
      PM_ADD_DEV_COMMAND="pnpm add -D <package>@<version> --save-exact"
      ;;
    yarn)
      if [ "$PM_YARN_MAJOR" = "1" ]; then
        PM_CI_COMMAND="yarn install --frozen-lockfile"
        PM_INSTALL_COMMAND="yarn install"
        PM_VERSION_DISCOVERY="Run \`yarn outdated --json || true\` to collect current, wanted, and latest versions. Use \`yarn info <package> versions --json\` for details."
        PM_ADD_COMMAND="yarn add <package>@<version> --exact"
        PM_ADD_DEV_COMMAND="yarn add <package>@<version> --exact --dev"
      else
        PM_CI_COMMAND="yarn install --immutable"
        PM_INSTALL_COMMAND="yarn install"
        PM_VERSION_DISCOVERY="Yarn Berry has no built-in \`outdated\` command. For each direct dependency, run \`yarn npm info <package> --json\` and compare its available versions with the version in \`package.json\`."
        PM_ADD_COMMAND="yarn add <package>@<version> --exact"
        PM_ADD_DEV_COMMAND="yarn add <package>@<version> --exact --dev"
      fi
      ;;
  esac
}

pm_export_env() {
  export PACKAGE_MANAGER="$PM"
  export PACKAGE_MANAGER_VERSION="$PM_VERSION"
  export PACKAGE_MANAGER_LOCKFILE="$PM_LOCKFILE"
  export PACKAGE_MANAGER_YARN_MAJOR="$PM_YARN_MAJOR"
  export PACKAGE_MANAGER_CI_COMMAND="$PM_CI_COMMAND"
  export PACKAGE_MANAGER_INSTALL_COMMAND="$PM_INSTALL_COMMAND"
  export PACKAGE_MANAGER_VERSION_DISCOVERY="$PM_VERSION_DISCOVERY"
  export PACKAGE_MANAGER_ADD_COMMAND="$PM_ADD_COMMAND"
  export PACKAGE_MANAGER_ADD_DEV_COMMAND="$PM_ADD_DEV_COMMAND"

  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "PACKAGE_MANAGER=$PM"
      echo "PACKAGE_MANAGER_VERSION=$PM_VERSION"
      echo "PACKAGE_MANAGER_LOCKFILE=$PM_LOCKFILE"
      echo "PACKAGE_MANAGER_YARN_MAJOR=$PM_YARN_MAJOR"
      echo "PACKAGE_MANAGER_CI_COMMAND=$PM_CI_COMMAND"
      echo "PACKAGE_MANAGER_INSTALL_COMMAND=$PM_INSTALL_COMMAND"
      echo "PACKAGE_MANAGER_VERSION_DISCOVERY=$PM_VERSION_DISCOVERY"
      echo "PACKAGE_MANAGER_ADD_COMMAND=$PM_ADD_COMMAND"
      echo "PACKAGE_MANAGER_ADD_DEV_COMMAND=$PM_ADD_DEV_COMMAND"
    } >> "$GITHUB_ENV"
  fi

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "manager=$PM"
      echo "version=$PM_VERSION"
      echo "lockfile=$PM_LOCKFILE"
      echo "yarn_major=$PM_YARN_MAJOR"
    } >> "$GITHUB_OUTPUT"
  fi
}

pm_setup() {
  pm_detect

  if [ "$PM" = "npm" ]; then
    if ! command -v npm >/dev/null 2>&1; then
      echo "::error::npm is not available." >&2
      exit 1
    fi
    PM_VERSION="$(npm --version)"
    pm_set_command_vars
    pm_export_env
    echo "Using npm $PM_VERSION (lockfile: ${PM_LOCKFILE:-none})."
    return 0
  fi

  if ! command -v corepack >/dev/null 2>&1; then
    echo "::error::corepack is required to set up $PM. It is bundled with Node.js; enable it or install $PM manually." >&2
    exit 1
  fi

  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  local spec="$PM"
  if [ -n "$PM_VERSION" ]; then
    spec="$PM@$PM_VERSION"
  fi

  echo "Preparing $spec with corepack..."
  corepack prepare "$spec" --activate

  local shim_dir
  if [ -n "${RUNNER_TEMP:-}" ]; then
    shim_dir="$RUNNER_TEMP/corepack-bin"
  else
    shim_dir="$(mktemp -d)"
  fi
  mkdir -p "$shim_dir"
  corepack enable --install-directory "$shim_dir" "$PM"
  export PATH="$shim_dir:$PATH"
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$shim_dir" >> "$GITHUB_PATH"
  fi

  if ! command -v "$PM" >/dev/null 2>&1; then
    echo "::error::Failed to make $PM available on PATH." >&2
    exit 1
  fi

  PM_VERSION="$("$PM" --version)"
  pm_set_command_vars
  pm_export_env
  echo "Using $PM $PM_VERSION (lockfile: ${PM_LOCKFILE:-none})."
}

pm_ensure() {
  pm_detect

  if [ "$PM" = "npm" ]; then
    if ! command -v npm >/dev/null 2>&1; then
      echo "::error::npm is not available." >&2
      exit 1
    fi
    PM_VERSION="$(npm --version)"
    pm_set_command_vars
    pm_export_env
    return 0
  fi

  # The workflow setup step already prepared the manager and put its shim on
  # PATH. Avoid downloading it again when this script is sourced later.
  if [ "${PACKAGE_MANAGER:-}" = "$PM" ] && command -v "$PM" >/dev/null 2>&1; then
    pm_set_command_vars
    pm_export_env
    return 0
  fi

  pm_setup
}

pm_install() {
  pm_detect

  case "$PM" in
    npm)
      if [ -n "$PM_LOCKFILE" ]; then
        echo "Installing with npm ci (lockfile: $PM_LOCKFILE)."
        npm ci --no-audit --no-fund
      else
        echo "No npm lockfile found; installing with npm install."
        npm install --no-audit --no-fund
      fi
      ;;
    pnpm)
      if [ -n "$PM_LOCKFILE" ]; then
        echo "Installing with pnpm (lockfile: $PM_LOCKFILE)."
        pnpm install --frozen-lockfile
      else
        echo "No pnpm-lock.yaml found; installing with pnpm install."
        pnpm install
      fi
      ;;
    yarn)
      if [ "$PM_YARN_MAJOR" = "1" ]; then
        if [ -n "$PM_LOCKFILE" ]; then
          echo "Installing with Yarn Classic (lockfile: $PM_LOCKFILE)."
          yarn install --frozen-lockfile
        else
          echo "No yarn.lock found; installing with yarn install."
          yarn install
        fi
      else
        if [ -n "$PM_LOCKFILE" ]; then
          echo "Installing with Yarn Berry (lockfile: $PM_LOCKFILE)."
          yarn install --immutable
        else
          echo "No yarn.lock found; installing with yarn install."
          yarn install
        fi
      fi
      ;;
  esac
}

pm_run_script() {
  local script="$1"

  case "$PM" in
    npm)
      if [ "$script" = "test" ]; then
        npm test
      else
        npm run "$script"
      fi
      ;;
    pnpm)
      pnpm run "$script"
      ;;
    yarn)
      yarn run "$script"
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    detect)
      pm_detect
      echo "$PM"
      ;;
    setup)
      pm_setup
      ;;
    install)
      pm_ensure
      pm_install
      ;;
    run)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Usage: $0 run <script>" >&2
        exit 2
      fi
      pm_ensure
      pm_run_script "$1"
      ;;
    *)
      echo "Usage: $0 {detect|setup|install|run <script>}" >&2
      exit 2
      ;;
  esac
fi
