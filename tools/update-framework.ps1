[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FrameworkSource,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$FrameworkSource = (Resolve-Path -LiteralPath $FrameworkSource).Path
if ($Root -eq $FrameworkSource) { throw '框架源目录不能与目标知识库相同。' }

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

$sourceManifestPath = Join-Path $FrameworkSource 'framework.manifest.json'
if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
    throw '框架源目录缺少 framework.manifest.json。'
}
$sourceManifest = Get-Content -Raw -LiteralPath $sourceManifestPath | ConvertFrom-Json
$sourceVersion = (Get-Content -Raw -LiteralPath (Join-Path $FrameworkSource $sourceManifest.version_file)).Trim()
$statePath = Join-Path $Root '.knowledge\framework-state.json'
$oldState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $oldState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $Root ".knowledge\framework-backups\$timestamp"
$updated = [System.Collections.Generic.List[string]]::new()
$added = [System.Collections.Generic.List[string]]::new()
$unchanged = [System.Collections.Generic.List[string]]::new()
$conflicts = [System.Collections.Generic.List[string]]::new()
$newHashes = [ordered]@{}

foreach ($relativePath in Get-ManagedFiles -BasePath $FrameworkSource -Manifest $sourceManifest) {
    $sourcePath = Join-Path $FrameworkSource ($relativePath -replace '/', '\')
    $targetPath = Join-Path $Root ($relativePath -replace '/', '\')
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
    $oldBaseline = $null
    if ($oldState -and $oldState.files -and $oldState.files.PSObject.Properties[$relativePath]) {
        $oldBaseline = [string]$oldState.files.PSObject.Properties[$relativePath].Value
    }

    if (-not $targetExists) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
        $added.Add($relativePath)
        $newHashes[$relativePath] = $sourceHash
        continue
    }

    $targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash.ToLowerInvariant()
    if ($targetHash -eq $sourceHash) {
        $unchanged.Add($relativePath)
        $newHashes[$relativePath] = $sourceHash
    } elseif ($oldBaseline -and $targetHash -eq $oldBaseline) {
        $backupPath = Join-Path $backupRoot ($relativePath -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Copy-Item -LiteralPath $targetPath -Destination $backupPath
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $updated.Add($relativePath)
        $newHashes[$relativePath] = $sourceHash
    } else {
        $conflicts.Add($relativePath)
        if ($oldBaseline) { $newHashes[$relativePath] = $oldBaseline }
    }
}

$installedVersion = if ($conflicts.Count -eq 0) { $sourceVersion } elseif ($oldState) { $oldState.installed_version } else { 'unknown' }
$newState = [ordered]@{
    installed_version = $installedVersion
    last_attempted_version = $sourceVersion
    generated_at = (Get-Date).ToString('o')
    files = $newHashes
    conflicts = @($conflicts)
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $statePath) | Out-Null
[IO.File]::WriteAllText($statePath, ($newState | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

[pscustomobject]@{
    source_version = $sourceVersion
    installed_version = $installedVersion
    updated = @($updated)
    added = @($added)
    unchanged_count = $unchanged.Count
    conflicts = @($conflicts)
    backup = if ($updated.Count -gt 0) { $backupRoot } else { $null }
} | ConvertTo-Json -Depth 10

if ($conflicts.Count -gt 0) { exit 2 }
