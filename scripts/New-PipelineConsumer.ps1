[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ApplicationName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $Destination,

    [string] $LibraryName = 'infra-ops-pipeline',
    [string] $LibraryVersion = 'v0.1.0',
    [string] $BuildAgent = 'linux && dotnet',
    [string] $DeployAgent = 'linux && docker',
    [string] $ProjectFile = 'src/MyService/MyService.csproj',
    [string] $TestProjectFile = 'tests/MyService.Tests/MyService.Tests.csproj'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot 'examples\consumer-project'
$destinationPath = [System.IO.Path]::GetFullPath($Destination)

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Consumer template was not found: $source"
}

if (Test-Path -LiteralPath $destinationPath) {
    $existing = @(Get-ChildItem -LiteralPath $destinationPath -Force)
    if ($existing.Count -gt 0) {
        throw "Destination must be new or empty; existing files were left unchanged: $destinationPath"
    }
} else {
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
}

Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destinationPath -Recurse
}

$replacements = [ordered]@{
    '__APPLICATION_NAME__' = $ApplicationName
    '__LIBRARY_NAME__' = $LibraryName
    '__LIBRARY_VERSION__' = $LibraryVersion
    '__BUILD_AGENT__' = $BuildAgent
    '__DEPLOY_AGENT__' = $DeployAgent
    '__PROJECT_FILE__' = $ProjectFile.Replace('\', '/')
    '__TEST_PROJECT_FILE__' = $TestProjectFile.Replace('\', '/')
}

$textExtensions = @('.groovy', '.md', '.sh', '.yml', '.yaml', '.json', '')
Get-ChildItem -LiteralPath $destinationPath -Recurse -File | ForEach-Object {
    if ($textExtensions -notcontains $_.Extension) {
        return
    }

    $content = Get-Content -LiteralPath $_.FullName -Raw
    foreach ($entry in $replacements.GetEnumerator()) {
        $content = $content.Replace($entry.Key, $entry.Value)
    }
    Set-Content -LiteralPath $_.FullName -Value $content -Encoding utf8NoBOM
}

Write-Host "Created pipeline consumer starter: $destinationPath"
Write-Host 'Next: update environment URLs, credential IDs, migration command, and rollback image resolution.'
