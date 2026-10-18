'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const publish = require('../../.github/scripts/publish-release.js');
const { validateReleaseChangelog, requiresTaggedChangelogValidation } = require('../../.github/scripts/validate-release-changelog.js');

const TAG = 'v0.4.0';
const DATE = '2026-10-15';
const VALID_CHANGELOG = '## [0.4.0] - ' + DATE +
  '\n\n### Added\n\n- Verified stable bootstrap.\n\n' +
  '## [0.3.0] - Unreleased\n\n- Historical release candidate notes.\n';
const BASE = 'a'.repeat(40);
const COMMIT = 'b'.repeat(40);
const TREE = 'c'.repeat(40);
const PS_BLOB = 'd'.repeat(40);
const SH_BLOB = 'e'.repeat(40);
const hash = (data) => crypto.createHash('sha256').update(data).digest('hex');

async function exercise(options = {}) {
  const priorCwd = process.cwd();
  const priorEnv = { ...process.env };
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'publisher-test-'));
  const ps = "$ToolReleaseIdentity = '" + (options.badIdentity ? 'v0.0.1' : TAG) + "'\n" +
    (options.duplicateIdentity ? "$ToolReleaseIdentity = '" + TAG + "'\n" : '');
  const sh = 'TOOL_RELEASE_IDENTITY="' + (options.badBashIdentity ? 'v0.0.1' : TAG) + '"\n';
  const manifest = hash(ps) + '  isolated-dotnet-sdk.ps1\n' +
    hash(sh) + '  isolated-dotnet-sdk.sh\n';
  const notes = 'Release notes from the checked-out commit.\n';
  const changelog = options.changelog === undefined ? VALID_CHANGELOG : options.changelog;
  const calls = [];
  const warnings = [];
  const outputs = {};
  const summary = {
    addHeading() { return this; },
    addList() { return this; },
    addCodeBlock() { return this; },
    async write() {
      calls.push('summary.write');
      if (options.failAt === 'summary.write') throw new Error('injected failure: summary.write');
    }
  };
  const core = {
    warning(message) { warnings.push(message); },
    info() {},
    summary,
    setOutput(name, value) { outputs[name] = value; }
  };
  const state = {
    tag: false,
    release: null,
    deleted: [],
    preExisting: options.preExistingDraft
      ? { id: 99, tag_name: TAG, draft: true, prerelease: false }
      : null
  };
  const identity = { owner: 'example', repo: 'publisher-test' };
  const metadata = () => ({
    id: 42,
    tag_name: TAG,
    name: TAG,
    body: notes,
    draft: true,
    prerelease: false,
    published_at: null,
    html_url: 'https://example.invalid/releases/' + TAG
  });
  const respond = (name, value) => {
    calls.push(name);
    if (options.failAt === name ||
      (options.failAfterPublication === name && state.release && !state.release.draft)) {
      throw new Error('injected failure: ' + name);
    }
    const override = options.responses && options.responses[name];
    return override ? override(value, state) : value;
  };
  const git = {
    async getCommit({ commit_sha }) {
      return respond('getCommit', { data: commit_sha === BASE
        ? { tree: { sha: 'f'.repeat(40) } }
        : { parents: [{ sha: options.wrongParent ? '0'.repeat(40) : BASE }],
            tree: { sha: TREE } } });
    },
    async createBlob({ content }) {
      const script = Buffer.from(content, 'base64').toString('utf8');
      return respond('createBlob', { data: { sha: script === ps ? PS_BLOB : SH_BLOB } });
    },
    async createTree() { return respond('createTree', { data: { sha: TREE } }); },
    async createCommit() { return respond('createCommit', { data: { sha: COMMIT } }); },
    async getTree() {
      return respond('getTree', { data: { tree: [
        { path: 'isolated-dotnet-sdk.ps1', sha: options.wrongTree ? BASE : PS_BLOB, mode: '100644', type: 'blob' },
        { path: 'isolated-dotnet-sdk.sh', sha: SH_BLOB, mode: '100755', type: 'blob' }
      ] } });
    },
    async createRef() {
      const result = respond('createRef', { data: { ref: 'refs/tags/' + TAG } });
      state.tag = true;
      return result;
    },
    async getRef() {
      return respond('getRef', { data: { object: {
        type: 'commit', sha: options.wrongTag ? BASE : COMMIT
      } } });
    },
    async deleteRef() {
      const result = respond('deleteRef', { data: {} });
      state.tag = false;
      state.deleted.push('tag');
      return result;
    }
  };
  const repos = {
    async compareCommits() {
      return respond('compareCommits', { data: {
        ahead_by: options.wrongDiff ? 2 : 1,
        behind_by: 0,
        files: [{ filename: 'isolated-dotnet-sdk.ps1' }, { filename: 'isolated-dotnet-sdk.sh' }]
      } });
    },
    async createRelease() {
      const result = respond('createRelease', { data: metadata() });
      state.release = { ...result.data };
      return result;
    },
    async uploadReleaseAsset() {
      return respond('uploadReleaseAsset', { data: {
        id: 7, name: 'SHA256SUMS', state: options.badUpload ? 'new' : 'uploaded'
      } });
    },
    async getRelease() {
      return respond('getRelease', { data: options.badDraft && state.release.draft
        ? { ...state.release, body: 'wrong notes' } : { ...state.release } });
    },
    async updateRelease() {
      if (options.publicOnError) {
        // GitHub may complete the mutation but lose the response.
        state.release.draft = false;
        state.release.published_at = (options.publishedAt || '2026-10-15T00:00:00Z');
      }
      const response = respond('updateRelease', { data: {
        ...state.release, draft: options.badPublishResponse ? true : false,
        published_at: (options.publishedAt || '2026-10-15T00:00:00Z')
      } });
      state.release.draft = false;
      state.release.published_at = (options.publishedAt || '2026-10-15T00:00:00Z');
      return response;
    },
    async getReleaseByTag() {
      return respond('getReleaseByTag', { data: { id: options.wrongByTag ? 99 : 42 } });
    },
    async getLatestRelease() {
      return respond('getLatestRelease', { data: { id: 42 } });
    },
    async deleteRelease({ release_id }) {
      const result = respond('deleteRelease', { data: {} });
      state.deleted.push(release_id);
      if (state.release && release_id === state.release.id) state.release = null;
      if (state.preExisting && release_id === state.preExisting.id) state.preExisting = null;
      return result;
    },
    listReleaseAssets() {},
    listReleases() {}
  };
  const github = {
    rest: { git, repos },
    async paginate(method) {
      if (method === repos.listReleaseAssets) return respond('listReleaseAssets',
        state.release ? [{ id: 7, name: 'SHA256SUMS', state: options.badAsset ? 'new' : 'uploaded' }] : []);
      if (method === repos.listReleases) {
        const list = [state.preExisting, state.release && (
          options.staleDraftOnPublic && !state.release.draft
            ? { ...state.release, draft: true } : state.release
        )].filter(Boolean);
        return respond('listReleases', list);
      }
      throw new Error('Unexpected paginate method');
    },
    async request() {
      return respond('downloadAsset', { data: options.badDownload
        ? Buffer.from('corrupted') : Buffer.from(manifest) });
    }
  };
  fs.writeFileSync(path.join(directory, 'isolated-dotnet-sdk.ps1'), ps);
  fs.writeFileSync(path.join(directory, 'isolated-dotnet-sdk.sh'), sh);
  fs.writeFileSync(path.join(directory, 'SHA256SUMS'), options.badManifest ? 'incorrect manifest\n' : manifest);
  fs.writeFileSync(path.join(directory, 'notes.md'), notes);
  fs.writeFileSync(path.join(directory, 'CHANGELOG.md'), changelog);
  let error;
  try {
    process.chdir(directory);
    Object.assign(process.env, {
      RELEASE_TAG: TAG,
      RELEASE_DATE: options.releaseDate || DATE,
      EXPECTED_SHA: BASE,
      RELEASE_NOTES_PATH: 'notes.md',
      CHECKSUM_PATH: 'SHA256SUMS',
      MANIFEST_SHA256: options.wrongManifestHash ? '0'.repeat(64) : hash(options.badManifest ? 'incorrect manifest\n' : manifest),
      POWERSHELL_SHA256: options.wrongScriptHash ? '0'.repeat(64) : hash(ps),
      BASH_SHA256: options.wrongBashHash ? '0'.repeat(64) : hash(sh)
    });
    try {
      await publish({ github, context: { repo: identity }, core });
    } catch (caught) {
      error = caught;
    }
  } finally {
    process.chdir(priorCwd);
    process.env = priorEnv;
    fs.rmSync(directory, { recursive: true, force: true });
  }
  return { error, calls, state, outputs, warnings };
}

function failed(result, reason, { summaryWriteAttempted = false } = {}) {
  assert.ok(result.error, 'publisher must reject');
  assert.match(result.error.message, reason);
  assert.equal(result.outputs.release_url, undefined, 'no publication success output');
  assert.equal(result.outputs.release_id, undefined, 'no release id success output');
  assert.equal(result.outputs.release_commit_sha, undefined, 'no commit success output');
  if (!summaryWriteAttempted) {
    assert.ok(!result.calls.includes('summary.write'), 'no publication success summary');
  }
}

test('independent tagged changelog verification preserves historical releases only', () => {
  for (const historical of ['v0.1.0', 'v0.2.0', 'v0.3.0', 'v0.4.0']) {
    assert.equal(requiresTaggedChangelogValidation(historical), false, historical);
  }
  for (const future of ['v0.0.1', 'v0.3.1', 'v0.4.1', 'v0.5.0', 'v1.0.0', 'v2.11.0']) {
    assert.equal(requiresTaggedChangelogValidation(future), true, future);
  }
  assert.throws(() => requiresTaggedChangelogValidation('v0.5.0-rc.1'), /vMAJOR.MINOR.PATCH/);
  assert.throws(() => requiresTaggedChangelogValidation('0.5.0'), /vMAJOR.MINOR.PATCH/);
  assert.throws(() => requiresTaggedChangelogValidation('v999999999999999999999.0.0'), /safe integers/);
});

test('future release tagged verification rejects undated or candidate entries', () => {
  const futureTag = 'v0.5.0';
  const date = '2026-12-01';
  const good = '## [0.5.0] - ' + date + '\n\n- Published changes.\n';
  assert.equal(requiresTaggedChangelogValidation(futureTag), true);
  assert.deepEqual(validateReleaseChangelog(good, futureTag, date), { tag: futureTag, date });
  assert.throws(() => validateReleaseChangelog(good.replace(date, 'Unreleased'), futureTag, date), /exact UTC publication date/);
  assert.throws(() => validateReleaseChangelog(good.replace('Published changes.', 'Release candidate changes.'), futureTag, date), /provisional or candidate/);
});

test('changelog gate validates the exact release entry, not older versions', () => {
  assert.deepEqual(validateReleaseChangelog(VALID_CHANGELOG, TAG, DATE), { tag: TAG, date: DATE });
});

for (const scenario of [
  { name: 'Unreleased heading', changelog: VALID_CHANGELOG.replace('## [0.4.0] - ' + DATE, '## [0.4.0] - Unreleased'), error: /exact UTC publication date/ },
  { name: 'wrong publication day', changelog: VALID_CHANGELOG.replace(DATE, '2026-10-14'), error: /exact UTC publication date/ },
  { name: 'candidate language', changelog: VALID_CHANGELOG.replace('Verified stable bootstrap.', 'v0.4.0 candidate is ready.'), error: /provisional or candidate/ },
  { name: 'still awaiting publication', changelog: VALID_CHANGELOG.replace('Verified stable bootstrap.', 'Not yet published.'), error: /provisional or candidate/ },
  { name: 'missing entry', changelog: VALID_CHANGELOG.replace('## [0.4.0]', '## [9.9.9]'), error: /exactly one release entry/ },
  { name: 'duplicate entry', changelog: VALID_CHANGELOG + '## [0.4.0] - ' + DATE + '\n\n- Duplicate.\n', error: /exactly one release entry/ },
  { name: 'empty entry', changelog: '## [0.4.0] - ' + DATE + '\n## [0.3.0] - 2026-10-01\n- Old.\n', error: /no release details/ },
  { name: 'missing release date', changelog: VALID_CHANGELOG, date: '2026-10-16', error: /exact UTC publication date/ },
  { name: 'invalid calendar date', changelog: VALID_CHANGELOG, date: '2026-02-30', error: /not a real calendar date/ }
]) {
  test('fail before tag creation: ' + scenario.name, async () => {
    const result = await exercise({ changelog: scenario.changelog, releaseDate: scenario.date || DATE });
    failed(result, scenario.error);
    assert.ok(!result.calls.includes('createRef'), 'invalid changelog must not create a tag');
    assert.ok(!result.calls.includes('createCommit'), 'invalid changelog must not derive a release commit');
  });
}

test('published_at must match the finalized UTC changelog date, preserving public state if not', async () => {
  const result = await exercise({ publishedAt: '2026-10-16T00:01:00Z' });
  failed(result, /UTC date must match/);
  assert.equal(result.state.tag, true);
  assert.equal(result.state.release.draft, false);
  assert.deepEqual(result.state.deleted, [], 'published release must never be auto-removed');
});

test('valid transaction verifies the derived identity and checksum asset before publishing', async () => {
  const result = await exercise();
  assert.equal(result.error, undefined);
  assert.equal(result.outputs.release_commit_sha, COMMIT);
  assert.equal(result.outputs.release_id, '42');
  assert.equal(result.state.release.draft, false);
  assert.deepEqual(result.state.deleted, []);
  assert.ok(result.calls.indexOf('downloadAsset') < result.calls.indexOf('updateRelease'));
  assert.ok(result.calls.includes('getReleaseByTag'));
  assert.ok(result.calls.includes('getLatestRelease'));
});

test('pre-existing same-tag draft is never deleted after tag verification fails', async () => {
  const result = await exercise({ preExistingDraft: true, wrongTag: true });
  failed(result, /Tag .* does not point directly/);
  assert.ok(result.state.preExisting, 'pre-existing draft remains intact');
  assert.ok(!result.state.deleted.includes(99), 'pre-existing draft not deleted');
});

test('ambiguous publication response must not delete an already-public release or tag', async () => {
  const result = await exercise({
    failAt: 'updateRelease', publicOnError: true, staleDraftOnPublic: true
  });
  failed(result, /injected failure: updateRelease/);
  assert.equal(result.state.release.draft, false, 'public release preserved');
  assert.equal(result.state.tag, true, 'tag preserved');
  assert.deepEqual(result.state.deleted, [], 'no destructive cleanup once publishing was attempted');
});

for (const scenario of [
  { name: 'mismatched PowerShell identity', options: { badIdentity: true }, error: /PowerShell release source/ },
  { name: 'duplicate PowerShell identity', options: { duplicateIdentity: true }, error: /PowerShell release source/ },
  { name: 'mismatched Bash identity', options: { badBashIdentity: true }, error: /Bash release source/ },
  { name: 'malformed checksum manifest', options: { badManifest: true }, error: /manifest|checksum/i },
  { name: 'wrong manifest hash', options: { wrongManifestHash: true }, error: /checksum|manifest/i },
  { name: 'wrong script hash', options: { wrongScriptHash: true }, error: /script SHA-256/i },
  { name: 'wrong Bash hash', options: { wrongBashHash: true }, error: /script SHA-256/i },
  { name: 'wrong derived parent', options: { wrongParent: true }, error: /only parent/ },
  { name: 'wrong derived tree', options: { wrongTree: true }, error: /stamped PowerShell source bytes/ },
  { name: 'unexpected derived change set', options: { wrongDiff: true }, error: /only by the two stamped/ },
  { name: 'wrong tag commit', options: { wrongTag: true }, error: /Tag .* does not point directly/ },
  { name: 'rejected checksum upload', options: { badUpload: true }, error: /did not confirm the SHA256SUMS upload/ },
  { name: 'invalid draft release metadata', options: { badDraft: true }, error: /Release metadata verification failed/ },
  { name: 'unexpected asset state', options: { badAsset: true }, error: /exactly one uploaded SHA256SUMS asset/ },
  { name: 'asset checksum corruption', options: { badDownload: true }, error: /Uploaded SHA256SUMS bytes/ },
  { name: 'inconsistent publication response', options: { badPublishResponse: true }, error: /did not confirm publication/ },
  { name: 'incorrect release-by-tag lookup', options: { wrongByTag: true }, error: /lookup by tag/ }
]) {
  test('fail closed: ' + scenario.name, async () => {
    const result = await exercise(scenario.options);
    failed(result, scenario.error);
    if (scenario.name !== 'inconsistent publication response' && scenario.name !== 'incorrect release-by-tag lookup') {
      assert.ok(!result.calls.includes('updateRelease'), 'must not reach publication');
    }
  });
}

for (const stage of [
  'createRef', 'getRef', 'createRelease', 'uploadReleaseAsset',
  'getRelease', 'listReleaseAssets', 'downloadAsset'
]) {
  test('pre-publication injected ' + stage + ' failure retains only safe cleanup', async () => {
    const result = await exercise({ failAt: stage });
    failed(result, new RegExp('injected failure: ' + stage));
    assert.ok(!result.calls.includes('updateRelease'), 'no public transition');
    if (stage === 'getRelease') {
      // A failing ownership check cannot safely authorize destructive cleanup.
      assert.equal(result.state.tag, true, 'uncertain tag is retained');
      assert.ok(result.state.release, 'unverified draft is retained');
      assert.ok(result.warnings.some((message) => /cleanup also failed/.test(message)));
    } else if (stage === 'createRelease') {
      assert.equal(result.state.tag, true, 'ambiguous draft creation leaves tag for investigation');
      assert.equal(result.state.release, null, 'no locally confirmed draft');
      assert.ok(result.warnings.some((message) => /Draft creation .* not confirmed/.test(message)));
    } else {
      assert.equal(result.state.tag, false, 'known owned incomplete tag removed, if created');
      assert.equal(result.state.release, null, 'known owned draft removed, if created');
    }
    assert.ok(!result.state.deleted.includes(99));
  });
}

test('cleanup API failure cannot replace original publisher error', async () => {
  const result = await exercise({
    wrongTag: true, responses: {
      deleteRef() { throw new Error('cleanup refused by GitHub'); }
    }
  });
  failed(result, /Tag .* does not point directly/);
  assert.ok(result.warnings.some((warning) => /cleanup also failed.*cleanup refused/.test(warning)));
});

test('post-publication verification failure keeps release and tag public', async () => {
  const result = await exercise({ failAfterPublication: 'getRelease' });
  failed(result, /injected failure: getRelease/);
  assert.equal(result.state.release.draft, false);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
  assert.ok(result.warnings.some((warning) => /already public|publication/i.test(warning)));
});

test('missing GitHub API response fails without a false publication success', async () => {
  const result = await exercise({ responses: {
    uploadReleaseAsset() { return { data: {} }; }
  } });
  failed(result, /SHA256SUMS upload/);
});

test('pre-existing releases remain intact even if draft creation fails', async () => {
  const result = await exercise({ preExistingDraft: true, failAt: 'createRelease' });
  failed(result, /injected failure: createRelease/);
  assert.ok(result.state.preExisting);
  assert.deepEqual(result.state.deleted, []);
});

test('incomplete cleanup retains the original error and leaves the tag for investigation', async () => {
  const result = await exercise({ wrongTag: true, responses: {
    listReleases() { throw new Error('cannot establish remote release state'); }
  } });
  failed(result, /Tag .* does not point directly/);
  assert.equal(result.state.tag, true);
  assert.ok(result.warnings.some((warning) => /cleanup also failed.*cannot establish remote/.test(warning)));
});

test('ambiguous successful-publication response preserves remote public state', async () => {
  const result = await exercise({ badPublishResponse: true, staleDraftOnPublic: true });
  failed(result, /did not confirm publication/);
  assert.equal(result.state.release.draft, false);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
});

test('invalid draft creation response does not fabricate ownership or publish', async () => {
  const result = await exercise({ responses: {
    createRelease(response) { return { data: { ...response.data, id: null } }; }
  } });
  failed(result, /did not confirm ownership of the draft release/);
  assert.equal(result.state.tag, true, 'unknown remote creation prevents tag cleanup');
  assert.ok(!result.calls.includes('updateRelease'));
});

test('summary failure is reported without publishing a success output or deleting public state', async () => {
  const result = await exercise({ failAt: 'summary.write' });
  failed(result, /injected failure: summary.write/, { summaryWriteAttempted: true });
  assert.ok(result.calls.includes('summary.write'), 'summary write actually failed');
  assert.equal(result.state.release.draft, false);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
});

test('failure deleting an owned draft preserves the original integrity failure', async () => {
  const result = await exercise({ badAsset: true, responses: {
    deleteRelease() { throw new Error('GitHub refused draft deletion'); }
  } });
  failed(result, /exactly one uploaded SHA256SUMS asset/);
  assert.ok(result.warnings.some((message) => /cleanup also failed.*refused draft deletion/.test(message)));
  assert.ok(result.state.release && result.state.release.draft);
  assert.equal(result.state.tag, true);
});

test('an unrelated same-tag draft blocks cleanup even when the current draft is incomplete', async () => {
  const result = await exercise({ preExistingDraft: true, badAsset: true });
  failed(result, /exactly one uploaded SHA256SUMS asset/);
  assert.ok(result.state.preExisting);
  assert.ok(result.state.release);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
});

test('failed publication request retains uncertain draft and tag for investigation', async () => {
  const result = await exercise({ failAt: 'updateRelease' });
  failed(result, /injected failure: updateRelease/);
  assert.equal(result.state.release.draft, true);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
});

test('post-publication tag-read failure cannot trigger rollback', async () => {
  const result = await exercise({ failAfterPublication: 'getRef' });
  failed(result, /injected failure: getRef/);
  assert.equal(result.state.release.draft, false);
  assert.equal(result.state.tag, true);
  assert.deepEqual(result.state.deleted, []);
});

test('missing derived commit identity never reaches tag creation', async () => {
  const result = await exercise({ responses: {
    createCommit() { return { data: {} }; }
  } });
  failed(result, /verification was requested before the derived release commit/);
  assert.ok(!result.calls.includes('createRef'));
});
