import assert from "node:assert/strict";
import test from "node:test";
import chalk from "chalk";

import {
  classifyUpdate,
  formatUpdate,
  highestStable,
} from "../src/version.js";

// Keep assertions stable when tests run in a TTY.
chalk.level = 0;

test("highestStable returns the highest stable version", () => {
  assert.equal(
    highestStable(["1.0.0", "1.2.0", "2.0.0-beta.1", "not-a-version"]),
    "1.2.0",
  );
});

test("highestStable deduplicates versions", () => {
  assert.equal(highestStable(["1.0.0", "1.0.0"]), "1.0.0");
});

test("highestStable returns null when no stable versions exist", () => {
  assert.equal(highestStable(["2.0.0-rc.1", "nope"]), null);
});

test("classifyUpdate detects major, minor, and patch changes", () => {
  assert.equal(classifyUpdate("1.2.3", "2.0.0"), "major");
  assert.equal(classifyUpdate("1.2.3", "1.3.0"), "minor");
  assert.equal(classifyUpdate("1.2.3", "1.2.4"), "patch");
  assert.equal(classifyUpdate("1.2.3", "1.2.3"), "none");
});

test("classifyUpdate rejects invalid versions", () => {
  assert.throws(() => classifyUpdate("1.2.3", "latest"), TypeError);
});

test("formatUpdate includes the versions and change kind", () => {
  assert.match(formatUpdate("1.2.3", "1.3.0"), /1\.2\.3 -> 1\.3\.0 \(minor\)/);
});
