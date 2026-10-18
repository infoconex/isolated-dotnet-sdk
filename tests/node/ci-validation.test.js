'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { classify, isDocumentationOnly, affectsPages } =
  require('../../.github/scripts/classify-ci-changes.js');
const { checkGate } = require('../../.github/scripts/check-validation-gate.js');

function file(filename, status = 'modified', previous_filename) {
  return { filename, status, ...(previous_filename ? { previous_filename } : {}) };
}
function decide(paths) { return classify('pull_request', paths, paths.length); }
function gate(overrides = {}) {
  return {
    classification: 'success',
    behavioral: 'true',
    documentation: 'false',
    docsJob: 'skipped',
    bash: 'success',
    powershell: 'success',
    ...overrides
  };
}

test('strict documentation allowlist and Pages inputs', () => {
  assert.equal(isDocumentationOnly('README.md'), true);
  assert.equal(isDocumentationOnly('docs/training/session.md'), true);
  for (const path of ['CHANGELOG.md', 'AGENTS.md', '.github/release-notes/v0.5.0.md',
    'scripts/README.md', 'docs/picture.png', 'install.sh', '.github/workflows/validate.yml']) {
    assert.equal(isDocumentationOnly(path), false, path);
  }
  for (const path of ['docs/assets/image.png', 'assets/js/site.js', '_layouts/default.html',
    '.github/workflows/pages.yml', 'CHANGELOG.md', '.config/static-analysis.json']) {
    assert.equal(affectsPages(path), true, path);
  }
});

test('docs-only, source-only, mixed, and release-sensitive PR changes', () => {
  assert.deepEqual(decide([file('docs/training/README.md'), file('README.md')]),
    { behavioral: false, documentation: true, reason: 'documentation-only paths' });
  assert.deepEqual(decide([file('tests/bash/basic.bats')]),
    { behavioral: true, documentation: false, reason: 'product/infrastructure/mixed paths' });
  assert.deepEqual(decide([file('docs/README.md'), file('isolated-dotnet-sdk.ps1')]),
    { behavioral: true, documentation: true, reason: 'product/infrastructure/mixed paths' });
  for (const path of ['.github/workflows/validate.yml', '.github/scripts/publish-release.js',
    '.config/test-frameworks.json', '.github/release-notes/v0.5.0.md']) {
    assert.equal(decide([file(path)]).behavioral, true, path);
  }
});

test('renames and deletions classify both affected locations', () => {
  assert.equal(decide([file('docs/new.md', 'renamed', 'docs/old.md')]).behavioral, false);
  assert.equal(decide([file('docs/README.md', 'renamed', 'scripts/old.sh')]).behavioral, true);
  assert.equal(decide([file('scripts/new.sh', 'renamed', 'docs/old.md')]).documentation, true);
  assert.equal(decide([file('docs/deleted.md', 'removed')]).documentation, true);
});

test('explicit manual and integration pushes always require both paths', () => {
  for (const event of ['push', 'workflow_dispatch']) {
    assert.deepEqual(classify(event, [], undefined),
      { behavioral: true, documentation: true, reason: 'full-validation event' });
  }
});

test('incomplete, malformed or excessive changed-file data fails closed', () => {
  assert.throws(() => classify('pull_request', [], 0), /Incomplete/);
  assert.throws(() => classify('pull_request', [file('README.md')], 2), /Incomplete/);
  assert.throws(() => classify('pull_request', [file('../escape.md')], 1), /Invalid/);
  assert.throws(() => classify('pull_request', [file('docs/new.md', 'renamed')], 1), /original/);
  assert.throws(() => classify('schedule', [], 0), /Unsupported/);
  const many = Array.from({ length: 3000 }, (_, i) => file('docs/' + i + '.md'));
  assert.throws(() => classify('pull_request', many, 3000), /Incomplete/);
});

test('final gate succeeds only when requested jobs truly succeed', () => {
  // The docs job result gets its own field, never confused with the decision flag.
  assert.equal(checkGate(gate()), 'Required validation paths completed successfully');
  assert.equal(checkGate(gate({ behavioral: 'false', documentation: 'true',
    bash: 'skipped', powershell: 'skipped', docsJob: 'success' })),
    'Required validation paths completed successfully');
  assert.equal(checkGate(gate({ behavioral: 'true', documentation: 'true',
    docsJob: 'success' })), 'Required validation paths completed successfully');
  for (const state of [
    { classification: 'failure' },
    { classification: 'skipped' },
    { behavioral: '' },
    { behavioral: 'false', documentation: 'false' },
    { bash: 'skipped' },
    { powershell: 'cancelled' },
    { docsJob: 'failure', documentation: 'true' },
    { docsJob: 'skipped', documentation: 'true' },
    { docsJob: 'success', documentation: 'false' }
  ]) {
    assert.throws(() => checkGate(gate(state)), /./, JSON.stringify(state));
  }
});
