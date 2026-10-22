#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import semver from "semver";

const DEPENDENCY_FIELDS = [
  "dependencies",
  "devDependencies",
  "optionalDependencies",
  "peerDependencies",
];

function readBasePackageJson() {
  const baseRef = process.env.BASE_SHA || "HEAD";

  try {
    return JSON.parse(
      execFileSync("git", ["show", `${baseRef}:package.json`], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
  } catch {
    return null;
  }
}

function cleanVersion(range) {
  if (typeof range !== "string") return null;

  const cleaned = range
    .trim()
    .replace(/^(?:[\^~]|>=?|<=?|=)?\s*/, "");

  if (semver.valid(cleaned)) return cleaned;

  return semver.coerce(cleaned)?.version ?? null;
}

const before = readBasePackageJson();
if (!before) {
  console.log("No base package.json found; skipping dependency policy check.");
  process.exit(0);
}

const after = JSON.parse(readFileSync("package.json", "utf8"));

const ignoreMajor = (process.env.IGNORE_MAJOR ?? "true").toLowerCase() === "true";
const allowPrerelease =
  (process.env.ALLOW_PRERELEASE ?? "false").toLowerCase() === "true";
const ignoredPackages = new Set(
  (process.env.IGNORE_PACKAGES ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean),
);

const violations = [];

for (const field of DEPENDENCY_FIELDS) {
  const beforeDeps = before[field] ?? {};
  const afterDeps = after[field] ?? {};

  for (const [name, afterRange] of Object.entries(afterDeps)) {
    if (!(name in beforeDeps)) continue;

    const beforeRange = beforeDeps[name];

    if (ignoredPackages.has(name)) {
      if (afterRange !== beforeRange) {
        violations.push(
          `${name}: ignored package changed from ${beforeRange} to ${afterRange}`,
        );
      }
      continue;
    }

    const from = cleanVersion(beforeRange);
    const to = cleanVersion(afterRange);

    if (!from || !to || from === to) continue;

    if (!allowPrerelease && semver.prerelease(to)) {
      violations.push(
        `${name}: prerelease ${to} is not allowed (was ${from})`,
      );
    }

    if (ignoreMajor && semver.major(to) !== semver.major(from)) {
      violations.push(
        `${name}: major update ${from} -> ${to} is not allowed (ignore_major=true)`,
      );
    }
  }
}

if (violations.length > 0) {
  console.error("Dependency policy violations:");
  for (const violation of violations) {
    console.error(`- ${violation}`);
  }
  process.exit(1);
}

console.log("Dependency policy check passed.");
