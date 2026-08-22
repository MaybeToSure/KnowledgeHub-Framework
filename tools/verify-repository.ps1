[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$healthScript = Join-Path $Root '.agents\skills\knowledge-hub\scripts\knowledge-health.ps1'

& $healthScript -Root $Root
if ($LASTEXITCODE -ne 0) { throw '知识库健康检查失败。' }

& git -C $Root lfs env | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Git LFS 不可用。' }

$manifestPath = Join-Path $Root 'framework.manifest.json'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
foreach ($managedRoot in $manifest.managed_roots) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $managedRoot))) {
        throw "缺少框架管理路径：$managedRoot"
    }
}

Write-Output 'VERIFY_OK'
