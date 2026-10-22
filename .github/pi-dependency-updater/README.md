# pi Dependency Updater

Portable GitHub Action that uses the [pi coding agent](https://pi.dev) with the [`pi-mixlayer`](https://www.npmjs.com/package/pi-mixlayer) provider to:

- scan a Node.js project for outdated npm dependencies
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
│       ├── render-prompt.mjs
│       ├── render-repair-prompt.mjs
│       └── run-checks.sh
└── workflows/
    └── update-dependencies.yml
```

The sample application in the rest of this repository is not required. `AGENTS.md` is also optional; the prompt reads it if the target repo has one.

## Target repo requirements

- A Node.js project with `package.json`.
- An npm `test` script is strongly recommended. `build` and `lint` scripts are optional and run when present.
- A lockfile is optional. The installer uses `npm ci` when `package-lock.json` or `npm-shrinkwrap.json` exists, otherwise it falls back to `npm install`.
- GitHub Actions enabled.
- A repository secret named `MIXLAYER_API_KEY`.
- A repository variable named `MIXLAYER_MODEL`, or edit the fallback in the workflow.
- Workflow permissions for `contents: write` and `pull-requests: write`.

The scripts are npm-based by default. For pnpm, Yarn, or custom commands, edit `scripts/install-deps.sh` and `scripts/run-checks.sh`, then update the prompt wording in `prompts/update-dependencies.md` and `prompts/repair-tests.md`.

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
```

If the model is not set, the workflow falls back to `deepseek/deepseek-v4.1-flash`. To see models available to the Mixlayer provider:

```bash
pi --no-session --no-extensions -e npm:pi-mixlayer --list-models mixlayer
```

Enable workflow permissions under **Settings → Actions → General → Workflow permissions**:

- `contents: write`
- `pull-requests: write`

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
- **Package manager**: edit `scripts/install-deps.sh` and `scripts/run-checks.sh`.
- **npm caching**: add `cache: npm` to the `actions/setup-node` step if the target repo has a lockfile.
- **Policy wording**: edit `prompts/update-dependencies.md`.
- **Repair behavior**: edit `prompts/repair-tests.md`.

## How the workflow runs

1. Installs dependencies with `scripts/install-deps.sh`.
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
- **No tests ran**: add an npm `test` script. The check helper warns and continues when the script is missing.
- **`npm ci` failed**: the lockfile is out of sync with `package.json`. The repair pass is instructed to fix this, or run `npm install` locally and commit the updated lockfile.
- **Workflow does not appear in Actions**: make sure `update-dependencies.yml` is under `.github/workflows/` on the default branch.
- **PR creation fails**: confirm the workflow has `contents: write` and `pull-requests: write`, and that branch protection allows the bot to push a new branch.
- **Tests need secrets or external services**: add the required environment variables to the workflow steps or to `scripts/run-checks.sh`. Do not put secrets in the prompt files.
- **Using pnpm or Yarn**: replace the npm commands in `scripts/install-deps.sh` and `scripts/run-checks.sh`, and adjust the prompt wording.
