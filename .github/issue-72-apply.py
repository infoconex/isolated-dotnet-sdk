from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def replace(path, old, new):
    p = ROOT / path
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old[:80]!r}")
    p.write_text(text.replace(old, new))


def replace_re(path, pattern, replacement, flags=re.S):
    p = ROOT / path
    text = p.read_text()
    new_text, count = re.subn(pattern, replacement, text, flags=flags)
    if count != 1:
        raise SystemExit(f"expected one match in {path}, found {count}")
    p.write_text(new_text)

# Bash: remove the installer-helper constants; payload resolution now comes from
# Microsoft's release metadata and is verified before extraction.
replace(
    "isolated-dotnet-sdk.sh",
    'DOTNET_INSTALL_COMMIT="da3ce11ba63f3dbb0fb835d41bda2665d5c48e84"\nDOTNET_INSTALL_SHA256="082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e"\nDOTNET_INSTALL_URL="https://raw.githubusercontent.com/dotnet/install-scripts/$DOTNET_INSTALL_COMMIT/src/dotnet-install.sh"\n',
    "",
)

bash_block = r'''cleanup_install_transaction() {
    local metadata_path="${1:-}"
    local archive_path="${2:-}"
    local staging_path="${3:-}"
    local cleanup_failed="false"

    if [[ -n "$metadata_path" && ( -e "$metadata_path" || -L "$metadata_path" ) ]]; then
        if ! rm -f "$metadata_path"; then
            tool_warn "Unable to clean SDK release metadata: $metadata_path"
            cleanup_failed="true"
        fi
    fi

    if [[ -n "$archive_path" && ( -e "$archive_path" || -L "$archive_path" ) ]]; then
        if ! rm -f "$archive_path"; then
            tool_warn "Unable to clean SDK payload archive: $archive_path"
            cleanup_failed="true"
        fi
    fi

    if [[ -n "$staging_path" && ( -e "$staging_path" || -L "$staging_path" ) ]]; then
        if ! rm -rf "$staging_path"; then
            tool_warn "Unable to clean install staging directory: $staging_path"
            cleanup_failed="true"
        fi
    fi

    [[ "$cleanup_failed" == "false" ]]
}

calculate_sha512() {
    local path="$1"

    if command -v sha512sum >/dev/null 2>&1; then
        sha512sum "$path" | awk '{print tolower($1)}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 512 "$path" | awk '{print tolower($1)}'
        return
    fi

    return 1
}

get_sdk_channel() {
    local core="${VERSION%%-*}"
    local major=""
    local minor=""
    local rest=""

    IFS='.' read -r major minor rest <<< "$core"
    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ ]]; then
        tool_fail "Unable to determine the .NET release channel for SDK $VERSION."
    fi

    printf '%s.%s' "$major" "$minor"
}

get_sdk_rid() {
    local os=""
    local arch=""
    local machine=""

    case "$(uname -s)" in
        Linux)
            os="linux"
            if [[ -f /etc/alpine-release ]] || \
               { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; then
                os="linux-musl"
            fi
            ;;
        Darwin) os="osx" ;;
        *) tool_fail "Unable to map the current operating system to a Microsoft SDK artifact." ;;
    esac

    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv8l) arch="arm" ;;
        s390x) arch="s390x" ;;
        ppc64le) arch="ppc64le" ;;
        *) tool_fail "Unable to map architecture $machine to a Microsoft SDK artifact." ;;
    esac

    printf '%s-%s' "$os" "$arch"
}

extract_sdk_artifact_metadata() {
    local expected_url="$1"

    awk -v expected="$expected_url" '
        /"url"[[:space:]]*:/ {
            value=$0
            sub(/^[^:]*:[[:space:]]*"/, "", value)
            sub(/".*$/, "", value)
            if (value == expected) {
                candidate=value
            }
            next
        }
        candidate != "" && /"hash"[[:space:]]*:/ {
            hash=$0
            sub(/^[^:]*:[[:space:]]*"/, "", hash)
            sub(/".*$/, "", hash)
            print candidate "|" hash
            candidate=""
        }
    ' | awk '!seen[$0]++'
}

install_isolated_sdk() {
    resolve_install_version || return 0

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local installed_sdks=""
    local installed_versions=""
    local isolated_sdks=""
    local metadata_file=""
    local archive_file=""
    local staging_dir=""
    local staged_dotnet=""
    local channel=""
    local rid=""
    local metadata_url=""
    local expected_artifact_url=""
    local artifact_data=""
    local artifact_count=0
    local artifact_url=""
    local expected_hash=""
    local actual_hash=""
    local status=0

    tool_info "Target SDK: $VERSION"
    tool_info "Isolated install directory: $install_dir"
    echo

    tool_info "Checking SDKs installed through the normal dotnet host..."

    if command -v dotnet >/dev/null 2>&1; then
        if installed_sdks="$(dotnet --list-sdks)"; then
            :
        else
            status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
        printf "%s\n" "$installed_sdks"
        echo

        installed_versions="$(printf "%s\n" "$installed_sdks" | awk '{print $1}')"
    else
        tool_warn "No system dotnet installation was found."
        echo
    fi

    tool_info "Checking for an existing isolated SDK..."

    if [[ -x "$isolated_dotnet" ]]; then
        if isolated_sdks="$("$isolated_dotnet" --list-sdks)"; then
            :
        else
            status=$?
            tool_fail "Unable to inspect existing isolated SDK $VERSION with exit code $status."
        fi

        if printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
            tool_success "Isolated SDK $VERSION is already installed."
            tool_info "Location: $install_dir"
            return
        fi
    fi

    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
        tool_fail "Isolated SDK destination already exists and cannot be replaced: $install_dir"
    fi

    tool_info "No existing isolated copy was found."
    echo

    if printf "%s\n" "$installed_versions" | grep -Fxq "$VERSION"; then
        tool_warn ".NET SDK $VERSION is already installed normally."

        if ! confirm_action "Install an isolated copy too?"; then
            tool_info "Installation cancelled."
            return
        fi

        echo
    fi

    channel="$(get_sdk_channel)"
    rid="$(get_sdk_rid)"
    metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/$channel/releases.json"
    expected_artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$VERSION/dotnet-sdk-$VERSION-$rid.tar.gz"
    metadata_file="$(mktemp "$SDK_ROOT/.release-metadata-$VERSION.XXXXXX")"
    archive_file="$(mktemp "$SDK_ROOT/.sdk-payload-$VERSION.XXXXXX")"
    trap 'cleanup_install_transaction "$metadata_file" "$archive_file" "$staging_dir" || true' EXIT

    tool_info "Loading Microsoft release metadata for SDK $VERSION..."
    if ! curl -fsSL "$metadata_url" -o "$metadata_file"; then
        status=$?
        tool_fail "Unable to load Microsoft release metadata for SDK $VERSION with exit code $status."
    fi

    if ! looks_like_json_object "$(cat "$metadata_file")" || \
       [[ "$(cat "$metadata_file")" != *'"releases"'* ]]; then
        tool_fail "Invalid Microsoft release metadata for SDK $VERSION."
    fi

    artifact_data="$(extract_sdk_artifact_metadata "$expected_artifact_url" < "$metadata_file")"
    artifact_count="$(printf '%s\n' "$artifact_data" | awk 'NF { count++ } END { print count + 0 }')"
    if (( artifact_count != 1 )); then
        tool_fail "Microsoft release metadata did not contain exactly one SDK archive for $VERSION and $rid."
    fi

    IFS='|' read -r artifact_url expected_hash <<< "$artifact_data"
    if [[ "$artifact_url" != "$expected_artifact_url" ]]; then
        tool_fail "Microsoft release metadata returned an unexpected SDK archive URL for $VERSION and $rid."
    fi
    if [[ ! "$expected_hash" =~ ^[0-9A-Fa-f]{128}$ ]]; then
        tool_fail "Microsoft release metadata contained an invalid SHA-512 hash for SDK $VERSION and $rid."
    fi
    expected_hash="$(printf '%s' "$expected_hash" | tr '[:upper:]' '[:lower:]')"

    tool_info "Downloading .NET SDK $VERSION payload..."
    if ! curl -fsSL "$artifact_url" -o "$archive_file"; then
        status=$?
        tool_fail "Unable to download the .NET SDK $VERSION payload with exit code $status."
    fi

    if ! actual_hash="$(calculate_sha512 "$archive_file")"; then
        tool_fail "Unable to verify the .NET SDK $VERSION payload because no SHA-512 utility is available."
    fi

    if [[ "$actual_hash" != "$expected_hash" ]]; then
        tool_fail "Integrity verification failed for the .NET SDK $VERSION payload."
    fi

    staging_dir="$(mktemp -d "$SDK_ROOT/.install-$VERSION.XXXXXX")"
    staged_dotnet="$staging_dir/dotnet"

    tool_info "Extracting verified .NET SDK $VERSION payload..."
    if ! tar -xzf "$archive_file" -C "$staging_dir"; then
        status=$?
        tool_fail "Unable to extract the verified .NET SDK $VERSION payload with exit code $status."
    fi

    echo
    tool_info "Verifying the isolated SDK..."

    if [[ ! -x "$staged_dotnet" ]]; then
        tool_fail "The isolated dotnet executable was not found at $staged_dotnet"
    fi

    if isolated_sdks="$("$staged_dotnet" --list-sdks)"; then
        :
    else
        status=$?
        tool_fail "Unable to verify isolated SDK $VERSION with exit code $status."
    fi
    printf "%s\n" "$isolated_sdks"

    if ! printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
        tool_fail "SDK $VERSION was not found after installation."
    fi

    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
        tool_fail "Isolated SDK destination already exists and cannot be replaced: $install_dir"
    fi

    if mv "$staging_dir" "$install_dir"; then
        staging_dir=""
    else
        status=$?
        tool_fail "Unable to promote isolated SDK $VERSION into $install_dir with exit code $status."
    fi

    if ! cleanup_install_transaction "$metadata_file" "$archive_file" "$staging_dir"; then
        metadata_file=""
        archive_file=""
        staging_dir=""
        trap - EXIT
        tool_fail "Isolated SDK $VERSION was installed, but transaction cleanup failed."
    fi

    metadata_file=""
    archive_file=""
    staging_dir=""
    trap - EXIT

    echo
    tool_success "Isolated SDK installation completed successfully."
    tool_info "Location: $install_dir"
}

'''
replace_re(
    "isolated-dotnet-sdk.sh",
    r"cleanup_install_transaction\(\) \{.*?\n\}\n\nremove_isolated_sdk\(\) \{",
    bash_block + "remove_isolated_sdk() {",
)

# PowerShell: remove installer pin constants and replace the install implementation.
replace(
    "isolated-dotnet-sdk.ps1",
    "$DotNetInstallCommit = 'da3ce11ba63f3dbb0fb835d41bda2665d5c48e84'\n$DotNetInstallSha256 = '3bb07bc8025211836c1e4f9d3f6a044e55b1fb6eec518a6c78851d04e210442b'\n$DotNetInstallUrl = \"https://raw.githubusercontent.com/dotnet/install-scripts/$DotNetInstallCommit/src/dotnet-install.ps1\"\n",
    "",
)

ps_install = r'''function Get-SdkChannel {
    if ($Version -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.') {
        throw "Unable to determine the .NET release channel for SDK $Version."
    }

    return "$($Matches.major).$($Matches.minor)"
}

function Get-SdkRid {
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $arch = switch ($architecture) {
        ([System.Runtime.InteropServices.Architecture]::X64) { 'x64'; break }
        ([System.Runtime.InteropServices.Architecture]::X86) { 'x86'; break }
        ([System.Runtime.InteropServices.Architecture]::Arm64) { 'arm64'; break }
        ([System.Runtime.InteropServices.Architecture]::Arm) { 'arm'; break }
        default { throw "Unable to map architecture $architecture to a Microsoft SDK artifact." }
    }

    return "win-$arch"
}

function Get-SdkArtifactMetadata {
    param(
        [Parameter(Mandatory)]
        [psobject]$Metadata,
        [Parameter(Mandatory)]
        [string]$SdkVersion,
        [Parameter(Mandatory)]
        [string]$Rid
    )

    $expectedUrl = "https://builds.dotnet.microsoft.com/dotnet/Sdk/$SdkVersion/dotnet-sdk-$SdkVersion-$Rid.zip"
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($release in @($Metadata.releases)) {
        $sdkEntries = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $release.sdk) {
            $sdkEntries.Add($release.sdk)
        }
        foreach ($sdk in @($release.sdks)) {
            if ($null -ne $sdk) {
                $sdkEntries.Add($sdk)
            }
        }

        foreach ($sdk in $sdkEntries) {
            if ([string]$sdk.version -ne $SdkVersion) {
                continue
            }

            foreach ($file in @($sdk.files)) {
                if ([string]$file.rid -eq $Rid -and [string]$file.url -eq $expectedUrl) {
                    $candidates.Add("$([string]$file.url)|$([string]$file.hash)")
                }
            }
        }
    }

    $uniqueCandidates = @($candidates | Sort-Object -Unique)
    if ($uniqueCandidates.Count -ne 1) {
        throw "Microsoft release metadata did not contain exactly one SDK archive for $SdkVersion and $Rid."
    }

    $parts = $uniqueCandidates[0].Split('|', 2)
    $url = $parts[0]
    $hash = $parts[1]

    if ($url -ne $expectedUrl) {
        throw "Microsoft release metadata returned an unexpected SDK archive URL for $SdkVersion and $Rid."
    }
    if ($hash -notmatch '^[0-9A-Fa-f]{128}$') {
        throw "Microsoft release metadata contained an invalid SHA-512 hash for SDK $SdkVersion and $Rid."
    }

    return [pscustomobject]@{
        Url = $url
        Hash = $hash.ToLowerInvariant()
    }
}

function Install-IsolatedSdk {
    if (-not (Resolve-InstallVersion)) {
        return
    }

    $InstallDir = Join-Path $SdkRoot $Version
    $IsolatedDotNet = Get-IsolatedDotNetPath -SdkVersion $Version

    Write-ToolInfo "Target SDK: $Version"
    Write-ToolInfo "Isolated install directory: $InstallDir"
    Write-ToolDisplay

    Write-ToolInfo 'Checking SDKs installed through the normal dotnet host...'

    $InstalledVersions = @()
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $InstalledSdks = dotnet --list-sdks
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "Unable to list SDKs through the system dotnet host with exit code $ExitCode."
        }

        foreach ($InstalledSdk in $InstalledSdks) {
            Write-ToolDisplay $InstalledSdk
        }
        Write-ToolDisplay
        $InstalledVersions = @($InstalledSdks | ForEach-Object { ($_ -split '\s+')[0] })
    }
    else {
        Write-ToolWarning 'No system dotnet installation was found.'
        Write-ToolDisplay
    }

    Write-ToolInfo 'Checking for an existing isolated SDK...'

    if (Test-Path -LiteralPath $IsolatedDotNet -PathType Leaf) {
        $IsolatedSdks = & $IsolatedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "Unable to inspect existing isolated SDK $Version with exit code $ExitCode."
        }

        $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
        if ($IsolatedVersions -contains $Version) {
            Write-ToolSuccess "Isolated SDK $Version is already installed."
            Write-ToolInfo "Location: $InstallDir"
            return
        }
    }

    if (Test-Path -LiteralPath $InstallDir) {
        throw "Isolated SDK destination already exists and cannot be replaced: $InstallDir"
    }

    Write-ToolInfo 'No existing isolated copy was found.'
    Write-ToolDisplay

    if ($InstalledVersions -contains $Version) {
        Write-ToolWarning ".NET SDK $Version is already installed normally."

        if (-not (Confirm-Action -Prompt 'Install an isolated copy too?')) {
            Write-ToolInfo 'Installation cancelled.'
            return
        }

        Write-ToolDisplay
    }

    $Channel = Get-SdkChannel
    $Rid = Get-SdkRid
    $MetadataUrl = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$Channel/releases.json"
    $MetadataPath = Join-Path $SdkRoot ('.release-metadata-{0}-{1}.json' -f $Version, [guid]::NewGuid().ToString('N'))
    $ArchivePath = Join-Path $SdkRoot ('.sdk-payload-{0}-{1}.zip' -f $Version, [guid]::NewGuid().ToString('N'))
    $StagingDir = Join-Path $SdkRoot ('.install-{0}-{1}' -f $Version, [guid]::NewGuid().ToString('N'))
    $StagedDotNet = Join-Path $StagingDir 'dotnet.exe'
    $PrimaryFailure = $null
    $CleanupFailure = $null

    try {
        Write-ToolInfo "Loading Microsoft release metadata for SDK $Version..."
        try {
            Invoke-WebRequest $MetadataUrl -OutFile $MetadataPath
            $Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to load valid Microsoft release metadata for SDK ${Version}: $($_.Exception.Message)"
        }

        $Artifact = Get-SdkArtifactMetadata -Metadata $Metadata -SdkVersion $Version -Rid $Rid

        Write-ToolInfo "Downloading .NET SDK $Version payload..."
        try {
            Invoke-WebRequest $Artifact.Url -OutFile $ArchivePath
        }
        catch {
            throw "Unable to download the .NET SDK $Version payload: $($_.Exception.Message)"
        }

        try {
            $ActualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA512).Hash.ToLowerInvariant()
        }
        catch {
            throw "Unable to verify the .NET SDK $Version payload: $($_.Exception.Message)"
        }

        if ($ActualHash -ne $Artifact.Hash) {
            throw "Integrity verification failed for the .NET SDK $Version payload."
        }

        New-Item -ItemType Directory -Path $StagingDir -WhatIf:$false -Confirm:$false | Out-Null
        Write-ToolInfo "Extracting verified .NET SDK $Version payload..."
        try {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StagingDir -Force
        }
        catch {
            throw "Unable to extract the verified .NET SDK $Version payload: $($_.Exception.Message)"
        }

        Write-ToolDisplay
        Write-ToolInfo 'Verifying the isolated SDK...'

        if (-not (Test-Path -LiteralPath $StagedDotNet -PathType Leaf)) {
            throw "The isolated dotnet executable was not found at $StagedDotNet"
        }

        $IsolatedSdks = & $StagedDotNet --list-sdks
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            throw "Unable to verify isolated SDK $Version with exit code $ExitCode."
        }

        foreach ($IsolatedSdk in $IsolatedSdks) {
            Write-ToolDisplay $IsolatedSdk
        }

        $IsolatedVersions = @($IsolatedSdks | ForEach-Object { ($_ -split '\s+')[0] })
        if ($IsolatedVersions -notcontains $Version) {
            throw "SDK $Version was not found after installation."
        }

        if (Test-Path -LiteralPath $InstallDir) {
            throw "Isolated SDK destination already exists and cannot be replaced: $InstallDir"
        }

        try {
            Move-Item -LiteralPath $StagingDir -Destination $InstallDir -WhatIf:$false -Confirm:$false
            $StagingDir = $null
        }
        catch {
            throw "Unable to promote isolated SDK $Version into ${InstallDir}: $($_.Exception.Message)"
        }
    }
    catch {
        $PrimaryFailure = $_
    }
    finally {
        foreach ($TemporaryPath in @($MetadataPath, $ArchivePath)) {
            if ($TemporaryPath -and (Test-Path -LiteralPath $TemporaryPath)) {
                try {
                    Remove-Item -LiteralPath $TemporaryPath -Force -WhatIf:$false -Confirm:$false
                }
                catch {
                    Write-ToolWarning "Unable to clean install transaction file ${TemporaryPath}: $($_.Exception.Message)"
                    if ($null -eq $CleanupFailure) {
                        $CleanupFailure = $_
                    }
                }
            }
        }

        if ($StagingDir -and (Test-Path -LiteralPath $StagingDir)) {
            try {
                Remove-Item -LiteralPath $StagingDir -Recurse -Force -WhatIf:$false -Confirm:$false
            }
            catch {
                Write-ToolWarning "Unable to clean install staging directory ${StagingDir}: $($_.Exception.Message)"
                if ($null -eq $CleanupFailure) {
                    $CleanupFailure = $_
                }
            }
        }
    }

    if ($null -ne $PrimaryFailure) {
        throw $PrimaryFailure
    }

    if ($null -ne $CleanupFailure) {
        throw "Isolated SDK $Version was installed, but transaction cleanup failed: $($CleanupFailure.Exception.Message)"
    }

    Write-ToolDisplay
    Write-ToolSuccess 'Isolated SDK installation completed successfully.'
    Write-ToolInfo "Location: $InstallDir"
}

'''
replace_re(
    "isolated-dotnet-sdk.ps1",
    r"function Install-IsolatedSdk \{.*?\n\}\n\nfunction Invoke-IsolatedSdkBuildServerShutdown",
    ps_install + "function Invoke-IsolatedSdkBuildServerShutdown",
)

# Replace helper-integrity tests with payload-integrity tests. These establish the
# new pre-extraction security boundary without live Microsoft dependencies.
bash_tests = r'''#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  test_root="$(mktemp -d "${TMPDIR:-/tmp}/isolated-dotnet-sdk-payload-integrity.XXXXXX")"
  test_home="$test_root/home"
  tool_root="$test_home/dotnet-sdks"
  tool_path="$tool_root/isolated-dotnet-sdk.sh"
  fake_bin="$test_root/fake-bin"
  fixture_root="$test_root/fixture"
  version='99.0.100'
  rid='linux-x64'
  artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$version/dotnet-sdk-$version-$rid.tar.gz"
  metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/99.0/releases.json"
  payload="$test_root/sdk.tar.gz"
  metadata="$test_root/releases.json"

  mkdir -p "$tool_root" "$fake_bin" "$fixture_root"
  cp "$repo_root/isolated-dotnet-sdk.sh" "$tool_path"
  chmod +x "$tool_path"

  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) printf '%s\n' Linux ;;
esac
EOF
  chmod +x "$fake_bin/uname"

  cat > "$fake_bin/dotnet" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fake_bin/dotnet"

  cat > "$fixture_root/dotnet" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == '--list-sdks' ]]; then
  printf '%s\n' '99.0.100 [/fixture/sdk]'
  exit 0
fi
exit 0
EOF
  chmod +x "$fixture_root/dotnet"
  tar -czf "$payload" -C "$fixture_root" dotnet

  if command -v sha512sum >/dev/null 2>&1; then
    payload_hash="$(sha512sum "$payload" | awk '{print $1}')"
  else
    payload_hash="$(shasum -a 512 "$payload" | awk '{print $1}')"
  fi

  write_metadata "$payload_hash"

  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url=''
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$HOME/curl.log"
case "$url" in
  *release-metadata*) cp "$TEST_METADATA" "$out" ;;
  */dotnet/Sdk/*) cp "$TEST_PAYLOAD" "$out" ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$fake_bin/curl"
}

write_metadata() {
  local hash="$1"
  cat > "$metadata" <<EOF
{
  "releases": [
    {
      "sdk": {
        "version": "$version",
        "files": [
          {
            "rid": "$rid",
            "url": "$artifact_url",
            "hash": "$hash"
          }
        ]
      }
    }
  ]
}
EOF
}

teardown() {
  rm -rf "$test_root"
}

run_install() {
  run env HOME="$test_home" TEST_METADATA="$metadata" TEST_PAYLOAD="$payload" PATH="$fake_bin:$PATH" \
    "$tool_path" install "$version" --yes
}

@test "verified SDK payload is extracted and promoted" {
  run_install

  [ "$status" -eq 0 ]
  [ -x "$tool_root/$version/dotnet" ]
  [[ "$output" == *"Extracting verified .NET SDK $version payload..."* ]]
  [[ "$output" == *"Isolated SDK installation completed successfully."* ]]
  grep -Fq "$metadata_url" "$test_home/curl.log"
  grep -Fq "$artifact_url" "$test_home/curl.log"
  ! compgen -G "$tool_root/.release-metadata-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
  ! compgen -G "$tool_root/.install-$version.*" >/dev/null
}

@test "SDK payload checksum mismatch prevents extraction and promotion" {
  write_metadata "$(printf '%0128d' 0)"
  cat > "$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called > "$HOME/tar-called.txt"
exit 91
EOF
  chmod +x "$fake_bin/tar"

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"Integrity verification failed for the .NET SDK $version payload."* ]]
  [ ! -e "$test_home/tar-called.txt" ]
  [ ! -e "$tool_root/$version" ]
  ! compgen -G "$tool_root/.release-metadata-$version.*" >/dev/null
  ! compgen -G "$tool_root/.sdk-payload-$version.*" >/dev/null
}

@test "missing matching SDK artifact metadata fails closed" {
  write_metadata "$payload_hash"
  sed -i.bak "s/$rid/linux-arm64/" "$metadata"
  rm -f "$metadata.bak"

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not contain exactly one SDK archive for $version and $rid"* ]]
  [ ! -e "$tool_root/$version" ]
}

@test "malformed SDK payload checksum metadata fails closed" {
  write_metadata deadbeef

  run_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid SHA-512 hash for SDK $version and $rid"* ]]
  [ ! -e "$tool_root/$version" ]
}
'''
(ROOT / "tests/bash/installer-integrity.bats").write_text(bash_tests)

ps_tests = r'''Describe 'PowerShell SDK payload integrity' {
    BeforeEach {
        $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:ToolScript = Join-Path $script:RepositoryRoot 'isolated-dotnet-sdk.ps1'
        $script:HomeVariableName = 'USERPROFILE'
        $script:OriginalHomeValue = [Environment]::GetEnvironmentVariable($script:HomeVariableName, 'Process')
        $script:TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("isolated-dotnet-sdk-payload-integrity-{0}" -f [guid]::NewGuid())
        $script:TestHome = Join-Path $script:TestRoot 'home'
        $script:ToolRoot = Join-Path $script:TestHome 'dotnet-sdks'
        $script:ToolPath = Join-Path $script:ToolRoot 'isolated-dotnet-sdk.ps1'
        $script:Version = '99.0.100'
        $script:InstallDir = Join-Path $script:ToolRoot $script:Version
        New-Item -ItemType Directory -Path $script:ToolRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:ToolScript -Destination $script:ToolPath -Force
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:TestHome, 'Process')
        $env:ISOLATED_DOTNET_SDK_TOOL_PATH = $script:ToolPath
        $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER = Join-Path $script:TestHome 'expand-called.txt'
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable($script:HomeVariableName, $script:OriginalHomeValue, 'Process')
        Remove-Item Env:ISOLATED_DOTNET_SDK_TOOL_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:ISOLATED_DOTNET_SDK_EXPAND_MARKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rejects a SDK payload checksum mismatch before extraction' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        $rid = "win-x64"
        $url = "https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-$rid.zip"
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = $rid; url = $url; hash = ("a" * 128) }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
    else {
        Set-Content -LiteralPath $OutFile -Value payload
    }
}
function Get-FileHash {
    param([string]$LiteralPath, [string]$Algorithm)
    [pscustomobject]@{ Hash = ("b" * 128) }
}
function Expand-Archive {
    param($LiteralPath, $DestinationPath, [switch]$Force)
    Set-Content -LiteralPath $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER -Value called
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'Integrity verification failed for the \.NET SDK 99\.0\.100 payload\.'
        Test-Path -LiteralPath $env:ISOLATED_DOTNET_SDK_EXPAND_MARKER | Should -BeFalse
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:ToolRoot -Filter '.sdk-payload-*' -ErrorAction SilentlyContinue).Count |
            Should -Be 0
    }

    It 'fails closed when the SDK artifact checksum is malformed' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        $rid = "win-x64"
        $url = "https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-$rid.zip"
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = $rid; url = $url; hash = "deadbeef" }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'invalid SHA-512 hash for SDK 99\.0\.100 and win-x64'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }

    It 'fails closed when matching SDK artifact metadata is missing' {
        $failureOutput = @(& pwsh -NoProfile -Command '
function Invoke-WebRequest {
    param($Uri, $OutFile)
    if ([string]$Uri -like "*release-metadata*") {
        @{ releases = @(@{ sdk = @{ version = "99.0.100"; files = @(@{ rid = "win-arm64"; url = "https://builds.dotnet.microsoft.com/example.zip"; hash = ("a" * 128) }) } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
    }
}
& $env:ISOLATED_DOTNET_SDK_TOOL_PATH -Action Install -Version 99.0.100 -Yes
' 2>&1)

        $LASTEXITCODE | Should -Not -Be 0
        ($failureOutput -join [Environment]::NewLine) |
            Should -Match 'did not contain exactly one SDK archive for 99\.0\.100 and win-x64'
        Test-Path -LiteralPath $script:InstallDir | Should -BeFalse
    }
}
'''
(ROOT / "tests/powershell/installer-integrity.Tests.ps1").write_text(ps_tests)

# Remove obsolete runtime-helper provenance. The dependency monitor should no longer
# track a remote executable that the product does not consume.
config_path = ROOT / ".config/remote-artifacts.json"
config = json.loads(config_path.read_text())
config.pop("dotnetInstall", None)
config_path.write_text(json.dumps(config, indent=2) + "\n")

monitor = ROOT / "scripts/Invoke-DependencyUpdateCheck.ps1"
text = monitor.read_text()
text = text.replace("    $remote = Get-Content -LiteralPath (Join-Path $Root '.config/remote-artifacts.json') -Raw |\n        ConvertFrom-Json\n\n", "")
text = text.replace("        'dotnetInstallCommit' = [string]$remote.dotnetInstall.commit\n", "")
text = text.replace("    if ($requiredValues['dotnetInstallCommit'] -notmatch '^[0-9a-f]{40}$') {\n        throw 'dotnetInstall.commit must be a full lowercase Git commit SHA.'\n    }\n", "")
text = text.replace("        DotNetInstallCommit = $requiredValues['dotnetInstallCommit']\n", "")
text = text.replace("    $dotnetInstall = Get-GitHubStableRelease -Repository 'dotnet/install-scripts' -ResolveCommit\n", "")
text = text.replace("        DotNetInstall = $dotnetInstall\n", "")
text = re.sub(r"\n    if \(\[string\]\$Candidate\.DotNetInstall\.Commit.*?\n    \}\n\n    return @\(\$updates\)", "\n    return @($updates)", text, flags=re.S)
monitor.write_text(text)

print('issue 72 implementation patch applied')
