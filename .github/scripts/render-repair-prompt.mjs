#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const templatePath = resolve(here, "../prompts/repair-tests.md");
const template = readFileSync(templatePath, "utf8");

const values = {
  DEPENDENCY_REPORT_PATH:
    process.env.DEPENDENCY_REPORT_PATH ?? "/tmp/dependency-report.md",
  GITHUB_REPOSITORY: process.env.GITHUB_REPOSITORY ?? "local",
  TEST_OUTPUT_PATH: process.env.TEST_OUTPUT_PATH ?? "/tmp/test-output.log",
};

const rendered = template.replace(/\{\{([A-Z0-9_]+)\}\}/g, (match, key) =>
  Object.hasOwn(values, key) ? values[key] : match,
);

process.stdout.write(rendered);
