from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace(path, old, new):
    p = root / path
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old!r}")
    p.write_text(text.replace(old, new))

# Preserve the failed native command's status instead of the status of `!`.
replace(
    "isolated-dotnet-sdk.sh",
    '''    if ! curl -fsSL "$metadata_url" -o "$metadata_file"; then
        status=$?
        tool_fail "Unable to load Microsoft release metadata for SDK $VERSION with exit code $status."
    fi
''',
    '''    if curl -fsSL "$metadata_url" -o "$metadata_file"; then
        :
    else
        status=$?
        tool_fail "Unable to load Microsoft release metadata for SDK $VERSION with exit code $status."
    fi
''',
)
replace(
    "isolated-dotnet-sdk.sh",
    '''    if ! curl -fsSL "$artifact_url" -o "$archive_file"; then
        status=$?
        tool_fail "Unable to download the .NET SDK $VERSION payload with exit code $status."
    fi
''',
    '''    if curl -fsSL "$artifact_url" -o "$archive_file"; then
        :
    else
        status=$?
        tool_fail "Unable to download the .NET SDK $VERSION payload with exit code $status."
    fi
''',
)
replace(
    "isolated-dotnet-sdk.sh",
    '''    if ! tar -xzf "$archive_file" -C "$staging_dir"; then
        status=$?
        tool_fail "Unable to extract the verified .NET SDK $VERSION payload with exit code $status."
    fi
''',
    '''    if tar -xzf "$archive_file" -C "$staging_dir"; then
        :
    else
        status=$?
        tool_fail "Unable to extract the verified .NET SDK $VERSION payload with exit code $status."
    fi
''',
)

# Match the real Microsoft releases.json field layout so the fixture exercises the
# same parsing path instead of failing before the transaction behavior under test.
replace(
    "tests/bash/sdk-payload-fixture.bash",
    '''          { "rid": "$rid", "url": "$artifact_url", "hash": "$hash" }
''',
    '''          {
            "rid": "$rid",
            "url": "$artifact_url",
            "hash": "$hash"
          }
''',
)

print("issue 72 Bash fixes applied")
