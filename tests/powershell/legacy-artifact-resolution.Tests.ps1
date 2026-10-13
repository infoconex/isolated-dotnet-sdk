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

        function New-Metadata {
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
        $metadata = New-Metadata '1.1.14' 'dotnet-dev-win-x64.zip' $url
        $artifact = Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'win-x64'
        $artifact.Url | Should -Be $url
        $artifact.Hash | Should -Be ('a' * 128)
    }

    It 'selects the historical macOS TAR archive without substituting a different RID' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-osx-x64.1.1.14.tar.gz'
        $metadata = New-Metadata '1.1.14' 'dotnet-dev-osx-x64.tar.gz' $url 'osx-x64'
        (Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'osx-x64').Url | Should -Be $url
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.1.14' -Rid 'linux-x64' } |
            Should -Throw '*did not contain exactly one SDK archive*'
    }

    It 'rejects historical SDK 1.0.4 SHA-256-only metadata under SHA-512 policy' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.0.4/dotnet-dev-win-x64.1.0.4.zip'
        $metadata = New-Metadata '1.0.4' 'dotnet-dev-win-x64.zip' $url 'win-x64' ('a' * 64)
        { Resolve-SdkArtifact -Metadata $metadata -SdkVersion '1.0.4' -Rid 'win-x64' } |
            Should -Throw '*invalid SHA-512 hash*'
    }

    It 'keeps current modern SDK selection and accepts sdks collection entries' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.401/dotnet-sdk-10.0.401-win-x64.zip'
        $metadata = New-Metadata '10.0.401' 'dotnet-sdk-win-x64.zip' $url
        $metadata.releases[0] | Add-Member -NotePropertyName sdks -NotePropertyValue @($metadata.releases[0].sdk)
        $metadata.releases[0].sdk = $null
        (Resolve-SdkArtifact -Metadata $metadata -SdkVersion '10.0.401' -Rid 'win-x64').Url | Should -Be $url
    }

    It 'rejects wrong SDK entry, untrusted URL and inconsistent archive name' {
        $url = 'https://builds.dotnet.microsoft.com/dotnet/Sdk/1.1.14/dotnet-dev-win-x64.1.1.14.zip'
        $metadata = New-Metadata '1.0.4' 'dotnet-dev-win-x64.zip' $url
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
        $metadata = New-Metadata '1.1.14' 'dotnet-dev-win-x64.zip' $url
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
