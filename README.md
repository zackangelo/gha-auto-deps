# gha-auto-deps-sample

A small Node.js project with a pi-powered GitHub Action that updates Node.js dependencies, runs the test suite, and opens a pull request with a report of what changed and what was skipped. The action auto-detects npm, pnpm, and Yarn.

The action uses the [`pi-mixlayer`](https://www.npmjs.com/package/pi-mixlayer) provider plugin. The Mixlayer API key and model are passed to pi through environment variables.

## What the workflow does

1. Checks out the repository, auto-detects npm/pnpm/Yarn, and installs dependencies with `install-deps.sh` (`npm ci`, `pnpm install --frozen-lockfile`, or the matching Yarn install when a lockfile exists).
2. Installs the pi coding agent and loads the `pi-mixlayer` extension for one run.
3. Renders a prompt from `.github/pi-dependency-updater/prompts/update-dependencies.md` using the workflow inputs.
4. Runs pi in non-interactive mode with the `mixlayer` provider.
5. Lets pi inspect `package.json` and the detected lockfile, apply the dependency policy, fix any test failures caused by the updates, run tests, and write a Markdown report.
6. Enforces the policy deterministically by comparing `package.json` against the base commit, then runs the project checks with `run-checks.sh` using the detected package manager (`test`, plus `build`/`lint` when those scripts exist).
7. If the check gate fails, runs a second pi repair pass with the captured test output and the report, then re-runs the policy check and checks. A failing test suite cannot produce a PR.
8. Commits the changes to a new branch and opens a PR with the `gh` CLI. The PR body includes the report, including every skipped update and the reason.

The workflow refuses to open a PR if pi committed changes, touched the protected automation files under `.github/`, or violated the dependency policy. In those cases the run fails and the report/logs are still uploaded.

The prompt explicitly tells pi to repair failures caused by the dependency bump and rerun the checks. Reverting the update is only the fallback when the failure cannot be fixed within the scope of the dependency update. If the independent test gate still fails, the workflow runs a second pi pass using `.github/pi-dependency-updater/prompts/repair-tests.md` and the captured test output, then re-runs the gate.

If there are no changes, the workflow exits without opening a PR. If the safety gate fails, no PR is opened and the pi logs/report are uploaded as a workflow artifact.

## Package manager support

The action does not assume npm. It detects the package manager from the first match:

1. `packageManager` in `package.json` (for example `"pnpm@9.15.0"` or `"yarn@4.5.0"`).
2. `pnpm-lock.yaml` → pnpm.
3. `yarn.lock` → Yarn. Yarn Classic vs Berry is selected from `packageManager`, or from `.yarnrc.yml` / `.yarn/releases` when the field is absent.
4. `package-lock.json` or `npm-shrinkwrap.json` → npm.
5. Otherwise npm.

The installer uses `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile` for Yarn Classic, or `yarn install --immutable` for Yarn Berry when the matching lockfile exists. Without a lockfile it falls back to the manager's normal install command. The check runner uses the same manager for `test`, `build`, and `lint`.

pnpm and Yarn are provisioned with Corepack, which is bundled with Node.js. When `packageManager` pins a version, that version is used.

To override detection, set these optional repository variables:

| Variable | Meaning |
| --- | --- |
| `PACKAGE_MANAGER` | `npm`, `pnpm`, or `yarn`. |
| `PACKAGE_MANAGER_VERSION` | A version or dist-tag, for example `9.15.0`, `latest`, or `stable` for Yarn Berry. |

## Setup

### 1. Add the Mixlayer API key

Create a repository secret named `MIXLAYER_API_KEY`:

```bash
gh secret set MIXLAYER_API_KEY
```

### 2. Configure the model

The workflow reads the model from the `MIXLAYER_MODEL` environment variable, which is populated from the repository variable `MIXLAYER_MODEL`.

```bash
gh variable set MIXLAYER_MODEL --body "deepseek/deepseek-v4.1-flash"
```

If the variable is not set, the workflow falls back to `deepseek/deepseek-v4.1-flash`. Change the default in `.github/workflows/update-dependencies.yml` if you prefer a different model.

The API key is read by the `pi-mixlayer` extension from `MIXLAYER_API_KEY`; it is not passed on the command line.

### 3. Enable workflow permissions

The workflow uses the built-in `GITHUB_TOKEN` with:

```yaml
permissions:
  contents: write
  pull-requests: write
```

If your organization restricts workflow permissions, make sure these are allowed under **Settings → Actions → General → Workflow permissions**.

You must also enable **Allow GitHub Actions to create and approve pull requests**. The `pull-requests: write` permission alone is not enough; without this setting, the workflow fails at `gh pr create` with `GitHub Actions is not permitted to create or approve pull requests`.

You can enable it from the UI or with the API:

```bash
gh api --method PUT repos/OWNER/REPO/actions/permissions/workflow \
  --input - <<'JSON'
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":true}
JSON
```

## Running the workflow

### Manually

Open **Actions → Update dependencies → Run workflow** and choose the policy inputs:

| Input | Default | Meaning |
| --- | --- | --- |
| `ignore_major` | `true` | Do not cross major versions. If a newer minor/patch exists in the current major, update to that instead. |
| `ignore_packages` | empty | Comma-separated package names to leave untouched, for example `chalk,lodash`. |
| `allow_prerelease` | `false` | Allow versions such as `2.0.0-beta.1`. |
| `extra_rules` | empty | Free-form rules appended to the prompt, for example `Keep @types/* on the same major as its runtime package`. |

The workflow also runs on a schedule every Monday at 06:00 UTC. Scheduled runs use these repository variables when present:

| Variable | Default | Meaning |
| --- | --- | --- |
| `IGNORE_MAJOR_UPDATES` | `true` | Same as the `ignore_major` input. |
| `IGNORE_PACKAGES` | empty | Same as the `ignore_packages` input. |
| `ALLOW_PRERELEASE` | `false` | Same as the `allow_prerelease` input. |
| `EXTRA_RULES` | empty | Same as the `extra_rules` input. |

Manual inputs take precedence over the repository variables.

### Locally

```bash
npm install --global --ignore-scripts @earendil-works/pi-coding-agent

npm ci
npm test

export MIXLAYER_API_KEY="sk_mxl_..."
export MIXLAYER_MODEL="deepseek/deepseek-v4.1-flash"
export MIXLAYER_TRANSPORT="chat-completions"

export IGNORE_MAJOR="true"
export IGNORE_PACKAGES=""
export ALLOW_PRERELEASE="false"
export EXTRA_RULES=""
export DEPENDENCY_REPORT_PATH="/tmp/dependency-report.md"

node .github/pi-dependency-updater/scripts/render-prompt.mjs > /tmp/pi-prompt.md

pi \
  --no-session \
  --no-extensions \
  -e npm:pi-mixlayer \
  --provider mixlayer \
  --model "$MIXLAYER_MODEL" \
  -p "$(cat /tmp/pi-prompt.md)"

bash .github/pi-dependency-updater/scripts/run-checks.sh
node .github/pi-dependency-updater/scripts/check-policy.mjs
cat /tmp/dependency-report.md
```

The sample repository uses npm. In another repo, run `bash .github/pi-dependency-updater/scripts/install-deps.sh` and `bash .github/pi-dependency-updater/scripts/run-checks.sh` instead; they auto-detect pnpm and Yarn as well.

You can also inspect the current outdated packages before running pi:

```bash
npm outdated --json || true
```

For pnpm or Yarn, use the matching command (`pnpm outdated`, `yarn outdated` for Yarn Classic, or `yarn npm info` for Yarn Berry).

## Project layout

```
.
├── .github/
│   ├── pi-dependency-updater/
│   │   ├── README.md                    # copy instructions for other repos
│   │   ├── prompts/
│   │   │   ├── update-dependencies.md   # main dependency update prompt
│   │   │   └── repair-tests.md          # second-pass test repair prompt
│   │   └── scripts/
│   │       ├── check-policy.mjs         # deterministic policy enforcement
│   │       ├── install-deps.sh          # install helper
│   │       ├── package-manager.sh       # detects npm/pnpm/Yarn and runs scripts
│   │       ├── render-prompt.mjs        # fills in policy values
│   │       ├── render-repair-prompt.mjs # fills in repair prompt values
│   │       └── run-checks.sh            # install + test/build/lint helper
│   └── workflows/update-dependencies.yml
├── src/
│   ├── cli.js
│   └── version.js
├── test/
│   ├── package-manager.test.js
│   └── version.test.js
├── AGENTS.md
├── package.json
└── package-lock.json
```

## Copying to another repo

Everything the action needs lives under `.github/pi-dependency-updater/` plus `.github/workflows/update-dependencies.yml`. See [`.github/pi-dependency-updater/README.md`](.github/pi-dependency-updater/README.md) for copy-paste instructions and target-repo requirements.

The sample pins deliberately older versions so the workflow has something to update:

- `chalk@4.1.2` has a newer major release, so it is skipped by default when `ignore_major=true`.
- `lodash@4.17.20` and `semver@7.5.2` have newer minor/patch releases, so they are updated by default.

## Customizing

- **Model**: set the `MIXLAYER_MODEL` repository variable or change the fallback in the workflow.
- **Node version**: set the `NODE_VERSION` repository variable or edit the workflow. The default is `22`.
- **Package manager**: auto-detected from `packageManager` or the lockfile. Set the `PACKAGE_MANAGER` / `PACKAGE_MANAGER_VERSION` repository variables to override.
- **Schedule**: edit the `cron` expression in `.github/workflows/update-dependencies.yml`.
- **Policy**: update the rules in `.github/pi-dependency-updater/prompts/update-dependencies.md`.
- **PR flow**: the workflow uses `gh pr create`; replace it with an MCP-based PR tool if your environment provides one.

## Security notes

- `GITHUB_TOKEN` is only exposed to the final push/PR step. The checkout uses `persist-credentials: false`, so the pi step cannot push commits or open PRs. The final step runs `gh auth setup-git` before pushing.
- `MIXLAYER_API_KEY` is available to the pi process so the provider can authenticate. Like any agent running in CI, pi's shell tool inherits the process environment. The prompt tells the agent not to print secrets, and GitHub Actions masks secret values in logs, but for stronger isolation run pi inside a container or use a tool-routing extension that strips credentials from shell commands.
- The workflow does not run `pull_request_target` or checkout untrusted code with write credentials. It runs on the default branch on a schedule or on manual dispatch.
