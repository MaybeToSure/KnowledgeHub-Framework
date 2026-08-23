[CmdletBinding()]
param(
    [string]$Root,
    [switch]$StrictFrameworkState
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
$version = (Get-Content -Raw -LiteralPath (Join-Path $Root $manifest.version_file)).Trim()
$statePath = Join-Path $Root '.knowledge\framework-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw '缺少 .knowledge/framework-state.json。'
}
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ([string]$state.installed_version -ne $version) {
    throw "框架状态版本 '$($state.installed_version)' 与 VERSION '$version' 不一致。"
}
foreach ($managedRoot in $manifest.managed_roots) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $managedRoot))) {
        throw "缺少框架管理路径：$managedRoot"
    }
}

if ($StrictFrameworkState) {
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

    $managedFiles = @(Get-ManagedFiles -BasePath $Root -Manifest $manifest)
    foreach ($relativePath in $managedFiles) {
        $property = $state.files.PSObject.Properties[$relativePath]
        if (-not $property) {
            throw "框架发布状态缺少受管文件：$relativePath。发布前运行 tools/refresh-framework-state.ps1。"
        }
        $fullPath = Join-Path $Root ($relativePath -replace '/', '\')
        if ((Get-PortableFileHash -Path $fullPath) -ne [string]$property.Value) {
            throw "框架发布状态哈希不匹配：$relativePath。发布前运行 tools/refresh-framework-state.ps1。"
        }
    }
    foreach ($property in $state.files.PSObject.Properties) {
        if ($property.Name -notin $managedFiles) {
            throw "框架发布状态包含已不受管理的文件：$($property.Name)。发布前运行 tools/refresh-framework-state.ps1。"
        }
    }
}

Write-Output 'VERIFY_OK'
