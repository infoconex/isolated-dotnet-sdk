'use strict';

const fs = require('node:fs');

// Validate only the entry being released. Older versions may legitimately
// mention historical prereleases, candidates, or different publication dates.
function validateReleaseChangelog(changelog, tag, expectedDate) {
  if (typeof tag !== 'string' || !/^v[0-9]+\.[0-9]+\.[0-9]+$/.test(tag)) {
    throw new Error('Stable release tag must use vMAJOR.MINOR.PATCH.');
  }
  if (typeof expectedDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(expectedDate)) {
    throw new Error('Expected UTC publication date must use YYYY-MM-DD.');
  }
  const date = new Date(expectedDate + 'T00:00:00Z');
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== expectedDate) {
    throw new Error('Expected UTC publication date is not a real calendar date.');
  }
  if (typeof changelog !== 'string') {
    throw new Error('CHANGELOG.md content is missing.');
  }

  const version = tag.slice(1);
  const headings = [...changelog.matchAll(/^## \[([^\]\r\n]+)\]\s*-\s*([^\r\n]*)\r?$/gm)];
  const entries = headings.filter((heading) => heading[1] === version);
  if (entries.length !== 1) {
    throw new Error('CHANGELOG.md must have exactly one release entry for ' + tag + '.');
  }
  if (entries[0][2] !== expectedDate) {
    throw new Error(
      'CHANGELOG.md entry for ' + tag + ' must have the exact UTC publication date ' +
      expectedDate + ', not ' + JSON.stringify(entries[0][2]) + '.'
    );
  }

  const following = changelog.slice(entries[0].index + entries[0][0].length);
  const nextHeading = following.search(/^##[ \t]+/m);
  const entry = nextHeading === -1 ? following : following.slice(0, nextHeading);
  if (!entry.trim()) {
    throw new Error('CHANGELOG.md entry for ' + tag + ' has no release details.');
  }
  if (/\b(?:unreleased|candidate|not yet published|not yet public|publication pending|publication is pending|will be published|date will be finalized|being prepared)\b/i.test(entry)) {
    throw new Error('CHANGELOG.md entry for ' + tag + ' still contains provisional or candidate wording.');
  }
  return { tag, date: expectedDate };
}

// The tagged-source changelog gate was introduced after v0.4.0 was published.
// Keep historical release verification compatible, but enforce for all later
// stable versions, including v0.4.1 hotfixes.
function requiresTaggedChangelogValidation(tag) {
  if (typeof tag !== 'string' || !/^v[0-9]+\.[0-9]+\.[0-9]+$/.test(tag)) {
    throw new Error('Stable release tag must use vMAJOR.MINOR.PATCH.');
  }
  const [major, minor, patch] = tag.slice(1).split('.').map(Number);
  if (![major, minor, patch].every(Number.isSafeInteger)) {
    throw new Error('Stable release version components must be safe integers.');
  }
  return major > 0 || minor > 4 || (minor === 4 && patch > 0);
}

module.exports = { validateReleaseChangelog, requiresTaggedChangelogValidation };

if (require.main === module) {
  try {
    const tag = process.argv[2];
    const date = process.argv[3];
    validateReleaseChangelog(fs.readFileSync('CHANGELOG.md', 'utf8'), tag, date);
    process.stdout.write('Validated finalized changelog entry for ' + tag + ' (' + date + ').\n');
  } catch (error) {
    process.stderr.write('Release changelog validation failed: ' + error.message + '\n');
    process.exitCode = 1;
  }
}
