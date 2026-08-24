[CmdletBinding()]
param(
    [string]$Root,
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Split-Path -Parent $Root
}
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'KnowledgeHub'))
if (-not $Root.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "KnowledgeHub must be located at <WorkspaceRoot>\KnowledgeHub. Root: $Root; WorkspaceRoot: $WorkspaceRoot"
}

function Get-ManagedFiles {
    param([string]$BasePath, [object]$Manifest)

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($relativeFile in $Manifest.managed_files) {
        if (Test-Path -LiteralPath (Join-Path $BasePath $relativeFile) -PathType Leaf) {
            $result.Add(($relativeFile -replace '\\', '/'))
        }
    }
    foreach ($relativeRoot in $Manifest.managed_roots) {
        $fullRoot = Join-Path $BasePath $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Force | ForEach-Object {
            $relative = $_.FullName.Substring($BasePath.Length).TrimStart([char[]]'\/') -replace '\\', '/'
            $result.Add($relative)
        }
    }
    return @($result | Sort-Object -Unique)
}

function Get-PortableFileHash {
    param([string]$Path)

    $name = [IO.Path]::GetFileName($Path)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $textNames = @('.gitattributes', '.gitignore', 'AGENTS.md', 'LICENSE', 'README.md', 'VERSION')
    $textExtensions = @('.md', '.yaml', '.yml', '.json', '.jsonl', '.csv', '.tsv', '.ps1')
    if ($name -in $textNames -or $extension -in $textExtensions) {
        $text = [IO.File]::ReadAllText($Path)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    } else {
        $bytes = [IO.File]::ReadAllBytes($Path)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$requiredDirectories = @(
    '.knowledge', '.obsidian', '_Dashboard', '00-Inbox\Human', '00-Inbox\Human\Quick-Captures', '00-Inbox\Agents',
    '10-Sources\Attachments', '10-Sources\Attachments\Quick-Captures',
    '20-Knowledge', '30-Notes', '30-Notes\Quick-Capture-Summaries', '40-Courses',
    '50-Projects', '60-Experiments', '70-Outputs', '90-Archive',
    '90-Archive\Quick-Captures',
    'Rules\Local', 'Templates\Custom'
)
foreach ($directory in $requiredDirectories) {
    $fullDirectory = Join-Path $Root $directory
    New-Item -ItemType Directory -Force -Path $fullDirectory | Out-Null
    if ($directory -notin @('.knowledge', '.obsidian', '_Dashboard', 'Rules\Local', 'Templates\Custom')) {
        $hasFiles = @(Get-ChildItem -LiteralPath $fullDirectory -File -Force -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $hasFiles) {
            New-Item -ItemType File -Force -Path (Join-Path $fullDirectory '.gitkeep') | Out-Null
        }
    }
}

$obsidianConfigPath = Join-Path $Root '.obsidian\app.json'
$recommendedConfig = [ordered]@{
    alwaysUpdateLinks = $true
    newLinkFormat = 'relative'
    attachmentFolderPath = '10-Sources/Attachments'
}
if (Test-Path -LiteralPath $obsidianConfigPath) {
    $obsidianConfig = Get-Content -Raw -LiteralPath $obsidianConfigPath | ConvertFrom-Json
    $changed = $false
    foreach ($entry in $recommendedConfig.GetEnumerator()) {
        if ($null -eq $obsidianConfig.PSObject.Properties[$entry.Key]) {
            $obsidianConfig | Add-Member -NotePropertyName $entry.Key -NotePropertyValue $entry.Value
            $changed = $true
        }
    }
    if ($changed) {
        [IO.File]::WriteAllText($obsidianConfigPath, ($obsidianConfig | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
    }
} else {
    [IO.File]::WriteAllText($obsidianConfigPath, ($recommendedConfig | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

$gitMetadataPath = Join-Path $Root '.git'
if (-not (Test-Path -LiteralPath $gitMetadataPath)) {
    & git init -b main $Root | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Git 仓库初始化失败。' }
}

& git -C $Root lfs install --local | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Git LFS 不可用，请先安装 Git LFS。' }

$manifestPath = Join-Path $Root 'framework.manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$version = (Get-Content -Raw -LiteralPath (Join-Path $Root $manifest.version_file)).Trim()
$hashes = [ordered]@{}
foreach ($relativePath in Get-ManagedFiles -BasePath $Root -Manifest $manifest) {
    $hashes[$relativePath] = Get-PortableFileHash -Path (Join-Path $Root ($relativePath -replace '/', '\'))
}
$state = [ordered]@{
    installed_version = $version
    generated_at = (Get-Date).ToString('o')
    files = $hashes
}
$statePath = Join-Path $Root '.knowledge\framework-state.json'
$stateUpdated = -not (Test-Path -LiteralPath $statePath -PathType Leaf)
if ($stateUpdated) {
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
} else {
    $existingState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ([string]$existingState.installed_version -ne $version) {
        throw "framework-state.json records version '$($existingState.installed_version)', but VERSION is '$version'. Framework maintainers must refresh the release state; existing instances must use tools/update-framework.ps1."
    }
}

$localConfig = [ordered]@{
    workspaceRoot = $WorkspaceRoot
    knowledgeHubRoot = $Root
    projectRepositoriesRoot = $WorkspaceRoot
}
$localConfigPath = Join-Path $Root '.knowledge\local-config.json'
[IO.File]::WriteAllText($localConfigPath, ($localConfig | ConvertTo-Json -Depth 5) + [Environment]::NewLine)

$overviewScript = Join-Path $Root 'tools\update-workspace-overview.ps1'
if (Test-Path -LiteralPath $overviewScript -PathType Leaf) {
    & $overviewScript -Root $Root | Out-Null
}

[pscustomobject]@{
    root = $Root
    workspace_root = $WorkspaceRoot
    local_config = $localConfigPath
    framework_version = $version
    managed_files = $hashes.Count
    state_updated = $stateUpdated
    git_initialized = $true
    lfs_initialized = $true
} | ConvertTo-Json -Depth 5
