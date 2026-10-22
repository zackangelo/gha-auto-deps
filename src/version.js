import chalk from "chalk";
import lodash from "lodash";
import semver from "semver";

const { uniq } = lodash;

/**
 * Return the highest stable semver from a list of version strings.
 * Invalid versions and prereleases are ignored.
 */
export function highestStable(versions) {
  const stable = versions.filter(
    (version) => semver.valid(version) && !semver.prerelease(version),
  );

  return semver.rsort(uniq(stable))[0] ?? null;
}

/**
 * Classify the semver change between two versions.
 */
export function classifyUpdate(current, next) {
  if (!semver.valid(current) || !semver.valid(next)) {
    throw new TypeError(`Invalid semver comparison: ${current} -> ${next}`);
  }

  const diff = semver.diff(current, next);

  if (!diff) return "none";
  if (diff === "major" || diff === "premajor") return "major";
  if (diff === "minor" || diff === "preminor") return "minor";
  if (diff === "patch" || diff === "prepatch") return "patch";

  return diff;
}

/**
 * Format a dependency update for terminal output.
 */
export function formatUpdate(current, next) {
  const kind = classifyUpdate(current, next);
  const color =
    kind === "major"
      ? chalk.red
      : kind === "minor"
        ? chalk.yellow
        : kind === "none"
          ? chalk.dim
          : chalk.green;

  return `${current} -> ${color(next)} (${kind})`;
}
