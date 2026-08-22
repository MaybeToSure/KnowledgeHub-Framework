[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([string]$Level, [string]$Code, [string]$Message)
    $findings.Add([pscustomobject]@{ level = $Level; code = $Code; message = $Message })
}

$requiredDirectories = @(
    '00-Inbox\Human', '00-Inbox\Agents', '10-Sources\Attachments',
    '20-Knowledge', '30-Notes', '40-Courses', '50-Projects',
    '60-Experiments', '70-Outputs', '90-Archive',
    'Rules\Core', 'Rules\Local', 'Templates\Core', 'Templates\Custom'
)
foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
        Add-Finding 'error' 'missing-directory' "缺少必需目录：$directory"
    }
}

$projectsRoot = Join-Path $Root '50-Projects'
if (Test-Path -LiteralPath $projectsRoot) {
    $nestedRepositories = @(Get-ChildItem -LiteralPath $projectsRoot -Force -Recurse -Filter '.git' -ErrorAction SilentlyContinue)
    foreach ($nestedRepository in $nestedRepositories) {
        $relativeNestedPath = $nestedRepository.FullName.Substring($Root.Length).TrimStart('\')
        Add-Finding 'error' 'nested-git-repository' "50-Projects 中发现嵌套 Git 仓库：$relativeNestedPath"
    }
}

$gitMetadataPath = Join-Path $Root '.git'
if (-not (Test-Path -LiteralPath $gitMetadataPath)) {
    Add-Finding 'error' 'not-git-repository' '当前知识库尚未初始化为 Git 仓库。'
} else {
    $statusLines = @(& git -C $Root status --short)
    if ($statusLines.Count -gt 0) {
        Add-Finding 'info' 'working-tree-changes' "工作区存在 $($statusLines.Count) 项变更。"
    }

    $trackedFiles = @(& git -c core.quotepath=false -C $Root ls-files)
    foreach ($relativePath in $trackedFiles) {
        if ($relativePath -match '(^|/)(\.env($|\.)|[^/]+\.(pem|key|p12|pfx)$|id_rsa$|id_ed25519$)') {
            Add-Finding 'error' 'tracked-secret-file' "疑似敏感文件已被跟踪：$relativePath"
        }
        $fullPath = Join-Path $Root ($relativePath -replace '/', '\')
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $file = Get-Item -LiteralPath $fullPath
            if ($file.Length -gt 100MB) {
                $attribute = (& git -C $Root check-attr filter -- $relativePath)
                if ($attribute -notmatch ': filter: lfs$') {
                    Add-Finding 'error' 'large-file-without-lfs' "超过 100MB 但未使用 Git LFS：$relativePath"
                }
            }
        }
    }
}

$errors = @($findings | Where-Object level -eq 'error')
[pscustomobject]@{
    root = $Root
    healthy = ($errors.Count -eq 0)
    findings = @($findings)
} | ConvertTo-Json -Depth 5

if ($errors.Count -gt 0) { exit 1 }
