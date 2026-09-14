param(
    [string]$Version = "",
    [string]$PlanPath = "runtime-package-plan.json",
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$VisionRoot = Join-Path $RepoRoot "runtime-models\vision"
& (Join-Path $PSScriptRoot "verify-vision-assets.ps1")

. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

if ([string]::IsNullOrWhiteSpace($Version) -and (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
    $Plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
    $VisionPlan = @($Plan.packages | Where-Object component -eq "vision") | Select-Object -First 1
    if ($VisionPlan) { $Version = [string]$VisionPlan.version }
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = if ($env:GITHUB_REF_NAME -and $env:GITHUB_REF_NAME -like "env-v*") { $env:GITHUB_REF_NAME } else { "env-dev" }
}

$Manifest = Get-Content -LiteralPath (Join-Path $VisionRoot "vision-assets.json") -Raw -Encoding utf8 | ConvertFrom-Json
$Runtime = $Manifest.pythonRuntime
$PackageRoot = Join-Path $RepoRoot "vision-assets-package"
$DownloadRoot = Join-Path $RepoRoot ".runtime-work\vision-opencv"
$ArchivePath = Join-Path $RepoRoot "vision-assets.zip"
$ReproArchivePath = Join-Path $RepoRoot ".runtime-work\vision-assets-repro.zip"

foreach ($Path in @($PackageRoot, $DownloadRoot)) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}
if (Test-Path -LiteralPath $ReproArchivePath) { Remove-Item -LiteralPath $ReproArchivePath -Force }

Get-ChildItem -LiteralPath $VisionRoot -Force | Copy-Item -Destination $PackageRoot -Recurse -Force
Write-Utf8NoBom -Path (Join-Path $PackageRoot "version.txt") -Content ($Version + "`n")

$Downloader = (Get-Command python -ErrorAction Stop).Source
& $Downloader -m pip download --disable-pip-version-check --no-deps --only-binary=:all: `
    --platform ([string]$Runtime.platform) --python-version ([string]$Runtime.pythonVersion).Replace(".", "") `
    --implementation cp --dest $DownloadRoot "$([string]$Runtime.distribution)==$([string]$Runtime.version)"
if ($LASTEXITCODE -ne 0) { throw "Unable to download the pinned Vision OpenCV wheel." }

$WheelPath = Join-Path $DownloadRoot ([string]$Runtime.wheel)
if (-not (Test-Path -LiteralPath $WheelPath -PathType Leaf)) {
    throw "Pinned Vision OpenCV wheel was not downloaded: $($Runtime.wheel)"
}
if ((Get-RequiredFileHash -Path $WheelPath) -ne [string]$Runtime.wheelSha256) {
    throw "Pinned Vision OpenCV wheel SHA256 mismatch."
}

$SitePackages = Join-Path $PackageRoot "site-packages"
New-Item -ItemType Directory -Path $SitePackages -Force | Out-Null
& 7z x $WheelPath "-o$SitePackages" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to unpack the pinned Vision OpenCV wheel." }

# Normalize the only filesystem metadata that 7-Zip retains on Windows. Entry
# order and all archive timestamps are normalized by Invoke-DeterministicZip.
Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Force | ForEach-Object { $_.Attributes = [System.IO.FileAttributes]::Normal }

Invoke-DeterministicZip -SourceRoot $PackageRoot -OutputPath $ArchivePath -CompressionLevel 9
Invoke-DeterministicZip -SourceRoot $PackageRoot -OutputPath $ReproArchivePath -CompressionLevel 9
if ((Get-RequiredFileHash -Path $ArchivePath) -ne (Get-RequiredFileHash -Path $ReproArchivePath)) {
    throw "Vision asset package is not deterministic for identical inputs."
}
Remove-Item -LiteralPath $ReproArchivePath -Force

& (Join-Path $PSScriptRoot "verify-vision-package.ps1") -ArchivePath $ArchivePath -ExpectedVersion $Version -PythonExe $PythonExe
Write-Host "Vision asset package includes OpenCV $($Runtime.version) and passed deterministic rebuild verification."
