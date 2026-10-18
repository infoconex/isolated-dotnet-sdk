'use strict';

// Intentionally conservative: only Markdown in the documentation tree and the
// root README can bypass cross-platform product validation.
function isDocumentationOnly(path) {
  return path === 'README.md' || /^docs\/.+\.md$/.test(path);
}

function affectsPages(path) {
  return isDocumentationOnly(path) ||
    path === 'CHANGELOG.md' ||
    path === 'LICENSE' ||
    path === '_config.yml' ||
    path === 'search-index.json' ||
    path === 'install.ps1' ||
    path === 'install.sh' ||
    path === '.config/test-frameworks.json' ||
    path === '.config/static-analysis.json' ||
    path === '.github/workflows/pages.yml' ||
    path === '.github/workflows/validate.yml' ||
    path === '.github/scripts/prepare-pages-source.sh' ||
    path === '.github/scripts/validate-pages-output.sh' ||
    path === '.github/scripts/check-documentation-links.js' ||
    path === '.github/scripts/check-pages-gate.js' ||
    path === '.github/scripts/classify-ci-changes.js' ||
    path === 'tests/node/ci-validation.test.js' ||
    path === 'tests/node/documentation-links.test.js' ||
    path.startsWith('_data/') ||
    path.startsWith('_layouts/') ||
    path.startsWith('assets/') ||
    path.startsWith('docs/') ||
    path.startsWith('.github/release-notes/');
}

function validPath(path) {
  return typeof path === 'string' && path.length > 0 &&
    !path.startsWith('/') && !path.includes('\\') &&
    !path.split('/').some((part) => part === '' || part === '.' || part === '..');
}

function classify(eventName, files, expectedCount) {
  if (eventName === 'push' || eventName === 'workflow_dispatch') {
    // Landing commits and explicit operator requests always get the full suite
    // and a fresh documentation build, regardless of changed-file filtering.
    return { behavioral: true, documentation: true, reason: 'full-validation event' };
  }
  if (eventName !== 'pull_request') {
    throw new Error('Unsupported validation event: ' + eventName);
  }
  if (!Array.isArray(files) || files.length === 0 ||
      !Number.isSafeInteger(expectedCount) || expectedCount < 1 ||
      expectedCount !== files.length || files.length >= 3000) {
    throw new Error('Incomplete or empty pull request changed-file listing');
  }

  const paths = [];
  for (const file of files) {
    if (!file || !validPath(file.filename) || typeof file.status !== 'string') {
      throw new Error('Invalid changed-file record');
    }
    paths.push(file.filename);
    if (file.status === 'renamed' || file.status === 'copied') {
      if (!validPath(file.previous_filename)) {
        throw new Error('Rename/copy missing original path');
      }
      paths.push(file.previous_filename);
    } else if (file.previous_filename !== undefined &&
               file.previous_filename !== null) {
      if (!validPath(file.previous_filename)) {
        throw new Error('Invalid previous filename');
      }
      paths.push(file.previous_filename);
    }
  }

  const behavioral = paths.some((path) => !isDocumentationOnly(path));
  const documentation = paths.some(affectsPages);
  if (!behavioral && !documentation) {
    throw new Error('No required validation selected');
  }
  return {
    behavioral,
    documentation,
    reason: behavioral ? 'product/infrastructure/mixed paths' : 'documentation-only paths'
  };
}

module.exports = { classify, isDocumentationOnly, affectsPages };
