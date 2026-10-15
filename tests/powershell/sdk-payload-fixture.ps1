# Shared deterministic fixture for PowerShell SDK-payload transaction tests.
# These functions intentionally shadow built-in cmdlets so product behavior can be exercised
# without network, archive, or filesystem side effects. The static-analysis runner excludes
# this fixture for that reason.

function Invoke-WebRequest {
    param($Uri, $OutFile)

    if ([string]$Uri -like '*release-metadata*') {
        if ($env:SDK_TEST_DOWNLOAD_TARGET) {
            Set-Content -LiteralPath $env:SDK_TEST_DOWNLOAD_TARGET -Value $OutFile
        }
        if ($env:SDK_TEST_METADATA_FAILURE) {
            throw $env:SDK_TEST_METADATA_FAILURE
        }
        if ($env:SDK_TEST_METADATA_URL_TARGET) {
            Set-Content -LiteralPath $env:SDK_TEST_METADATA_URL_TARGET -Value ([string]$Uri)
        }
        $rid = 'win-x64'
        $legacyVersion = $env:SDK_TEST_LEGACY_VERSION
        $url = if ($legacyVersion -match '^1\.') {
            "https://builds.dotnet.microsoft.com/dotnet/Sdk/$legacyVersion/dotnet-dev-win-x64.$legacyVersion.zip"
        }
        elseif ($legacyVersion) {
            "https://builds.dotnet.microsoft.com/dotnet/Sdk/$legacyVersion/dotnet-sdk-$legacyVersion-win-x64.zip"
        }
        else {
            'https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-win-x64.zip'
        }
        $hash = if ($env:SDK_TEST_MALFORMED_HASH) { 'deadbeef' } elseif ($legacyVersion -eq '1.0.4') { 'a' * 64 } else { 'a' * 128 }
        $files = if ($env:SDK_TEST_MISSING_ARTIFACT) {
            @(@{ rid = 'win-arm64'; url = 'https://builds.dotnet.microsoft.com/example.zip'; hash = $hash })
        }
        else {
            @(@{ name = $(if ($legacyVersion -match '^1\.') { 'dotnet-dev-win-x64.zip' } else { 'dotnet-sdk-win-x64.zip' }); rid = $rid; url = $url; hash = $hash })
        }
        @{ releases = @(@{ sdk = @{ version = $(if ($legacyVersion) { $legacyVersion } else { '99.0.100' }); files = $files } }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutFile
        return
    }

    if ([string]$Uri -like '*/dotnet/Sdk/*') {
        if ($env:SDK_TEST_PAYLOAD_FAILURE) {
            throw $env:SDK_TEST_PAYLOAD_FAILURE
        }
        Set-Content -LiteralPath $OutFile -Value 'verified-payload-fixture'
        return
    }

    throw "Unexpected fixture URL: $Uri"
}

function Get-FileHash {
    param([string]$LiteralPath, [string]$Algorithm)
    $length = if ($Algorithm -eq 'SHA256') { 64 } else { 128 }
    $hash = if ($env:SDK_TEST_HASH_MISMATCH) { 'b' * $length } else { 'a' * $length }
    [pscustomobject]@{ Hash = $hash }
}

function Expand-Archive {
    param($LiteralPath, $DestinationPath, [switch]$Force)
    if ($env:SDK_TEST_EXTRACT_FAILURE) {
        throw $env:SDK_TEST_EXTRACT_FAILURE
    }
    if ($env:SDK_TEST_STAGING_TARGET) {
        Set-Content -LiteralPath $env:SDK_TEST_STAGING_TARGET -Value $DestinationPath
    }
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    if (-not $env:SDK_TEST_MISSING_HOST) {
        Copy-Item -Path (Join-Path $env:ISOLATED_DOTNET_SDK_FAKE_HOST_ROOT '*') -Destination $DestinationPath -Recurse -Force
        if ($env:SDK_TEST_LEGACY_VERSION) {
            New-Item -ItemType Directory -Path (Join-Path (Join-Path $DestinationPath 'sdk') $env:SDK_TEST_LEGACY_VERSION) -Force | Out-Null
        }
        else {
            New-Item -ItemType Directory -Path (Join-Path $DestinationPath 'sdk') -Force | Out-Null
        }
    }
}

function Move-Item {
    param([string]$LiteralPath, [string]$Destination, [switch]$WhatIf, [switch]$Confirm)
    if ($env:SDK_TEST_PROMOTION_FAILURE) {
        throw $env:SDK_TEST_PROMOTION_FAILURE
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -WhatIf:$WhatIf -Confirm:$Confirm
}

function Remove-Item {
    param(
        [string]$LiteralPath,
        [switch]$Recurse,
        [switch]$Force,
        [switch]$WhatIf,
        [switch]$Confirm,
        [System.Management.Automation.ActionPreference]$ErrorAction = [System.Management.Automation.ActionPreference]::Continue
    )
    if ($env:SDK_TEST_CLEANUP_PATTERN -and $LiteralPath -like "*$($env:SDK_TEST_CLEANUP_PATTERN)*") {
        throw 'cleanup-remove-failed'
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -WhatIf:$WhatIf -Confirm:$Confirm -ErrorAction $ErrorAction
}
