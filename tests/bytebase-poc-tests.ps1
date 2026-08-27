[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$pocRoot = Join-Path $root 'examples\bytebase-poc'
$reportDirectory = Join-Path $PSScriptRoot 'reports'
$reportPath = Join-Path $reportDirectory 'bytebase-poc-validation.txt'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Poc {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

function Write-ValidationReport {
    param([Parameter(Mandatory)] [string] $Value)

    [System.IO.File]::WriteAllText(
        $reportPath,
        $Value + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$requiredFiles = @(
    'README.md',
    '.env.example',
    'compose.yaml',
    'Jenkinsfile',
    'migrations\202608250001_create_customer.sql',
    'migrations\202608250002_add_customer_email.sql',
    'migrations\202608250003_create_customer_email_index.sql',
    'ops\validate-migrations.sh',
    'ops\bytebase-migrate.sh',
    'ops\acceptance-test.sh',
    'ops\package.sh',
    'ops\noop-deploy.sh',
    'ops\verify-migration.sh'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $pocRoot $relativePath
    Assert-Poc (Test-Path -LiteralPath $fullPath -PathType Leaf) "Missing Bytebase POC file: $relativePath"
}

$composePath = Join-Path $pocRoot 'compose.yaml'
if (Test-Path -LiteralPath $composePath -PathType Leaf) {
    $compose = Get-Content -LiteralPath $composePath -Raw
    Assert-Poc ($compose.Contains('bytebase/bytebase:${BYTEBASE_VERSION:-3.20.0}')) 'Bytebase server image must be version-pinned'
    Assert-Poc ($compose.Contains('postgres:${POSTGRES_VERSION:-17.6-alpine}')) 'PostgreSQL image must be version-pinned'
    Assert-Poc ($compose.Contains('/var/opt/bytebase')) 'Bytebase data must use persistent storage'
    Assert-Poc ($compose.Contains('BYTEBASE_DOCKER_NETWORK')) 'Compose network name must be explicit for the Jenkins action container'
}

$jenkinsPath = Join-Path $pocRoot 'Jenkinsfile'
if (Test-Path -LiteralPath $jenkinsPath -PathType Leaf) {
    $jenkins = Get-Content -LiteralPath $jenkinsPath -Raw
    Assert-Poc ($jenkins.Contains("migrationCommand: 'cd examples/bytebase-poc && bash ops/bytebase-migrate.sh'")) 'Jenkins must delegate migration to the Bytebase script from the repository root'
    Assert-Poc ($jenkins.Contains("id: 'bytebase-homelab-ci'")) 'Jenkins must reference the Bytebase credential by ID'
    Assert-Poc ($jenkins.Contains("usernameVariable: 'BYTEBASE_SERVICE_ACCOUNT'")) 'Bytebase service account variable binding is missing'
    Assert-Poc ($jenkins.Contains("passwordVariable: 'BYTEBASE_SERVICE_ACCOUNT_SECRET'")) 'Bytebase service key variable binding is missing'
    Assert-Poc (-not ($jenkins -match '(?i)@latest')) 'Bytebase POC must not use an unpinned Shared Library version'
}

$pipelineConfigPath = Join-Path $root 'src\com\company\infra\config\PipelineConfig.groovy'
$environmentConfigPath = Join-Path $root 'src\com\company\infra\config\EnvironmentConfig.groovy'
foreach ($configPath in @($pipelineConfigPath, $environmentConfigPath)) {
    Assert-Poc (Test-Path -LiteralPath $configPath -PathType Leaf) "Missing shared-library config class: $configPath"
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $configSource = Get-Content -LiteralPath $configPath -Raw
        Assert-Poc ($configSource.Contains('import com.cloudbees.groovy.cps.NonCPS')) "Config constructor helpers must import NonCPS: $configPath"
        Assert-Poc ($configSource -match '(?s)@NonCPS\s+private static String text') "text helper must be NonCPS because constructors cannot invoke CPS methods: $configPath"
    }
}

$migrationScriptPath = Join-Path $pocRoot 'ops\bytebase-migrate.sh'
if (Test-Path -LiteralPath $migrationScriptPath -PathType Leaf) {
    $migrationScript = Get-Content -LiteralPath $migrationScriptPath -Raw
    Assert-Poc ($migrationScript.Contains('BYTEBASE_ACTION_IMAGE')) 'Migration script must invoke the pinned Bytebase action image'
    Assert-Poc ($migrationScript.Contains('check')) 'Migration script must run Bytebase SQL review'
    Assert-Poc ($migrationScript.Contains('rollout')) 'Migration script must run Bytebase rollout'
    Assert-Poc ($migrationScript.Contains('FAIL_ON_ERROR')) 'SQL review errors must fail the pipeline'
    Assert-Poc (-not ($migrationScript -match '(?i)\bpsql\b')) 'Migration script must not execute SQL directly with psql'
    Assert-Poc (-not ($migrationScript.Contains('--service-account-secret'))) 'Service key must be passed as an environment variable, not a command argument'
    Assert-Poc ($migrationScript.Contains('docker image inspect')) 'Migration script must resolve the action image before capturing docker create output'
    Assert-Poc ($migrationScript -match 'action_container_id.*\[\[:xdigit:\]\]\{64\}') 'Migration script must validate the docker create container ID'
    Assert-Poc ($migrationScript -match '"\$\{BYTEBASE_ACTION_IMAGE\}"\s+\\\s+bytebase-action') 'Migration script must invoke the bytebase-action binary inside the container image'
}

$migrationFiles = @(Get-ChildItem -LiteralPath (Join-Path $pocRoot 'migrations') -Filter '*.sql' -File | Sort-Object Name)
Assert-Poc ($migrationFiles.Count -ge 3) 'At least three example migrations are required'

$seenVersions = @{}
foreach ($file in $migrationFiles) {
    $matchesConvention = $file.Name -match '^(?<version>\d{12,14})_[a-z0-9][a-z0-9_-]*\.sql$'
    Assert-Poc $matchesConvention "Migration filename is invalid: $($file.Name)"
    if ($matchesConvention) {
        $version = $Matches.version
        Assert-Poc (-not $seenVersions.ContainsKey($version)) "Duplicate migration version: $version"
        $seenVersions[$version] = $true
    }
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($null -ne $docker -and (Test-Path -LiteralPath $composePath -PathType Leaf)) {
    $previousDockerConfig = $env:DOCKER_CONFIG
    $testDockerConfig = Join-Path $PSScriptRoot '.docker-config-test'
    New-Item -ItemType Directory -Path $testDockerConfig -Force | Out-Null
    try {
        $env:DOCKER_CONFIG = $testDockerConfig
        & docker compose --env-file (Join-Path $pocRoot '.env.example') -f $composePath config --quiet
        Assert-Poc ($LASTEXITCODE -eq 0) 'docker compose config failed for the Bytebase POC'
    } finally {
        $env:DOCKER_CONFIG = $previousDockerConfig
    }
}

New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
if ($failures.Count -gt 0) {
    $message = "FAILED`n - " + ($failures -join "`n - ")
    Write-ValidationReport $message
    Write-Error $message
    exit 1
}

$success = "PASS: Bytebase POC structure, migration contract, Jenkins delegation, and Compose configuration validated."
Write-ValidationReport $success
Write-Host $success
