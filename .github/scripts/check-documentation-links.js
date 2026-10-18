'use strict';
const fs = require('node:fs');
const path = require('node:path');

function markdownFiles(root) {
  const files = [];
  for (const entry of ['README.md', 'CHANGELOG.md']) {
    if (fs.existsSync(path.join(root, entry))) files.push(path.join(root, entry));
  }
  function visit(dir) {
    if (!fs.existsSync(dir)) return;
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const location = path.join(dir, item.name);
      if (item.isDirectory()) visit(location);
      else if (item.isFile() && item.name.endsWith('.md')) files.push(location);
    }
  }
  visit(path.join(root, 'docs'));
  return files;
}
function linksFromMarkdown(contents) {
  const links = [];
  let fenced = false;
  for (const line of contents.split(/\r?\n/)) {
    if (/^\s*(?:\x60{3,}|~{3,})/.test(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    for (const match of line.matchAll(/!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+["'][^)]*["'])?\s*\)/g)) {
      links.push(match[1]);
    }
  }
  return links;
}
function localTarget(root, source, href) {
  if (/^(?:#|\/|[a-zA-Z][a-zA-Z0-9+.-]*:|\{\{)/.test(href)) return null;
  const plain = href.split('#')[0].split('?')[0];
  if (!plain) return null;
  let decoded;
  try { decoded = decodeURIComponent(plain); }
  catch { throw new Error('Invalid link encoding: ' + href); }
  const resolved = path.resolve(path.dirname(source), decoded);
  const relative = path.relative(root, resolved);
  if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
    throw new Error('Link escapes repository root: ' + href);
  }
  return resolved;
}
function existsTarget(destination) {
  return fs.existsSync(destination) ||
    fs.existsSync(destination + '.md') ||
    fs.existsSync(path.join(destination, 'README.md')) ||
    fs.existsSync(path.join(destination, 'index.md'));
}
function checkLinks(root) {
  const errors = [];
  let checked = 0;
  const files = markdownFiles(root);
  for (const source of files) {
    for (const href of linksFromMarkdown(fs.readFileSync(source, 'utf8'))) {
      try {
        const target = localTarget(root, source, href);
        if (!target) continue;
        checked += 1;
        if (!existsTarget(target)) errors.push(path.relative(root, source) + ': missing ' + href);
      } catch (error) {
        errors.push(path.relative(root, source) + ': ' + error.message);
      }
    }
  }
  return { files: files.length, checked, errors };
}
if (require.main === module) {
  const result = checkLinks(process.cwd());
  for (const error of result.errors) console.error(error);
  console.log('Checked ' + result.checked + ' local links in ' + result.files + ' Markdown files.');
  if (result.errors.length > 0) process.exitCode = 1;
}
module.exports = { markdownFiles, linksFromMarkdown, localTarget, existsTarget, checkLinks };
