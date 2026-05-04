#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads a DSC v3 configuration and applies it with the Pinned DSC v3 resource.
.DESCRIPTION
    DSC v3 expects --file to reference a local file. This example downloads a
    remote YAML configuration to %TEMP%, makes the Pinned DSC v3 resource
    discoverable for this process, and invokes `dsc config set`.
#>
[CmdletBinding()]
param(
    [string] $ConfigurationUri = 'https://raw.githubusercontent.com/AppNetOnline/ans-dsc-pinned/feature/dsc-v3-resource/.configurations/firefox-dscv3.yaml',

    [string] $ResourcePath,

    [string] $ResourceBaseUri = 'https://raw.githubusercontent.com/AppNetOnline/ans-dsc-pinned/feature/dsc-v3-resource/Pinned/DSCv3',

    [string] $DestinationPath = (Join-Path $env:TEMP 'ans-configure.yaml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Install-PinnedDscV3ResourceFromUrl {
    param(
        [Parameter(Mandatory)]
        [string] $BaseUri,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }

    $trimmedBaseUri = $BaseUri.TrimEnd('/')
    $moduleBaseUri = $trimmedBaseUri -replace '/DSCv3$', ''

    $resourceFiles = @(
        @{
            Uri = '{0}/Pinned.App.cmd' -f $trimmedBaseUri
            Path = Join-Path $Destination 'Pinned.App.cmd'
        }
        @{
            Uri = '{0}/Pinned.App.ps1' -f $trimmedBaseUri
            Path = Join-Path $Destination 'Pinned.App.ps1'
        }
        @{
            Uri = '{0}/Pinned.App.dsc.resource.json' -f $trimmedBaseUri
            Path = Join-Path $Destination 'Pinned.App.dsc.resource.json'
        }
        @{
            Uri = '{0}/DSCResources/App/App.psm1' -f $moduleBaseUri
            Path = Join-Path (Split-Path -Parent $Destination) 'DSCResources\App\App.psm1'
        }
    )

    foreach ($file in $resourceFiles) {
        $folder = Split-Path -Parent $file.Path
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }

        Invoke-WebRequest -Uri $file.Uri -OutFile $file.Path -UseBasicParsing

        $downloadedFile = Get-Item -LiteralPath $file.Path -ErrorAction Stop
        if ($downloadedFile.Length -eq 0) {
            throw "Downloaded '$($file.Uri)' to '$($file.Path)', but the file is empty."
        }
    }
}

function Test-PinnedDscV3ResourcePath {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    foreach ($fileName in @('Pinned.App.cmd', 'Pinned.App.ps1', 'Pinned.App.dsc.resource.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $fileName))) {
            return $false
        }
    }

    $moduleFile = Join-Path (Split-Path -Parent $Path) 'DSCResources\App\App.psm1'
    return (Test-Path -LiteralPath $moduleFile)
}

if ([string]::IsNullOrWhiteSpace($ResourcePath)) {
    $repoResourcePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        Join-Path $PSScriptRoot '..\Pinned\DSCv3'
    } else {
        $null
    }

    $installedResourcePath = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\Pinned\DSCv3'

    if ($repoResourcePath -and (Test-Path -LiteralPath $repoResourcePath)) {
        $ResourcePath = $repoResourcePath
    } elseif (Test-Path -LiteralPath $installedResourcePath) {
        $ResourcePath = $installedResourcePath
    } else {
        $ResourcePath = Join-Path $env:TEMP 'Pinned.DSCv3'
    }
}

if (-not (Test-PinnedDscV3ResourcePath -Path $ResourcePath)) {
    Install-PinnedDscV3ResourceFromUrl -BaseUri $ResourceBaseUri -Destination $ResourcePath
}

$resolvedResourcePath = (Resolve-Path -LiteralPath $ResourcePath).Path
$env:DSC_RESOURCE_PATH = $resolvedResourcePath

Invoke-WebRequest -Uri $ConfigurationUri -OutFile $DestinationPath -UseBasicParsing

$configFile = Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
if ($configFile.Length -eq 0) {
    throw "Downloaded '$ConfigurationUri' to '$DestinationPath', but the file is empty."
}

dsc resource list AppNetOnline.Pinned/App | Out-String | Write-Verbose

$dscArgs = @(
    'config'
    'set'
    '--file'
    $DestinationPath
)

dsc @dscArgs
