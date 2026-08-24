[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RepositoryName,
    [ValidateSet('Course', 'Engineering', 'Experiment', 'Research', 'Writing', 'Generic')]
    [string]$Type = 'Generic',
    [string]$KnowledgeHubRoot,
    [string]$Destination,
    [ValidateSet('None', 'GitHubPrivate')]
    [string]$RemoteMode = 'None',
    [string]$GitHubRepository
)

$ErrorActionPreference = 'Stop'
if (-not $KnowledgeHubRoot) {
    $KnowledgeHubRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$KnowledgeHubRoot = (Resolve-Path -LiteralPath $KnowledgeHubRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $KnowledgeHubRoot 'framework.manifest.json') -PathType Leaf)) {
    throw 'KnowledgeHubRoot is not a valid KnowledgeHub root.'
}

if (-not $Destination) {
    $projectRepositoriesRoot = Split-Path -Parent $KnowledgeHubRoot
    $localConfigPath = Join-Path $KnowledgeHubRoot '.knowledge\local-config.json'
    if (Test-Path -LiteralPath $localConfigPath -PathType Leaf) {
        $localConfig = Get-Content -Raw -LiteralPath $localConfigPath | ConvertFrom-Json
        if ($localConfig.projectRepositoriesRoot) {
            $projectRepositoriesRoot = [IO.Path]::GetFullPath([string]$localConfig.projectRepositoriesRoot)
        }
    }
    $Destination = Join-Path $projectRepositoriesRoot $RepositoryName
}
$Destination = [IO.Path]::GetFullPath($Destination)
$hubPrefix = $KnowledgeHubRoot.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
if ($Destination.Equals($KnowledgeHubRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $Destination.StartsWith($hubPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'An independent repository cannot be created inside KnowledgeHub.'
}

if (Test-Path -LiteralPath $Destination) {
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        throw "Destination is not a directory: $Destination"
    }
    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) {
        throw "Destination directory is not empty: $Destination"
    }
} else {
    New-Item -ItemType Directory -Path $Destination | Out-Null
}

$typeConfig = @{
    Course = @{
        EntryRoot = '40-Courses'; EntryType = 'course'; IdPrefix = 'course'
        Directories = @('docs', 'notes', 'exercises', 'projects', 'resources')
    }
    Engineering = @{
        EntryRoot = '50-Projects'; EntryType = 'project'; IdPrefix = 'project'
        Directories = @('docs', 'src', 'tests', 'tools')
    }
    Experiment = @{
        EntryRoot = '60-Experiments'; EntryType = 'experiment'; IdPrefix = 'experiment'
        Directories = @('docs', 'protocols', 'data/raw', 'data/processed', 'results')
    }
    Research = @{
        EntryRoot = '50-Projects'; EntryType = 'project'; IdPrefix = 'research'
        Directories = @('docs', 'sources', 'notes', 'analysis', 'outputs')
    }
    Writing = @{
        EntryRoot = '70-Outputs'; EntryType = 'output'; IdPrefix = 'writing'
        Directories = @('docs', 'sources', 'drafts', 'assets', 'outputs')
    }
    Generic = @{
        EntryRoot = '50-Projects'; EntryType = 'project'; IdPrefix = 'work'
        Directories = @('docs', 'work', 'outputs')
    }
}
$config = $typeConfig[$Type]
$workId = "$($config.IdPrefix)/$RepositoryName"
$entryDirectory = Join-Path (Join-Path $KnowledgeHubRoot $config.EntryRoot) $RepositoryName
$entryPath = Join-Path $entryDirectory 'entry.md'
if (Test-Path -LiteralPath $entryDirectory) {
    throw "KnowledgeHub entry already exists: $entryDirectory"
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

foreach ($directory in $config.Directories) {
    $fullDirectory = Join-Path $Destination $directory
    New-Item -ItemType Directory -Force -Path $fullDirectory | Out-Null
    Write-Utf8File -Path (Join-Path $fullDirectory '.gitkeep') -Content ''
}

$today = Get-Date -Format 'yyyy-MM-dd'
$hubRevision = ((& git -C $KnowledgeHubRoot rev-list --max-count=1 --all) | Select-Object -First 1)
if ($hubRevision) { $hubRevision = $hubRevision.Trim() } else { $hubRevision = '' }
$escapedName = $Name.Replace('"', '\"')
$normalizedHubPath = $KnowledgeHubRoot.Replace('\', '/')
$normalizedDestination = $Destination.Replace('\', '/')
$relativeEntry = "$($config.EntryRoot)/$RepositoryName/entry.md"

$readme = @"
# $Name

Type: $Type
Work unit ID: $workId

## Goal

Describe the intended outcome, acceptance criteria, and non-goals here.

## KnowledgeHub relationship

- KnowledgeHub: $KnowledgeHubRoot
- KnowledgeHub entry: $relativeEntry
- Import only the context needed by this task. Return reusable outcomes to KnowledgeHub.

## Start here

Read AGENTS.md and work.yaml, then maintain requirements, plans, and verification evidence.
"@

$agents = @"
# AGENTS.md

- This is an independent work repository and must not be nested inside KnowledgeHub.
- Human instructions have the highest priority. Obtain explicit authorization for high-risk, irreversible, or external publishing actions.
- Read README.md, work.yaml, and relevant docs before starting a task.
- Import only task-relevant knowledge and record its stable ID and KnowledgeHub revision.
- Keep work-specific material here. Return reusable conclusions, methods, and evidence to KnowledgeHub.
- Run risk-appropriate tests or checks after changes and report uncovered risks.
"@

$manifest = @"
schema_version: 1
id: $workId
name: "$escapedName"
type: $($Type.ToLowerInvariant())
status: active
created_at: $today
default_branch: main
knowledge_hub:
  local_path: "$normalizedHubPath"
  entry: "$relativeEntry"
  revision: "$hubRevision"
knowledge_inputs: []
reusable_outputs: []
"@

Write-Utf8File -Path (Join-Path $Destination 'README.md') -Content $readme
Write-Utf8File -Path (Join-Path $Destination 'AGENTS.md') -Content $agents
Write-Utf8File -Path (Join-Path $Destination 'work.yaml') -Content $manifest
Write-Utf8File -Path (Join-Path $Destination '.gitignore') -Content ".env`n*.secret`n.DS_Store`nThumbs.db`n"

& git init -b main $Destination | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to initialize the independent Git repository.' }
& git -C $Destination add --all
& git -C $Destination commit -m 'chore: initialize work repository' | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Initial commit failed. Configure Git identity, commit the preserved files manually, then ask Codex to register the repository.'
}
$projectRevision = (& git -C $Destination rev-parse HEAD).Trim()

$remoteUrl = ''
if ($RemoteMode -eq 'GitHubPrivate') {
    if (-not $GitHubRepository -or $GitHubRepository -notmatch '^[^/\s]+/[^/\s]+$') {
        throw 'GitHubPrivate mode requires -GitHubRepository <owner>/<repo>.'
    }
    & gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run gh auth login first.' }
    & gh repo create $GitHubRepository --private --source $Destination --remote origin
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to create the private GitHub repository. Local files remain and KnowledgeHub was not registered.'
    }
    $remoteUrl = (& git -C $Destination remote get-url origin).Trim()
}

$remoteDisplay = if ($remoteUrl) { $remoteUrl } else { 'Not created' }
$entry = @"
---
id: $workId
title: "$escapedName"
type: $($config.EntryType)
work_type: $($Type.ToLowerInvariant())
status: active
authority: human
locked: false
created_by: codex
created_at: "$today"
updated_by: codex
updated_at: "$today"
local_repository: "$normalizedDestination"
remote_repository: "$remoteUrl"
default_branch: main
project_revision: "$projectRevision"
knowledge_revision: "$hubRevision"
---

# $Name

## Goal and scope

To be refined by the human owner and Codex.

## Knowledge inputs

- Not assembled yet.

## Repository links

- Local: $Destination
- Remote: $remoteDisplay
- Baseline commit: $projectRevision

## Key decisions

- The repository is physically separate from KnowledgeHub and linked by stable IDs and revisions.

## Reusable outcomes

- None yet.

## Verification evidence

- Repository scaffold created and initial commit completed.
"@
Write-Utf8File -Path $entryPath -Content $entry

$overviewUpdated = $false
$overviewScript = Join-Path $KnowledgeHubRoot 'tools\update-workspace-overview.ps1'
if (Test-Path -LiteralPath $overviewScript -PathType Leaf) {
    & $overviewScript -Root $KnowledgeHubRoot | Out-Null
    $overviewUpdated = $true
}

[pscustomobject]@{
    id = $workId
    type = $Type
    local_repository = $Destination
    remote_mode = $RemoteMode
    remote_repository = $remoteUrl
    repository_revision = $projectRevision
    knowledge_entry = $entryPath
    knowledge_revision_before_registration = $hubRevision
    workspace_overview_updated = $overviewUpdated
    next_action = 'Review and commit the KnowledgeHub entry separately. Run git push only when explicitly intended.'
} | ConvertTo-Json -Depth 5
