Describe 'Legacy SDK artifact resolution' {
    BeforeAll {
        $path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path 'isolated-dotnet-sdk.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
        $definition = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-SdkArtifact'
            }, $true) | Select-Object -First 1
        $null -ne $definition | Should -BeTrue
        . ([scriptblock]::Create($definition.Extent.Text))

        function Get-ArtifactMetadataFixture {
            param([string]$Version, [string]$Name, [string]$Url, [string]$Rid = 'win-x64', [string]$Hash = ('a' * 128))
            [pscustomobject]@{
                releases = @([pscustomobject]@{
                    sdk = [pscustomobject]@{
                        version = $Version
                        files = @([pscustomobject]@{ name = $Name; rid = $Rid; url = $Url; hash = $Hash })
                    }
                })
            }
        }
    }

    It 'selects legacy SDK 1.1.14 Windows ZIP with exact SDK version and RID' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-win-x64.1.1.14.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '1.1.14' -Name 'dotnet-dev-win-x64.zip' -Url $url
        $artifact = Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64'
        $artifact.Url | Should -Be $url
        $artifact.Hash | Should -Be ('a' * 128)
    }

    It 'selects the historical macOS TAR archive without substituting a different RID' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-osx-x64.1.1.14.tar.gz'
        $metadata = Get-ArtifactMetadataFixture -Version '1.1.14' -Name 'dotnet-dev-osx-x64.tar.gz' -Url $url -Rid 'osx-x64'
        (Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'osx-x64').Url | Should -Be $url
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'linux-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
    }

    It 'accepts Microsoft-published SHA-256 for historical SDK 1.0.4' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.0.4/dotnet-dev-win-x64.1.0.4.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '1.0.4' -Name 'dotnet-dev-win-x64.zip' -Url $url -Rid 'win-x64' -Hash ('a' * 64)
        $artifact = Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.0.4' -Rid 'win-x64'
        $artifact.Url | Should -Be $url
        $artifact.Algorithm | Should -Be 'SHA256'
        $artifact.Hash | Should -Be ('a' * 64)
    }

    It 'continues to select SHA-512 for historical SDKs publishing SHA-512' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-win-x64.1.1.14.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '1.1.14' -Name 'dotnet-dev-win-x64.zip' -Url $url
        (Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64').Algorithm |
            Should -Be 'SHA512'
    }

    It 'rejects malformed historical checksums and SHA-256 metadata for modern SDKs' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.0.4/dotnet-dev-win-x64.1.0.4.zip'
        foreach ($hash in @('', 'deadbeef', ('z' * 64), ('a' * 63))) {
            $metadata = Get-ArtifactMetadataFixture -Version '1.0.4' -Name 'dotnet-dev-win-x64.zip' -Url $url -Hash $hash
            { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.0.4' -Rid 'win-x64' } |
                Should -Throw '*unsupported or malformed checksum*'
        }
        $modernUrl = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '10.0.401' -Name 'dotnet-sdk-win-x64.zip' -Url $modernUrl -Hash ('a' * 64)
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '10.0.401' -Rid 'win-x64' } |
            Should -Throw '*SHA-256 is supported only for historical*'
    }

    It 'keeps current modern SDK selection and accepts sdks collection entries' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '10.0.401' -Name 'dotnet-sdk-win-x64.zip' -Url $url
        $metadata.releases[0] | Add-Member -NotePropertyName sdks -NotePropertyValue @($metadata.releases[0].sdk)
        $metadata.releases[0].sdk = $null
        (Resolve-SdkArtifact -Metadata $metadata -SdkVersion '10.0.401' -Rid 'win-x64').Url | Should -Be $url
    }

    It 'rejects wrong SDK entry, untrusted URL and inconsistent archive name' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-win-x64.1.1.14.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '1.0.4' -Name 'dotnet-dev-win-x64.zip' -Url $url
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
        $metadata.releases[0].sdk.version = '1.1.14'
        $metadata.releases[0].sdk.files[0].url = $url.Replace('builds.dotnet.microsoft.com', 'untrusted.example')
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
        $metadata.releases[0].sdk.files[0].url = $url
        $metadata.releases[0].sdk.files[0].name = 'dotnet-dev-win-x86.zip'
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
    }

    It 'rejects ambiguous candidate hashes for one archive' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-win-x64.1.1.14.zip'
        $metadata = Get-ArtifactMetadataFixture -Version '1.1.14' -Name 'dotnet-dev-win-x64.zip' -Url $url
        $metadata.releases[0].sdk.files += [pscustomobject]@{
            name = 'dotnet-dev-win-x64.zip'
            rid = 'win-x64'
            url = $url
            hash = ('b' * 128)
        }
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
    }
}
