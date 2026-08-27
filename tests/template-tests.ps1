[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$reportDirectory = Join-Path $PSScriptRoot 'reports'
$reportPath = Join-Path $reportDirectory 'template-validation.txt'

function Assert-Template {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

$requiredFiles = @(
    'README.md',
    'Jenkinsfile',
    'VERSION',
    'vars\infraPipeline.groovy',
    'src\com\company\infra\config\PipelineConfig.groovy',
    'src\com\company\infra\core\ApplicationPipeline.groovy',
    'src\com\company\infra\runtime\CommandRunner.groovy',
    'examples\consumer-project\Jenkinsfile',
    'examples\consumer-project\ops\deploy.sh',
    'examples\consumer-project\ops\verify.sh',
    'examples\consumer-project\ops\rollback.sh',
    'docs\infra-operations-deployment-pipeline-playbook.docx'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $root $relativePath
    Assert-Template (Test-Path -LiteralPath $fullPath -PathType Leaf) "Missing required file: $relativePath"
}

$pipelinePath = Join-Path $root 'src\com\company\infra\core\ApplicationPipeline.groovy'
if (Test-Path -LiteralPath $pipelinePath -PathType Leaf) {
    $pipeline = Get-Content -LiteralPath $pipelinePath -Raw
    $approvalStart = $pipeline.IndexOf('private void requestApprovals')
    $deployStart = $pipeline.IndexOf('private void deployAndVerify')

    Assert-Template ($approvalStart -ge 0) 'requestApprovals method is missing'
    Assert-Template ($deployStart -gt $approvalStart) 'deployAndVerify must follow requestApprovals'

    if ($approvalStart -ge 0 -and $deployStart -gt $approvalStart) {
        $approvalBody = $pipeline.Substring($approvalStart, $deployStart - $approvalStart)
        Assert-Template ($approvalBody.Contains('steps.input(')) 'Approval method must call Jenkins input'
        Assert-Template (-not $approvalBody.Contains('steps.node(')) 'Approval must not hold a Jenkins node/executor'
        Assert-Template ($approvalBody.Contains('steps.timeout(')) 'Approval must be protected by timeout'
    }

    Assert-Template ($pipeline.Contains('throw originalFailure')) 'Original deployment failure must be rethrown'
    Assert-Template ($pipeline.Contains('attemptRollback')) 'Automatic rollback path is missing'
    Assert-Template ($pipeline.Contains('attemptRollback(environment, context)')) 'Rollback must retain environment variables'
    Assert-Template ($pipeline.Contains("defaultValue: true")) 'DRY_RUN must default to true'
}

$configPath = Join-Path $root 'src\com\company\infra\config\PipelineConfig.groovy'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configSource = Get-Content -LiteralPath $configPath -Raw
    Assert-Template ($configSource.Contains('RESERVED_VARIABLES')) 'Reserved runtime variables must be protected'
    Assert-Template ($configSource.Contains("cannot override reserved variable")) 'Reserved variable validation is missing'
}

$consumerPath = Join-Path $root 'examples\consumer-project\Jenkinsfile'
if (Test-Path -LiteralPath $consumerPath -PathType Leaf) {
    $consumer = Get-Content -LiteralPath $consumerPath -Raw
    Assert-Template ($consumer -match "@Library\('__LIBRARY_NAME__@__LIBRARY_VERSION__'\)") 'Consumer must pin the Shared Library version'
    Assert-Template ($consumer -notmatch "(?i)@latest") 'Consumer must not use an unpinned latest version'
    Assert-Template (($consumer -split "`n").Count -le 120) 'Consumer Jenkinsfile should remain a thin configuration entry point'
}

$codeFiles = Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.Extension -in @('.groovy', '.sh', '.ps1', '.yml', '.yaml') }
$literalSecretPattern = '(?im)^\s*(password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*["''][^<$][^"'']+["'']'

foreach ($file in $codeFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ([System.IO.Path].GetMethods().Name -contains 'GetRelativePath') {
        $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName)
    } else {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')
    }
    Assert-Template (-not ($content -match $literalSecretPattern)) "Possible literal secret in $relative"
}

function Write-ValidationReport {
    param([Parameter(Mandatory)] [string] $Value)

    [System.IO.File]::WriteAllText(
        $reportPath,
        $Value + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$referencePath = Join-Path $root 'docs\infra-operations-deployment-pipeline-playbook.docx'
if (Test-Path -LiteralPath $referencePath -PathType Leaf) {
    Assert-Template ((Get-Item -LiteralPath $referencePath).Length -gt 10000) 'Reference playbook appears empty or corrupted'
}

New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
if ($failures.Count -gt 0) {
    $message = "FAILED`n - " + ($failures -join "`n - ")
    Write-ValidationReport $message
    Write-Error $message
    exit 1
}

$success = "PASS: $($requiredFiles.Count) required files and pipeline safety invariants validated."
Write-ValidationReport $success
Write-Host $success
