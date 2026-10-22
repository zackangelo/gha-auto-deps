# Project Instructions

This is a small Node.js sample project used to demonstrate the pi-powered dependency update workflow.

- If a dependency update breaks tests, fix the application code or update test expectations to match legitimate API changes. Do not delete or skip tests. Only revert the dependency update if the failure cannot be fixed.
- Run `npm test` after changing source code or dependencies.
- Keep changes focused on dependency updates; do not edit `.github/workflows/`, `.github/prompts/`, or `.github/scripts/` unless the task is specifically about the automation.
- Use exact versions in `package.json` so the dependency diff is easy to review.
- Do not commit `node_modules/`, logs, or generated reports.
