const fs = require('fs');
const crypto = require('crypto');

module.exports = async ({ github, context, core }) => {
  const required = [
    'RELEASE_TAG',
    'EXPECTED_SHA',
    'RELEASE_NOTES_PATH',
    'CHECKSUM_PATH',
    'MANIFEST_SHA256',
    'POWERSHELL_SHA256',
    'BASH_SHA256'
  ];

  for (const name of required) {
    if (!process.env[name]) {
      throw new Error(`Required environment variable ${name} is missing.`);
    }
  }

  const tag = process.env.RELEASE_TAG;
  const expectedSha = process.env.EXPECTED_SHA;
  const releaseNotesPath = process.env.RELEASE_NOTES_PATH;
  const checksumPath = process.env.CHECKSUM_PATH;
  const { owner, repo } = context.repo;
  const releaseBody = fs.readFileSync(releaseNotesPath, 'utf8');
  const checksumBytes = fs.readFileSync(checksumPath);
  const powerShellBytes = fs.readFileSync('isolated-dotnet-sdk.ps1');
  const bashBytes = fs.readFileSync('isolated-dotnet-sdk.sh');

  let releaseCommitSha = null;
  let powerShellBlobSha = null;
  let bashBlobSha = null;
  let tagCreated = false;
  let releaseId = null;
  let published = false;

  const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

  const bufferFromResponse = (data) => {
    if (Buffer.isBuffer(data)) return data;
    if (data instanceof ArrayBuffer) return Buffer.from(data);
    if (ArrayBuffer.isView(data)) {
      return Buffer.from(data.buffer, data.byteOffset, data.byteLength);
    }
    if (typeof data === 'string') return Buffer.from(data);
    throw new Error('GitHub did not return release asset bytes.');
  };

  const verifyStampedIdentity = () => {
    const powerShell = powerShellBytes.toString('utf8');
    const bash = bashBytes.toString('utf8');
    const expectedPowerShellMarker = `$ToolReleaseIdentity = '${tag}'`;
    const expectedBashMarker = `TOOL_RELEASE_IDENTITY="${tag}"`;

    if (!powerShell.includes(expectedPowerShellMarker) || powerShell.includes("$ToolReleaseIdentity = 'development'")) {
      throw new Error(`PowerShell release source is not stamped exactly for ${tag}.`);
    }
    if (!bash.includes(expectedBashMarker) || bash.includes('TOOL_RELEASE_IDENTITY="development"')) {
      throw new Error(`Bash release source is not stamped exactly for ${tag}.`);
    }
  };

  const createReleaseCommit = async () => {
    verifyStampedIdentity();

    const baseCommit = await github.rest.git.getCommit({ owner, repo, commit_sha: expectedSha });
    const powerShellBlob = await github.rest.git.createBlob({
      owner,
      repo,
      content: powerShellBytes.toString('base64'),
      encoding: 'base64'
    });
    const bashBlob = await github.rest.git.createBlob({
      owner,
      repo,
      content: bashBytes.toString('base64'),
      encoding: 'base64'
    });
    powerShellBlobSha = powerShellBlob.data.sha;
    bashBlobSha = bashBlob.data.sha;

    const releaseTree = await github.rest.git.createTree({
      owner,
      repo,
      base_tree: baseCommit.data.tree.sha,
      tree: [
        {
          path: 'isolated-dotnet-sdk.ps1',
          mode: '100644',
          type: 'blob',
          sha: powerShellBlobSha
        },
        {
          path: 'isolated-dotnet-sdk.sh',
          mode: '100755',
          type: 'blob',
          sha: bashBlobSha
        }
      ]
    });

    const releaseCommit = await github.rest.git.createCommit({
      owner,
      repo,
      message: `release: stamp ${tag} tool identity`,
      tree: releaseTree.data.sha,
      parents: [expectedSha]
    });
    releaseCommitSha = releaseCommit.data.sha;
  };

  const verifyReleaseCommit = async () => {
    if (!releaseCommitSha || !powerShellBlobSha || !bashBlobSha) {
      throw new Error('Release commit verification was requested before the derived release commit was created.');
    }

    const commit = await github.rest.git.getCommit({ owner, repo, commit_sha: releaseCommitSha });
    if (commit.data.parents.length !== 1 || commit.data.parents[0].sha !== expectedSha) {
      throw new Error(`Derived release commit ${releaseCommitSha} must have ${expectedSha} as its only parent.`);
    }

    const tree = await github.rest.git.getTree({ owner, repo, tree_sha: commit.data.tree.sha });
    const entries = new Map(tree.data.tree.map((entry) => [entry.path, entry]));
    if (entries.get('isolated-dotnet-sdk.ps1')?.sha !== powerShellBlobSha) {
      throw new Error('Derived release commit does not contain the stamped PowerShell source bytes.');
    }
    if (entries.get('isolated-dotnet-sdk.sh')?.sha !== bashBlobSha) {
      throw new Error('Derived release commit does not contain the stamped Bash source bytes.');
    }

    const comparison = await github.rest.repos.compareCommits({
      owner,
      repo,
      base: expectedSha,
      head: releaseCommitSha
    });
    const changedFiles = (comparison.data.files || []).map((file) => file.filename).sort();
    const expectedFiles = ['isolated-dotnet-sdk.ps1', 'isolated-dotnet-sdk.sh'];
    if (
      comparison.data.ahead_by !== 1 ||
      comparison.data.behind_by !== 0 ||
      changedFiles.length !== expectedFiles.length ||
      changedFiles.some((file, index) => file !== expectedFiles[index])
    ) {
      throw new Error(`Derived release commit ${releaseCommitSha} must differ from ${expectedSha} only by the two stamped product scripts.`);
    }
  };

  const verifyTag = async () => {
    const ref = await github.rest.git.getRef({ owner, repo, ref: `tags/${tag}` });
    if (ref.data.object.type !== 'commit' || ref.data.object.sha !== releaseCommitSha) {
      throw new Error(`Tag ${tag} does not point directly to derived release commit ${releaseCommitSha}.`);
    }
  };

  const verifyRelease = async (shouldBeDraft) => {
    const release = await github.rest.repos.getRelease({ owner, repo, release_id: releaseId });
    const data = release.data;

    if (
      data.tag_name !== tag ||
      data.name !== tag ||
      data.draft !== shouldBeDraft ||
      data.prerelease !== false ||
      data.body !== releaseBody
    ) {
      throw new Error(`Release metadata verification failed for ${tag}.`);
    }

    if (!shouldBeDraft && !data.published_at) {
      throw new Error(`Published release ${tag} is missing published_at.`);
    }

    const assets = await github.paginate(github.rest.repos.listReleaseAssets, {
      owner,
      repo,
      release_id: releaseId,
      per_page: 100
    });

    if (assets.length !== 1 || assets[0].name !== 'SHA256SUMS' || assets[0].state !== 'uploaded') {
      throw new Error(`Release ${tag} must contain exactly one uploaded SHA256SUMS asset.`);
    }

    const downloaded = await github.request('GET /repos/{owner}/{repo}/releases/assets/{asset_id}', {
      owner,
      repo,
      asset_id: assets[0].id,
      headers: { accept: 'application/octet-stream' }
    });
    const downloadedBytes = bufferFromResponse(downloaded.data);

    if (!checksumBytes.equals(downloadedBytes)) {
      throw new Error(`Uploaded SHA256SUMS bytes do not match the generated manifest for ${tag}.`);
    }

    return data;
  };

  const cleanupBeforePublication = async () => {
    let publicReleaseExists = false;
    const releases = await github.paginate(github.rest.repos.listReleases, {
      owner,
      repo,
      per_page: 100
    });
    const matches = releases.filter((release) => release.tag_name === tag);

    for (const release of matches) {
      if (release.draft) {
        core.warning(`Deleting incomplete draft release ${release.id}.`);
        await github.rest.repos.deleteRelease({ owner, repo, release_id: release.id });
      } else {
        publicReleaseExists = true;
        core.warning(`A public ${tag} release exists; cleanup will not delete the release or tag.`);
      }
    }

    if (tagCreated && !publicReleaseExists) {
      try {
        core.warning(`Deleting incomplete tag ${tag}.`);
        await github.rest.git.deleteRef({ owner, repo, ref: `tags/${tag}` });
      } catch (error) {
        if (error.status !== 404) throw error;
      }
    }
  };

  const verifyLatestRelease = async () => {
    let lastSeen = null;
    for (let attempt = 1; attempt <= 5; attempt += 1) {
      const latest = await github.rest.repos.getLatestRelease({ owner, repo });
      lastSeen = latest.data.id;
      if (latest.data.id === releaseId) return;
      if (attempt < 5) await sleep(2000);
    }
    throw new Error(`Published ${tag} is not the repository's latest release; last observed release id ${lastSeen}.`);
  };

  try {
    await createReleaseCommit();
    await verifyReleaseCommit();

    await github.rest.git.createRef({
      owner,
      repo,
      ref: `refs/tags/${tag}`,
      sha: releaseCommitSha
    });
    tagCreated = true;
    await verifyTag();

    const created = await github.rest.repos.createRelease({
      owner,
      repo,
      tag_name: tag,
      target_commitish: releaseCommitSha,
      name: tag,
      body: releaseBody,
      draft: true,
      prerelease: false
    });
    releaseId = created.data.id;

    const upload = await github.rest.repos.uploadReleaseAsset({
      owner,
      repo,
      release_id: releaseId,
      name: 'SHA256SUMS',
      data: checksumBytes,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': checksumBytes.length
      }
    });

    if (upload.data.name !== 'SHA256SUMS' || upload.data.state !== 'uploaded') {
      throw new Error(`GitHub did not confirm the SHA256SUMS upload for ${tag}.`);
    }

    await verifyReleaseCommit();
    await verifyTag();
    await verifyRelease(true);

    const updated = await github.rest.repos.updateRelease({
      owner,
      repo,
      release_id: releaseId,
      draft: false,
      make_latest: 'true'
    });

    if (updated.data.draft !== false || updated.data.prerelease !== false || !updated.data.published_at) {
      throw new Error(`GitHub did not confirm publication of ${tag}.`);
    }
    published = true;

    await verifyReleaseCommit();
    await verifyTag();
    const finalRelease = await verifyRelease(false);

    const byTag = await github.rest.repos.getReleaseByTag({ owner, repo, tag });
    if (byTag.data.id !== releaseId) {
      throw new Error(`Release lookup by tag does not resolve to the published ${tag} release.`);
    }

    await verifyLatestRelease();

    const localManifestHash = crypto.createHash('sha256').update(checksumBytes).digest('hex');
    if (localManifestHash !== process.env.MANIFEST_SHA256) {
      throw new Error('Workflow checksum output changed before publication summary generation.');
    }

    core.setOutput('release_url', finalRelease.html_url);
    core.setOutput('release_id', String(releaseId));
    core.setOutput('release_commit_sha', releaseCommitSha);

    await core.summary
      .addHeading(`Published ${tag}`)
      .addList([
        `Release: ${finalRelease.html_url}`,
        `Validated main commit: ${expectedSha}`,
        `Derived release commit: ${releaseCommitSha}`,
        `SHA256SUMS SHA-256: ${process.env.MANIFEST_SHA256}`,
        `PowerShell script SHA-256: ${process.env.POWERSHELL_SHA256}`,
        `Bash script SHA-256: ${process.env.BASH_SHA256}`
      ])
      .addCodeBlock(checksumBytes.toString('utf8'), 'text')
      .write();
  } catch (error) {
    if (!published) {
      try {
        await cleanupBeforePublication();
      } catch (cleanupError) {
        core.warning(`Pre-publication cleanup also failed: ${cleanupError.message}`);
      }
    } else {
      core.warning('The release is already public; automatic cleanup is intentionally disabled after publication.');
    }
    throw error;
  }
};
