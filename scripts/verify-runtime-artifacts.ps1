param(
    [string]$ManifestPath = "runtime-manifest.json",
    [string]$AssetDirectory = ".",
    [string]$PlanPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ([int]$manifest.manifestVersion -lt 2) { throw "Runtime manifest v2 or newer is required." }
if ([string]$manifest.sourceFingerprintAlgorithm -ne "git-tree-sha256-v1") { throw "Unsupported source fingerprint algorithm." }

$seenAssets = @{}
foreach ($property in $manifest.packages.PSObject.Properties) {
    $component = $property.Name
    $package = $property.Value
    foreach ($requiredField in @("component", "version", "sourceFingerprint", "recipeFingerprint", "packageFingerprint", "archiveSha256", "sha256", "size", "asset", "file", "extractTo")) {
        if ($null -eq $package.$requiredField -or [string]::IsNullOrWhiteSpace([string]$package.$requiredField)) {
            throw "$component is missing manifest field '$requiredField'."
        }
    }
    if ([string]$package.component -ne $component) { throw "$component has a mismatched component field." }
    if ($seenAssets.ContainsKey([string]$package.asset)) { throw "Duplicate release asset: $($package.asset)" }
    $seenAssets[[string]$package.asset] = $true

    $path = Join-Path $AssetDirectory ([string]$package.asset)
    & 7z t $path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$component release archive failed the 7-Zip integrity test." }
    $actualSize = (Get-Item -LiteralPath $path).Length
    $actualHash = Get-RequiredFileHash -Path $path
    if ($actualSize -ne [int64]$package.size) { throw "$component asset size does not match the manifest." }
    if ($actualHash -ne [string]$package.sha256 -or $actualHash -ne [string]$package.archiveSha256) {
        throw "$component asset SHA256 does not match the manifest."
    }
}

if ($PlanPath) {
    $plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($planned in @($plan.packages)) {
        $package = $manifest.packages.PSObject.Properties[[string]$planned.component].Value
        if (-not $package) { throw "Manifest is missing planned component $($planned.component)." }
        if ($planned.action -eq "reuse") {
            if ([string]$package.sha256 -ne [string]$planned.baseSha256 -or [int64]$package.size -ne [int64]$planned.baseSize) {
                throw "Reused component $($planned.component) changed from the base release."
            }
        }
    }
}

$sidecar = "$ManifestPath.sha256"
if (Test-Path -LiteralPath $sidecar) {
    $expected = ((Get-Content -LiteralPath $sidecar -Raw) -split '\s+')[0].ToUpperInvariant()
    if ((Get-RequiredFileHash -Path $ManifestPath) -ne $expected) { throw "Manifest sidecar SHA256 mismatch." }
}

Write-Host "Runtime manifest and $($seenAssets.Count) release assets are consistent."
