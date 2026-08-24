[CmdletBinding()]
param(
    [string]$Root,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$Root = (Resolve-Path -LiteralPath $Root).Path
$localConfigPath = Join-Path $Root '.knowledge\local-config.json'
if (-not (Test-Path -LiteralPath $localConfigPath -PathType Leaf)) {
    throw '缺少 .knowledge/local-config.json，请先运行 tools/setup.ps1。'
}
$localConfig = Get-Content -Raw -LiteralPath $localConfigPath | ConvertFrom-Json
$workspaceRoot = [IO.Path]::GetFullPath([string]$localConfig.workspaceRoot)
$repositoriesRoot = [IO.Path]::GetFullPath([string]$localConfig.projectRepositoriesRoot)
if (-not (Test-Path -LiteralPath $repositoriesRoot -PathType Container)) {
    throw "项目仓库根目录不存在：$repositoriesRoot"
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-TopLevelWorkMetadata {
    param([string]$Path)
    $result = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        if ($line -match '^(id|name|type|status):\s*(.*?)\s*$') {
            $value = $Matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $result[$Matches[1]] = $value
        }
    }
    return $result
}

function Get-VaultLinkPath {
    param([string]$Target)
    $fullTarget = [IO.Path]::GetFullPath($Target)
    $prefix = $workspaceRoot.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
    if ($fullTarget.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullTarget.Substring($prefix.Length).Replace('\', '/')
    }
    return $null
}

function Get-RepositoryFacts {
    param([string]$RepositoryPath, [hashtable]$Metadata)
    $lastCommit = (& git -C $RepositoryPath log -1 --format='%cI%x09%s' 2>$null | Select-Object -First 1)
    $recentDocuments = @()
    $trackedMarkdown = @(& git -C $RepositoryPath -c core.quotePath=false ls-files -- '*.md' 2>$null)
    $recentDocuments = @($trackedMarkdown | ForEach-Object {
        $relative = [string]$_
        $fullPath = Join-Path $RepositoryPath ($relative -replace '/', '\')
        if ($relative -notin @('README.md', 'AGENTS.md') -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            [pscustomobject]@{ Relative = $relative; Modified = (Get-Item -LiteralPath $fullPath).LastWriteTimeUtc }
        }
    } | Sort-Object Modified -Descending | Select-Object -First 3)
    return [pscustomobject]@{
        Path = $RepositoryPath
        Id = if ($Metadata.id) { [string]$Metadata.id } else { Split-Path -Leaf $RepositoryPath }
        Name = if ($Metadata.name) { [string]$Metadata.name } else { Split-Path -Leaf $RepositoryPath }
        Type = if ($Metadata.type) { [string]$Metadata.type } else { '未登记' }
        Status = if ($Metadata.status) { [string]$Metadata.status } else { '未登记' }
        LastCommit = [string]$lastCommit
        RecentDocuments = $recentDocuments
    }
}

$repositories = [System.Collections.Generic.List[object]]::new()
Get-ChildItem -LiteralPath $repositoriesRoot -Directory -Force | ForEach-Object {
    $workFile = Join-Path $_.FullName 'work.yaml'
    $gitPath = Join-Path $_.FullName '.git'
    if ((Test-Path -LiteralPath $workFile -PathType Leaf) -and (Test-Path -LiteralPath $gitPath)) {
        $repositories.Add((Get-RepositoryFacts -RepositoryPath $_.FullName -Metadata (Get-TopLevelWorkMetadata -Path $workFile)))
    }
}

$hubFacts = Get-RepositoryFacts -RepositoryPath $Root -Metadata @{
    id = 'knowledge-hub'; name = 'KnowledgeHub'; type = 'knowledge'; status = 'active'
}
$quickCaptureRoot = Join-Path $Root '00-Inbox\Human\Quick-Captures'
$quickCaptureCount = if (Test-Path -LiteralPath $quickCaptureRoot) {
    @(Get-ChildItem -LiteralPath $quickCaptureRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue).Count
} else { 0 }

$lines = [System.Collections.Generic.List[string]]::new()
$generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
@(
    '---',
    'generated: true',
    'generator: tools/update-workspace-overview.ps1',
    "generated_at: $generatedAt",
    '---',
    '',
    '# 工作区总览（自动生成）',
    '',
    "> 本页由 Codex 根据仓库事实自动生成。人工内容请写入 [[KnowledgeHub/_Dashboard/工作区总览-手动维护]]。",
    '',
    '## KnowledgeHub',
    '',
    "- 状态：$($hubFacts.Status)",
    "- 待处理随手记：$quickCaptureCount 条",
    '- 入口：[[KnowledgeHub/README]]'
) | ForEach-Object { $lines.Add($_) }
if ($hubFacts.LastCommit) { $lines.Add("- 最近提交：$($hubFacts.LastCommit)") }

$lines.Add('')
$lines.Add('## 受管理仓库')
$lines.Add('')
if ($repositories.Count -eq 0) {
    $lines.Add('- 暂未发现包含 `work.yaml` 的独立 Git 仓库。')
} else {
    foreach ($repository in @($repositories | Sort-Object Name)) {
        $lines.Add("### $($repository.Name)")
        $lines.Add('')
        $lines.Add("- ID：``$($repository.Id)``")
        $lines.Add("- 类型：$($repository.Type)")
        $lines.Add("- 状态：$($repository.Status)")
        $readmeLink = Get-VaultLinkPath -Target (Join-Path $repository.Path 'README.md')
        if ($readmeLink) { $lines.Add("- 入口：[[$($readmeLink -replace '\.md$', '')]]") }
        else { $lines.Add("- 本地路径：``$($repository.Path)``") }
        if ($repository.LastCommit) { $lines.Add("- 最近提交：$($repository.LastCommit)") }
        if ($repository.RecentDocuments.Count -gt 0) {
            $lines.Add('- 最近文档：')
            foreach ($document in $repository.RecentDocuments) {
                $link = Get-VaultLinkPath -Target (Join-Path $repository.Path ($document.Relative -replace '/', '\'))
                if ($link) { $lines.Add("  - [[$($link -replace '\.md$', '')]]") }
            }
        }
        $lines.Add('')
    }
}

$lines.Add('## 待处理')
$lines.Add('')
$lines.Add("- KnowledgeHub 随手记：$quickCaptureCount 条")
$lines.Add('- ChatGPT 与 Slack 中尚未同步的记录由人工在对应入口确认；本工具不读取聊天服务。')
$lines.Add('')
$lines.Add('## 更新方式')
$lines.Add('')
$lines.Add('```powershell')
$lines.Add('powershell -ExecutionPolicy Bypass -File .\tools\update-workspace-overview.ps1')
$lines.Add('```')
$lines.Add('')

if (-not $OutputPath) { $OutputPath = Join-Path $Root '_Dashboard\工作区总览-自动生成.md' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    $existingHead = (Get-Content -LiteralPath $OutputPath -TotalCount 12) -join "`n"
    if ($existingHead -notmatch '(?m)^generated:\s*true\s*$' -or
        $existingHead -notmatch '(?m)^generator:\s*tools/update-workspace-overview\.ps1\s*$') {
        throw "拒绝覆盖未标记为本工具生成的文件：$OutputPath"
    }
}
Write-Utf8File -Path $OutputPath -Content (($lines -join "`n") + "`n")

$humanPath = Join-Path (Split-Path -Parent $OutputPath) '工作区总览-手动维护.md'
if (-not (Test-Path -LiteralPath $humanPath -PathType Leaf)) {
    Write-Utf8File -Path $humanPath -Content "# 工作区总览（手动维护）`n`n本页由人工或经人工明确授权的 Codex 维护；自动生成器不得覆盖。`n"
}

[pscustomobject]@{
    generated = $true
    overview = $OutputPath
    human_notes = $humanPath
    repositories = $repositories.Count
    quick_captures = $quickCaptureCount
    generated_at = $generatedAt
} | ConvertTo-Json -Depth 5
