param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$ArtifactDirectory = "out"
)

$ErrorActionPreference = "Stop"
if ($Tag -notlike "env-v*") { throw "Runtime release tags must match env-v*." }
if ([string]::IsNullOrWhiteSpace($Repository)) { throw "Repository is required." }

& (Join-Path $PSScriptRoot "verify-runtime-artifacts.ps1") -ManifestPath (Join-Path $ArtifactDirectory "runtime-manifest.json") -AssetDirectory $ArtifactDirectory

& gh release view $Tag --repo $Repository *> $null
if ($LASTEXITCODE -eq 0) {
    throw "Release $Tag already exists; existing releases are never overwritten."
}

$manifest = Get-Content -LiteralPath (Join-Path $ArtifactDirectory "runtime-manifest.json") -Raw -Encoding utf8 | ConvertFrom-Json
$assetPaths = @($manifest.packages.PSObject.Properties.Value | ForEach-Object { Join-Path $ArtifactDirectory $_.asset })
$assetPaths += @(
    (Join-Path $ArtifactDirectory "runtime-manifest.json"),
    (Join-Path $ArtifactDirectory "runtime-manifest.json.sha256"),
    (Join-Path $ArtifactDirectory "hash.txt")
)

& gh release create $Tag --repo $Repository --verify-tag --draft --title $Tag @assetPaths
if ($LASTEXITCODE -ne 0) { throw "Draft release upload failed. Any partial upload remains unpublished." }

$releaseJson = & gh api "repos/$Repository/releases/tags/$Tag"
if ($LASTEXITCODE -ne 0) { throw "Unable to verify draft release $Tag." }
$release = ($releaseJson -join "`n") | ConvertFrom-Json
$uploaded = @{}
foreach ($asset in @($release.assets)) { $uploaded[[string]$asset.name] = $asset }

foreach ($path in $assetPaths) {
    $item = Get-Item -LiteralPath $path
    if (-not $uploaded.ContainsKey($item.Name)) { throw "Draft release is missing $($item.Name)." }
    $remote = $uploaded[$item.Name]
    if ([int64]$remote.size -ne $item.Length) { throw "Uploaded size mismatch for $($item.Name)." }
    if ($remote.digest -and [string]$remote.digest -ne "sha256:$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())") {
        throw "Uploaded digest mismatch for $($item.Name)."
    }
}

& gh release edit $Tag --repo $Repository --draft=false --latest
if ($LASTEXITCODE -ne 0) { throw "Draft assets are valid, but publishing $Tag failed." }
Write-Host "Published verified runtime release $Tag."
