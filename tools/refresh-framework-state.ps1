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
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

[pscustomobject]@{
    refreshed = $true
    version = $version
    files = $hashes.Count
    state = $statePath
} | ConvertTo-Json -Depth 5
