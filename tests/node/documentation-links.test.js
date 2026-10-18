'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { linksFromMarkdown, localTarget, checkLinks } =
  require('../../.github/scripts/check-documentation-links.js');

test('scanner ignores fenced examples and reads local links', () => {
  const source = '[good](guide.md) [remote](https://example.com/x)\n' +
    '\x60\x60\x60md\n[ignored](missing.md)\n\x60\x60\x60\n' +
    '[anchor](#intro) ![image](../assets/logo.svg)';
  assert.deepEqual(linksFromMarkdown(source),
    ['guide.md', 'https://example.com/x', '#intro', '../assets/logo.svg']);
});
test('external links ignored and escaping repository rejected', () => {
  const root = path.resolve(os.tmpdir(), 'ci-link-check');
  const file = path.join(root, 'docs', 'README.md');
  assert.equal(localTarget(root, file, 'https://example.com'), null);
  assert.equal(localTarget(root, file, '#section'), null);
  assert.throws(() => localTarget(root, file, '../../../outside.md'), /escapes/);
});
test('finds missing local targets', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ci-doc-links-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'docs'));
  fs.writeFileSync(path.join(root, 'README.md'), '[Documentation](docs/README.md)');
  fs.writeFileSync(path.join(root, 'docs', 'README.md'), '[Guide](guide.md)');
  fs.writeFileSync(path.join(root, 'docs', 'guide.md'), 'Welcome');
  let result = checkLinks(root);
  assert.equal(result.checked, 2);
  assert.deepEqual(result.errors, []);
  fs.writeFileSync(path.join(root, 'docs', 'README.md'), '[Guide](deleted.md)');
  result = checkLinks(root);
  assert.equal(result.errors.length, 1);
  assert.match(result.errors[0], /deleted.md/);
});
