# Shared deterministic fixture for PowerShell SDK-payload transaction tests.
# These functions intentionally shadow built-in cmdlets so product behavior can be exercised
# without network, archive, or filesystem side effects. The static-analysis runner excludes
# this fixture for that reason.

function Invoke-WebRequest {
    param($Uri, $OutFile)

    if ([string]$Uri -like '*release-metadata*') {
        if ($env:SDK_TEST_METADATA_FAILURE) {
            throw $env:SDK_TEST_METADATA_FAILURE
        }
        if ($env:SDK_TEST_DOWNLOAD_TARGET) {
            Set-Content -LiteralPath $env:SDK_TEST_DOWNLOAD_TARGET -Value $OutFile
        }
        $rid = 'win-x64'
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/99.0.100/dotnet-sdk-99.0.100-win-x64.zip'
        $hash = if ($env:SDK_TEST_MALFORMED_HASH) { 'deadbeef' } else { 'a' * 128 }
        $files = if ($env:SDK_TEST_MISSING_ARTIFACT) {
            @(@{ rid = 'win-arm64'; url = 'https://builds.dotnet.microsoft.com/example.zip'; hash = $hash })
        }
        else {
            @(@{ rid = $rid; url = $url; hash = $hash })
        }
        @{ releases = @(@{ sdk = @{ version = '99.0.100'; files = $files } }) } |
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
    $hash = if ($env:SDK_TEST_HASH_MISMATCH) { 'b' * 128 } else { 'a' * 128 }
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
        [System.Management.Automation.ActionPreference]$ErrorAction
    )
    if ($env:SDK_TEST_CLEANUP_PATTERN -and $LiteralPath -like "*$($env:SDK_TEST_CLEANUP_PATTERN)*") {
        throw 'cleanup-remove-failed'
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -WhatIf:$WhatIf -Confirm:$Confirm -ErrorAction $ErrorAction
}
