param(
    [string]$PlanPath = "runtime-package-plan.json",
    [string]$OutputDirectory = "."
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
$releaseVersion = if ($env:GITHUB_REF_NAME -and $env:GITHUB_REF_NAME -like "env-v*") { $env:GITHUB_REF_NAME } else { [string]$plan.releaseVersion }
if ([string]::IsNullOrWhiteSpace($releaseVersion)) { $releaseVersion = "env-dev" }

$packageMap = [ordered]@{}
$hashLines = @()
foreach ($planned in @($plan.packages)) {
    $assetPath = Join-Path $OutputDirectory ([string]$planned.file)
    $hash = Get-RequiredFileHash -Path $assetPath
    $size = (Get-Item -LiteralPath $assetPath).Length

    if ($planned.action -eq "reuse") {
        if ($hash -ne [string]$planned.baseSha256) {
            throw "$($planned.file) was marked for reuse but its SHA256 changed."
        }
        if ($size -ne [int64]$planned.baseSize) {
            throw "$($planned.file) was marked for reuse but its size changed."
        }
    }

    $componentVersion = if ($planned.action -eq "reuse") { [string]$planned.version } else { $releaseVersion }
    $packageMap[[string]$planned.component] = [ordered]@{
        component = [string]$planned.component
        required = [bool]$planned.required
        version = $componentVersion
        sourceFingerprint = [string]$planned.sourceFingerprint
        recipeFingerprint = [string]$planned.recipeFingerprint
        packageFingerprint = [string]$planned.packageFingerprint
        archiveSha256 = $hash
        sha256 = $hash
        size = [int64]$size
        asset = [string]$planned.file
        file = [string]$planned.file
        extractTo = [string]$planned.extractTo
    }
    $hashLines += "$($planned.component): $hash  $size  $($planned.file)"
}

function Get-PackageVersion([string]$Component) {
    if ($packageMap.Contains($Component)) { return [string]$packageMap[$Component].version }
    return $null
}

$ttsPackages = @($plan.packages | Where-Object { $_.component -eq "ttsCore" -or $_.component -like "tts*" })
$ttsChanged = @($ttsPackages | Where-Object { $_.action -eq "rebuild" }).Count -gt 0
$manifest = [ordered]@{
    manifestVersion = 2
    sourceFingerprintAlgorithm = [string]$plan.sourceFingerprintAlgorithm
    releaseVersion = $releaseVersion
    baseRelease = [string]$plan.baseRelease
    engineVersion = Get-PackageVersion "engine"
    sttVersion = Get-PackageVersion "stt"
    ttsVersion = if ($ttsChanged) { $releaseVersion } elseif ($plan.baseTtsVersion) { [string]$plan.baseTtsVersion } else { Get-PackageVersion "ttsCore" }
    ttsCoreVersion = Get-PackageVersion "ttsCore"
    hailoVersion = Get-PackageVersion "hailo"
    visionVersion = Get-PackageVersion "vision"
    packages = $packageMap
}

foreach ($component in @($packageMap.Keys | Where-Object { $_ -like "tts*" -and $_ -ne "ttsCore" })) {
    $manifest["${component}Version"] = [string]$packageMap[$component].version
}

$manifestPath = Join-Path $OutputDirectory "runtime-manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 8
Write-Utf8NoBom -Path $manifestPath -Content $manifestJson
$manifestHash = Get-RequiredFileHash -Path $manifestPath
"$manifestHash  runtime-manifest.json" | Set-Content -LiteralPath (Join-Path $OutputDirectory "runtime-manifest.json.sha256") -Encoding Ascii
$hashLines | Set-Content -LiteralPath (Join-Path $OutputDirectory "hash.txt") -Encoding Ascii

Write-Host "Generated manifest v2 for $releaseVersion."
