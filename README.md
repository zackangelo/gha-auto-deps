# gha-auto-deps-sample

A small Node.js project with a pi-powered GitHub Action that updates npm dependencies, runs the test suite, and opens a pull request with a report of what changed and what was skipped.

The action uses the [`pi-mixlayer`](https://www.npmjs.com/package/pi-mixlayer) provider plugin. The Mixlayer API key and model are passed to pi through environment variables.

## What the workflow does

1. Checks out the repository and installs dependencies with `npm ci`.
2. Installs the pi coding agent and loads the `pi-mixlayer` extension for one run.
3. Renders a prompt from `.github/prompts/update-dependencies.md` using the workflow inputs.
4. Runs pi in non-interactive mode with the `mixlayer` provider.
5. Lets pi inspect `package.json` / `package-lock.json`, apply the dependency policy, run tests, and write a Markdown report.
6. Enforces the policy deterministically by comparing `package.json` against `HEAD`, then re-runs `npm ci` and `npm test` as a safety gate.
7. Commits the changes to a new branch and opens a PR with the `gh` CLI. The PR body includes the report, including every skipped update and the reason.

The workflow refuses to open a PR if pi committed changes, touched the protected automation files under `.github/`, or violated the dependency policy. In those cases the run fails and the report/logs are still uploaded.

If there are no changes, the workflow exits without opening a PR. If the safety gate fails, no PR is opened and the pi logs/report are uploaded as a workflow artifact.

## Setup

### 1. Add the Mixlayer API key

Create a repository secret named `MIXLAYER_API_KEY`:

```bash
gh secret set MIXLAYER_API_KEY
```

### 2. Configure the model

The workflow reads the model from the `MIXLAYER_MODEL` environment variable, which is populated from the repository variable `MIXLAYER_MODEL`.

```bash
gh variable set MIXLAYER_MODEL --body "z-ai/glm-5.3"
```

If the variable is not set, the workflow falls back to `z-ai/glm-5.3`. Change the default in `.github/workflows/update-dependencies.yml` if you prefer a different model.

The API key is read by the `pi-mixlayer` extension from `MIXLAYER_API_KEY`; it is not passed on the command line.

### 3. Enable workflow permissions

The workflow uses the built-in `GITHUB_TOKEN` with:

```yaml
permissions:
  contents: write
  pull-requests: write
```

If your organization restricts workflow permissions, make sure these are allowed under **Settings → Actions → General → Workflow permissions**.

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
export MIXLAYER_MODEL="z-ai/glm-5.3"
export MIXLAYER_TRANSPORT="chat-completions"

export IGNORE_MAJOR="true"
export IGNORE_PACKAGES=""
export ALLOW_PRERELEASE="false"
export EXTRA_RULES=""
export DEPENDENCY_REPORT_PATH="/tmp/dependency-report.md"

node .github/scripts/render-prompt.mjs > /tmp/pi-prompt.md

pi \
  --no-session \
  --no-extensions \
  -e npm:pi-mixlayer \
  --provider mixlayer \
  --model "$MIXLAYER_MODEL" \
  -p "$(cat /tmp/pi-prompt.md)"

node .github/scripts/check-policy.mjs
cat /tmp/dependency-report.md
```

You can also inspect the current outdated packages before running pi:

```bash
npm outdated --json || true
```

## Project layout

```
.
├── .github/
│   ├── prompts/update-dependencies.md   # prompt template used by the action
│   ├── scripts/
│   │   ├── check-policy.mjs             # deterministic policy enforcement
│   │   └── render-prompt.mjs            # fills in policy values
│   └── workflows/update-dependencies.yml
├── src/
│   ├── cli.js
│   └── version.js
├── test/version.test.js
├── AGENTS.md
├── package.json
└── package-lock.json
```

The sample pins deliberately older versions so the workflow has something to update:

- `chalk@4.1.2` has a newer major release, so it is skipped by default when `ignore_major=true`.
- `lodash@4.17.20` and `semver@7.5.2` have newer minor/patch releases, so they are updated by default.

## Customizing

- **Model**: set the `MIXLAYER_MODEL` repository variable or change the fallback in the workflow.
- **Schedule**: edit the `cron` expression in `.github/workflows/update-dependencies.yml`.
- **Policy**: update the rules in `.github/prompts/update-dependencies.md`.
- **PR flow**: the workflow uses `gh pr create`; replace it with an MCP-based PR tool if your environment provides one.

## Security notes

- `GITHUB_TOKEN` is only exposed to the final push/PR step. The checkout uses `persist-credentials: false`, so the pi step cannot push commits or open PRs. The final step runs `gh auth setup-git` before pushing.
- `MIXLAYER_API_KEY` is available to the pi process so the provider can authenticate. Like any agent running in CI, pi's shell tool inherits the process environment. The prompt tells the agent not to print secrets, and GitHub Actions masks secret values in logs, but for stronger isolation run pi inside a container or use a tool-routing extension that strips credentials from shell commands.
- The workflow does not run `pull_request_target` or checkout untrusted code with write credentials. It runs on the default branch on a schedule or on manual dispatch.
