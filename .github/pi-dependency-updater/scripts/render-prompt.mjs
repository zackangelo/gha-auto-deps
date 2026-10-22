#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const templatePath = resolve(here, "../prompts/update-dependencies.md");
const template = readFileSync(templatePath, "utf8");

const ignorePackages = (process.env.IGNORE_PACKAGES ?? "").trim();
const extraRules = (process.env.EXTRA_RULES ?? "").trim();

const values = {
  ALLOW_PRERELEASE: process.env.ALLOW_PRERELEASE ?? "false",
  DEPENDENCY_REPORT_PATH:
    process.env.DEPENDENCY_REPORT_PATH ?? "/tmp/dependency-report.md",
  EXTRA_RULES: extraRules || "(none)",
  GITHUB_REPOSITORY: process.env.GITHUB_REPOSITORY ?? "local",
  IGNORE_MAJOR: process.env.IGNORE_MAJOR ?? "true",
  IGNORE_PACKAGES: ignorePackages || "(none)",
};

const rendered = template.replace(/\{\{([A-Z0-9_]+)\}\}/g, (match, key) =>
  Object.hasOwn(values, key) ? values[key] : match,
);

process.stdout.write(rendered);
