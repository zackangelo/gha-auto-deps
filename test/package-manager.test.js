import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const script = join(
  here,
  "..",
  ".github",
  "pi-dependency-updater",
  "scripts",
  "package-manager.sh",
);

function detect(files, env = {}) {
  const dir = mkdtempSync(join(tmpdir(), "package-manager-"));

  try {
    for (const [name, contents] of Object.entries(files)) {
      writeFileSync(join(dir, name), contents);
    }

    const output = execFileSync(
      "bash",
      [
        "-c",
        'source "$1"; pm_detect; printf "%s|%s|%s|%s" "$PM" "$PM_VERSION" "$PM_YARN_MAJOR" "$PM_LOCKFILE"',
        "_",
        script,
      ],
      {
        cwd: dir,
        encoding: "utf8",
        env: {
          ...process.env,
          PACKAGE_MANAGER: "",
          PACKAGE_MANAGER_OVERRIDE: "",
          PACKAGE_MANAGER_VERSION: "",
          PACKAGE_MANAGER_VERSION_OVERRIDE: "",
          ...env,
        },
      },
    );

    const [manager, version, yarnMajor, lockfile] = output.split("|");
    return { manager, version, yarnMajor, lockfile };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("detects npm when no lockfile or packageManager is present", () => {
  const result = detect({});
  assert.equal(result.manager, "npm");
  assert.equal(result.lockfile, "");
});

test("uses the packageManager version for pnpm", () => {
  const result = detect({
    "package.json": JSON.stringify({ packageManager: "pnpm@9.15.0" }),
    "pnpm-lock.yaml": "lockfileVersion: 9\n",
  });

  assert.equal(result.manager, "pnpm");
  assert.equal(result.version, "9.15.0");
  assert.equal(result.lockfile, "pnpm-lock.yaml");
});

test("detects Yarn Classic from yarn.lock", () => {
  const result = detect({
    "package.json": JSON.stringify({ name: "yarn-classic" }),
    "yarn.lock": "# yarn lockfile v1\n",
  });

  assert.equal(result.manager, "yarn");
  assert.equal(result.version, "1.22.22");
  assert.equal(result.yarnMajor, "1");
  assert.equal(result.lockfile, "yarn.lock");
});

test("detects Yarn Berry from .yarnrc.yml", () => {
  const result = detect({
    "package.json": JSON.stringify({ name: "yarn-berry" }),
    "yarn.lock": "# yarn berry\n",
    ".yarnrc.yml": "nodeLinker: node-modules\n",
  });

  assert.equal(result.manager, "yarn");
  assert.equal(result.version, "stable");
  assert.equal(result.yarnMajor, "berry");
  assert.equal(result.lockfile, "yarn.lock");
});

test("allows an explicit package manager override", () => {
  const result = detect(
    {
      "package.json": JSON.stringify({ name: "override" }),
      "package-lock.json": "{}\n",
    },
    {
      PACKAGE_MANAGER_OVERRIDE: "pnpm",
      PACKAGE_MANAGER_VERSION_OVERRIDE: "9.15.0",
    },
  );

  assert.equal(result.manager, "pnpm");
  assert.equal(result.version, "9.15.0");
});
