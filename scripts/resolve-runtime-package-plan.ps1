param(
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$CurrentRef = $(if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { "HEAD" }),
    [string]$CurrentRelease = $(if ($env:GITHUB_REF_NAME -and $env:GITHUB_REF_NAME -like "env-v*") { $env:GITHUB_REF_NAME } else { "env-dev" }),
    [string]$BaseRelease = "",
    [string]$PlanPath = "runtime-package-plan.json",
    [string]$BaseManifestPath = "",
    [string]$BaseAssetsPath = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")
. (Join-Path $PSScriptRoot "runtime-package-plan.ps1")

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $json = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI request failed: gh $($Arguments -join ' ')" }
    return (($json -join "`n") | ConvertFrom-Json)
}

if ([string]::IsNullOrWhiteSpace($BaseRelease)) {
    if ([string]::IsNullOrWhiteSpace($Repository)) {
        throw "Repository is required when BaseRelease is not provided."
    }
    $releases = Invoke-GhJson -Arguments @("api", "repos/$Repository/releases?per_page=100")
    $base = @($releases) | Where-Object {
        -not $_.draft -and -not $_.prerelease -and $_.tag_name -like "env-v*" -and $_.tag_name -ne $CurrentRelease
    } | Select-Object -First 1
    if (-not $base) { throw "No previous env-v* release was found for $Repository." }
    $BaseRelease = [string]$base.tag_name
}

if ($BaseManifestPath) {
    $baseManifest = Get-Content -LiteralPath $BaseManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
} else {
    if ([string]::IsNullOrWhiteSpace($Repository)) { throw "Repository is required to load the base manifest." }
    $release = Invoke-GhJson -Arguments @("api", "repos/$Repository/releases/tags/$BaseRelease")
    $manifestAsset = @($release.assets) | Where-Object { $_.name -eq "runtime-manifest.json" } | Select-Object -First 1
    if (-not $manifestAsset) { throw "$BaseRelease does not contain runtime-manifest.json." }
    $manifestSidecar = @($release.assets) | Where-Object { $_.name -eq "runtime-manifest.json.sha256" } | Select-Object -First 1
    if (-not $manifestSidecar) { throw "$BaseRelease does not contain runtime-manifest.json.sha256." }
    $manifestWork = Join-Path ([System.IO.Path]::GetFullPath(".runtime-work")) ("base-manifest-{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $manifestWork -Force | Out-Null
    try {
        & gh release download $BaseRelease --repo $Repository --pattern "runtime-manifest.json" --pattern "runtime-manifest.json.sha256" --dir $manifestWork --clobber
        if ($LASTEXITCODE -ne 0) { throw "Unable to download the $BaseRelease runtime manifest." }
        $downloadedManifest = Join-Path $manifestWork "runtime-manifest.json"
        $downloadedSidecar = Join-Path $manifestWork "runtime-manifest.json.sha256"
        $expectedManifestHash = ((Get-Content -LiteralPath $downloadedSidecar -Raw) -split '\s+')[0].ToUpperInvariant()
        if ((Get-RequiredFileHash -Path $downloadedManifest) -ne $expectedManifestHash) {
            throw "$BaseRelease runtime manifest SHA256 mismatch."
        }
        $baseManifest = Get-Content -LiteralPath $downloadedManifest -Raw -Encoding utf8 | ConvertFrom-Json
    } finally {
        if (Test-Path -LiteralPath $manifestWork) { Remove-Item -LiteralPath $manifestWork -Recurse -Force }
    }
}

if ($BaseAssetsPath) {
    $baseAssets = Get-Content -LiteralPath $BaseAssetsPath -Raw -Encoding utf8 | ConvertFrom-Json
} elseif ($release) {
    $baseAssets = @($release.assets | ForEach-Object { [pscustomobject]@{ name = $_.name; size = [int64]$_.size } })
} else {
    if ([string]::IsNullOrWhiteSpace($Repository)) { throw "Repository is required to load base asset metadata." }
    $release = Invoke-GhJson -Arguments @("api", "repos/$Repository/releases/tags/$BaseRelease")
    $baseAssets = @($release.assets | ForEach-Object { [pscustomobject]@{ name = $_.name; size = [int64]$_.size } })
}

$plan = New-RuntimePackagePlan -CurrentRef $CurrentRef -CurrentRelease $CurrentRelease -BaseRelease $BaseRelease -BaseManifest $baseManifest -BaseAssets $baseAssets
$planJson = $plan | ConvertTo-Json -Depth 8
Write-Utf8NoBom -Path ([System.IO.Path]::GetFullPath($PlanPath)) -Content $planJson

$rebuild = @($plan.packages | Where-Object { $_.action -eq "rebuild" })
$ttsRebuild = @($rebuild | Where-Object { $_.component -eq "ttsCore" -or $_.component -like "tts*" })
$engine = $plan.packages | Where-Object { $_.component -eq "engine" } | Select-Object -First 1
$stt = $plan.packages | Where-Object { $_.component -eq "stt" } | Select-Object -First 1
$hailo = $plan.packages | Where-Object { $_.component -eq "hailo" } | Select-Object -First 1
$vision = $plan.packages | Where-Object { $_.component -eq "vision" } | Select-Object -First 1
$ttsRebuildFingerprint = if ($ttsRebuild.Count -gt 0) {
    Get-RecordFingerprint -Label "tts-rebuild-set-v1" -Records @($ttsRebuild | ForEach-Object { "$($_.component)`0$($_.packageFingerprint)" })
} else { "none" }

Write-GitHubOutput -Name "base_release" -Value $BaseRelease
Write-GitHubOutput -Name "engine_action" -Value ([string]$engine.action)
Write-GitHubOutput -Name "engine_fingerprint" -Value ([string]$engine.packageFingerprint)
Write-GitHubOutput -Name "stt_action" -Value ([string]$stt.action)
Write-GitHubOutput -Name "stt_fingerprint" -Value ([string]$stt.packageFingerprint)
Write-GitHubOutput -Name "hailo_action" -Value ([string]$hailo.action)
Write-GitHubOutput -Name "hailo_fingerprint" -Value ([string]$hailo.packageFingerprint)
Write-GitHubOutput -Name "vision_action" -Value ([string]$vision.action)
Write-GitHubOutput -Name "vision_fingerprint" -Value ([string]$vision.packageFingerprint)
Write-GitHubOutput -Name "vision_version" -Value ([string]$vision.version)
Write-GitHubOutput -Name "tts_rebuild" -Value $($ttsRebuild.Count -gt 0).ToString().ToLowerInvariant()
Write-GitHubOutput -Name "tts_rebuild_fingerprint" -Value $ttsRebuildFingerprint
Write-GitHubOutput -Name "needs_reused_engine_for_tts" -Value $(($ttsRebuild.Count -gt 0 -and $engine.action -eq "reuse").ToString().ToLowerInvariant())
Write-GitHubOutput -Name "rebuild_components" -Value (($rebuild.component) -join ",")

Write-Host "Base release: $BaseRelease"
foreach ($package in $plan.packages) {
    Write-Host ("{0,-36} {1}" -f $package.component, $package.action.ToUpperInvariant())
}
