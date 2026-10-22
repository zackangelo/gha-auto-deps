The dependency update run left the test suite or lockfile check failing. This is a repair pass before any PR is opened.

- Test output: `{{TEST_OUTPUT_PATH}}`
- Dependency report: `{{DEPENDENCY_REPORT_PATH}}`
- Repository: `{{GITHUB_REPOSITORY}}`
- Package manager: `{{PACKAGE_MANAGER}}`
- Lockfile: `{{PACKAGE_MANAGER_LOCKFILE}}`

Read the test output and the report. Fix failures caused by the dependency updates. If dependency installation failed, fix the `package.json` / lockfile inconsistency first. Use `{{PACKAGE_MANAGER_INSTALL_COMMAND}}` to refresh the lockfile after changing `package.json`, and use `{{PACKAGE_MANAGER_CI_COMMAND}}` only when the lockfile is already in sync. Do not hand-edit the lockfile. Prefer minimal application-code changes or test-expectation updates that reflect legitimate API changes. Do not delete tests, skip tests, or weaken assertions just to get a pass. Do not change the dependency policy.

Rerun the project checks with `bash .github/pi-dependency-updater/scripts/run-checks.sh` until they pass. Update the report's `## Test results` and `## Notes` sections with the fixes you made. Do not commit, push, or open a PR. If a failure cannot be fixed, revert the offending dependency update and record it in the report as skipped with the reason.

## Guardrails

- Never print, commit, or write secrets to files.
- Do not run destructive git commands such as `git reset --hard`, `git clean -fd`, or force-pushes.
- Never delete, skip, or weaken tests just to make the suite pass.
- Do not modify workflow files, prompt files, scripts under `.github/`, or unrelated files.
- Do not commit, push, or open a pull request.
