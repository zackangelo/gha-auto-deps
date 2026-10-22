# pi Dependency Updater

Portable GitHub Action that uses the [pi coding agent](https://pi.dev) with the [`pi-mixlayer`](https://www.npmjs.com/package/pi-mixlayer) provider to:

- scan a Node.js project for outdated dependencies
- apply a dependency policy such as "ignore major updates"
- fix test/build/lint failures caused by the updates
- run the project checks again before opening a PR
- open a PR with the `gh` CLI and include a report of updated and skipped dependencies

Everything the action needs lives in this folder plus one workflow file:

```text
.github/
├── pi-dependency-updater/
│   ├── prompts/
│   │   ├── update-dependencies.md
│   │   └── repair-tests.md
│   └── scripts/
│       ├── check-policy.mjs
│       ├── install-deps.sh
│       ├── package-manager.sh
│       ├── render-prompt.mjs
│       ├── render-repair-prompt.mjs
│       └── run-checks.sh
└── workflows/
    └── update-dependencies.yml
```

The sample application in the rest of this repository is not required. `AGENTS.md` is also optional; the prompt reads it if the target repo has one.

## Target repo requirements

- A Node.js project with `package.json`.
- A `test` script is strongly recommended. `build` and `lint` scripts are optional and run when present.
- A lockfile is optional. The installer uses the matching frozen/immutable install when a lockfile exists, otherwise it falls back to the package manager's normal install command.
- One of npm, pnpm, or Yarn. The package manager is auto-detected from `packageManager` in `package.json`, then the lockfile. npm is the fallback.
- Corepack for pnpm or Yarn. Corepack is bundled with Node.js; the workflow uses Node 22 by default.
- GitHub Actions enabled.
- A repository secret named `MIXLAYER_API_KEY`.
- A repository variable named `MIXLAYER_MODEL`, or edit the fallback in the workflow.
- Workflow permissions for `contents: write` and `pull-requests: write`.

## Package manager detection

The action detects the package manager from the first match:

1. `packageManager` in `package.json` (for example `"pnpm@9.15.0"` or `"yarn@4.5.0"`).
2. `pnpm-lock.yaml` → pnpm.
3. `yarn.lock` → Yarn. Yarn Classic vs Berry is selected from `packageManager`, or from `.yarnrc.yml` / `.yarn/releases` when the field is absent.
4. `package-lock.json` or `npm-shrinkwrap.json` → npm.
5. Otherwise npm.

The installer uses `npm ci`, `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile` for Yarn Classic, or `yarn install --immutable` for Yarn Berry when the matching lockfile exists. Without a lockfile it falls back to the manager's normal install command. The check runner uses the same manager for `test`, `build`, and `lint`.

pnpm and Yarn are provisioned with Corepack. When `packageManager` pins a version, that version is used. You can override detection with the optional repository variables `PACKAGE_MANAGER` (`npm`, `pnpm`, or `yarn`) and `PACKAGE_MANAGER_VERSION` (a version or dist-tag such as `9.15.0`, `latest`, or `stable` for Yarn Berry).

## Copy into another repo

From the root of this sample repository:

```bash
SAMPLE=/path/to/gha-auto-deps
TARGET=/path/to/target-repo

mkdir -p "$TARGET/.github/workflows"
cp -R "$SAMPLE/.github/pi-dependency-updater" "$TARGET/.github/"
cp "$SAMPLE/.github/workflows/update-dependencies.yml" "$TARGET/.github/workflows/"
```

If the target already has a workflow with that name, rename the copied workflow file and update its `name:` value.

Then configure the target repo:

```bash
cd "$TARGET"

gh secret set MIXLAYER_API_KEY
gh variable set MIXLAYER_MODEL --body "deepseek/deepseek-v4.1-flash"

# Optional: override package manager auto-detection.
# gh variable set PACKAGE_MANAGER --body "pnpm"
# gh variable set PACKAGE_MANAGER_VERSION --body "9.15.0"
```

If the model is not set, the workflow falls back to `deepseek/deepseek-v4.1-flash`. To see models available to the Mixlayer provider:

```bash
pi --no-session --no-extensions -e npm:pi-mixlayer --list-models mixlayer
```

Enable workflow permissions under **Settings → Actions → General → Workflow permissions**:

- `contents: write`
- `pull-requests: write`
- **Allow GitHub Actions to create and approve pull requests**

The last setting is required. Without it, `gh pr create` fails with `GitHub Actions is not permitted to create or approve pull requests`, even when `pull-requests: write` is granted in the workflow. You can enable it from the UI or with the API:

```bash
gh api --method PUT repos/OWNER/REPO/actions/permissions/workflow \
  --input - <<'JSON'
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":true}
JSON
```

Commit and push the copied files:

```bash
git add .github
git commit -m "ci: add pi dependency updater"
git push
```

Then run it manually from **Actions → Update dependencies → Run workflow** to verify the setup.

## Policy inputs

Manual runs expose:

| Input | Default | Meaning |
| --- | --- | --- |
| `ignore_major` | `true` | Do not cross major versions. If a newer minor/patch exists in the current major, update to that instead. |
| `ignore_packages` | empty | Comma-separated package names to leave untouched. |
| `allow_prerelease` | `false` | Allow versions such as `2.0.0-beta.1`. |
| `extra_rules` | empty | Extra free-form rules appended to the prompt. |

Scheduled runs can use these repository variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `IGNORE_MAJOR_UPDATES` | `true` | Same as `ignore_major`. |
| `IGNORE_PACKAGES` | empty | Same as `ignore_packages`. |
| `ALLOW_PRERELEASE` | `false` | Same as `allow_prerelease`. |
| `EXTRA_RULES` | empty | Same as `extra_rules`. |

The deterministic policy check in `scripts/check-policy.mjs` compares `package.json` against the base commit and rejects:

- major updates when `IGNORE_MAJOR=true`
- changes to packages listed in `IGNORE_PACKAGES`
- prerelease versions when `ALLOW_PRERELEASE=false`

It is self-contained and does not require `semver` in the target repo.

## What to customize

- **Model**: set the `MIXLAYER_MODEL` repository variable, or change the fallback in `.github/workflows/update-dependencies.yml`.
- **Node version**: set the `NODE_VERSION` repository variable, or edit the workflow. The default is `22`.
- **Schedule**: edit the `cron` expression in the workflow.
- **Branch name and PR title**: edit the `BRANCH` and `gh pr create` lines in the workflow.
- **Package manager**: auto-detected from `packageManager` or the lockfile. Set `PACKAGE_MANAGER` / `PACKAGE_MANAGER_VERSION` to override.
- **Package manager caching**: add `cache: npm`, `cache: pnpm`, or `cache: yarn` to the `actions/setup-node` step if the target repo has the matching lockfile.
- **Policy wording**: edit `prompts/update-dependencies.md`.
- **Repair behavior**: edit `prompts/repair-tests.md`.

## How the workflow runs

1. Detects the package manager and installs dependencies with `scripts/install-deps.sh`.
2. Installs pi and loads `pi-mixlayer`.
3. Renders `prompts/update-dependencies.md` with the selected policy.
4. Runs pi non-interactively with the `mixlayer` provider.
5. Enforces the policy with `scripts/check-policy.mjs`.
6. Runs `scripts/run-checks.sh`.
7. If checks fail, runs a second pi repair pass with `prompts/repair-tests.md` and the captured test output, then reruns the policy check and checks.
8. Commits the changes to a new branch and opens a PR with `gh pr create`.
9. Uploads the report, prompts, test output, and pi logs as workflow artifacts.

A PR is never opened if the final policy check or checks fail.

## Security notes

- `GITHUB_TOKEN` is only exposed to the final push/PR step.
- The checkout uses `persist-credentials: false`, so the pi steps cannot push or open PRs.
- `MIXLAYER_API_KEY` is available to the pi process for provider authentication. Like any agent in CI, pi's shell tool inherits the process environment. The prompts forbid printing secrets, and GitHub masks secret values in logs, but use a container or tool-routing extension if you need stronger isolation.
- The workflow runs on a schedule or manual dispatch on the default branch. It does not use `pull_request_target`.

## Troubleshooting

- **Model not found**: set `MIXLAYER_MODEL` to a model returned by `pi --list-models mixlayer`.
- **No tests ran**: add a `test` script to `package.json`. The check helper warns and continues when the script is missing.
- **Dependency install failed**: the lockfile is out of sync with `package.json`, or the package manager version does not match the lockfile. The repair pass is instructed to fix this, or run the install command locally and commit the updated lockfile.
- **Workflow does not appear in Actions**: make sure `update-dependencies.yml` is under `.github/workflows/` on the default branch.
- **PR creation fails**: confirm the workflow has `contents: write` and `pull-requests: write`, that **Allow GitHub Actions to create and approve pull requests** is enabled, and that branch protection allows the bot to push a new branch.
- **Tests need secrets or external services**: add the required environment variables to the workflow steps or to `scripts/run-checks.sh`. Do not put secrets in the prompt files.
- **pnpm or Yarn not found**: make sure Corepack is available (`corepack --version`). The workflow uses Node 22, which bundles it. You can also set `PACKAGE_MANAGER` and `PACKAGE_MANAGER_VERSION` explicitly.
