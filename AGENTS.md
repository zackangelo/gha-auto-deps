# Project Instructions

This is a small Node.js sample project used to demonstrate the pi-powered dependency update workflow.

- Run `npm test` after changing source code or dependencies.
- Keep changes focused on dependency updates; do not edit `.github/workflows/`, `.github/prompts/`, or `.github/scripts/` unless the task is specifically about the automation.
- Use exact versions in `package.json` so the dependency diff is easy to review.
- Do not commit `node_modules/`, logs, or generated reports.
