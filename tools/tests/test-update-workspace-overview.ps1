$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $env:TEMP ('KnowledgeHub-overview-test-' + [guid]::NewGuid().ToString('N'))
try {
    $hub = Join-Path $testRoot 'KnowledgeHub'
    $project = Join-Path $testRoot 'analog-electronics'
    New-Item -ItemType Directory -Force -Path (Join-Path $hub '.knowledge'), (Join-Path $hub '00-Inbox\Human\Quick-Captures'), (Join-Path $project 'docs') | Out-Null
    [IO.File]::WriteAllText((Join-Path $hub '.knowledge\local-config.json'), (@{
        workspaceRoot = $testRoot; knowledgeHubRoot = $hub; projectRepositoriesRoot = $testRoot
    } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $hub 'README.md'), '# KnowledgeHub', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $hub '00-Inbox\Human\Quick-Captures\capture.md'), '# Capture', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $project 'work.yaml'), "schema_version: 1`nid: course/analog-electronics`nname: `"模电原理`"`ntype: course`nstatus: active`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $project 'README.md'), '# 模电原理', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $project 'docs\lesson.md'), '# Lesson', [Text.UTF8Encoding]::new($false))
    & git init -b main $hub | Out-Null
    & git -C $hub add --all
    & git -C $hub commit -m 'test hub' | Out-Null
    & git init -b main $project | Out-Null
    & git -C $project add --all
    & git -C $project commit -m 'test project' | Out-Null

    $generator = Join-Path (Split-Path -Parent $PSScriptRoot) 'update-workspace-overview.ps1'
    & $generator -Root $hub | Out-Null
    $overview = Join-Path $hub '_Dashboard\工作区总览.md'
    $content = [IO.File]::ReadAllText($overview, [Text.Encoding]::UTF8)
    if ($content -notmatch 'generated: true') { throw '总览缺少生成标记。' }
    if ($content -notmatch '模电原理') { throw '总览缺少受管理仓库。' }
    if ($content -notmatch '待处理随手记：1 条') { throw '随手记计数不正确。' }
    if ($content -notmatch '\[\[analog-electronics/README\]\]') { throw '仓库入口链接不正确。' }
    if ($content -match '`t') { throw '最近提交包含字面量 `t。' }
    if ($content -notmatch "最近提交：[^`r`n]*`t") { throw '最近提交的时间与标题分隔不正确。' }
    if ($content -notmatch 'test hub' -or $content -notmatch 'test project') { throw '最近提交标题缺失。' }

    [IO.File]::WriteAllText((Join-Path $hub '_Dashboard\人工关注.md'), "# 人工内容`n", [Text.UTF8Encoding]::new($false))
    & $generator -Root $hub | Out-Null
    if ([IO.File]::ReadAllText((Join-Path $hub '_Dashboard\人工关注.md'), [Text.Encoding]::UTF8) -notmatch '人工内容') { throw '人工关注页被覆盖。' }

    [IO.File]::WriteAllText($overview, "# 人工总览`n", [Text.UTF8Encoding]::new($false))
    $blocked = $false
    try { & $generator -Root $hub | Out-Null } catch { $blocked = $true }
    if (-not $blocked) { throw '生成器覆盖了未标记的人工文件。' }
    Write-Output 'OVERVIEW_TEST_OK'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = (Resolve-Path -LiteralPath $testRoot).Path
        $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).Path
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolved) -notlike 'KnowledgeHub-overview-test-*') {
            throw "拒绝清理非测试路径：$resolved"
        }
        Get-ChildItem -LiteralPath $resolved -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
        [IO.Directory]::Delete($resolved, $true)
    }
}
