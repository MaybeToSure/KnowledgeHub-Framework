[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path

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

$requiredDirectories = @(
    '.knowledge', '.obsidian', '00-Inbox\Human', '00-Inbox\Agents',
    '10-Sources\Attachments', '20-Knowledge', '30-Notes', '40-Courses',
    '50-Projects', '60-Experiments', '70-Outputs', '90-Archive',
    'Rules\Local', 'Templates\Custom'
)
foreach ($directory in $requiredDirectories) {
    $fullDirectory = Join-Path $Root $directory
    New-Item -ItemType Directory -Force -Path $fullDirectory | Out-Null
    if ($directory -notin @('.knowledge', '.obsidian', 'Rules\Local', 'Templates\Custom')) {
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
    $hashes[$relativePath] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root ($relativePath -replace '/', '\'))).Hash.ToLowerInvariant()
}
$state = [ordered]@{
    installed_version = $version
    generated_at = (Get-Date).ToString('o')
    files = $hashes
}
$statePath = Join-Path $Root '.knowledge\framework-state.json'
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

[pscustomobject]@{
    root = $Root
    framework_version = $version
    managed_files = $hashes.Count
    git_initialized = $true
    lfs_initialized = $true
} | ConvertTo-Json -Depth 5
