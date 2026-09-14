$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$VisionRoot = Join-Path $RepoRoot "runtime-models\vision"
& (Join-Path $PSScriptRoot "verify-vision-assets.ps1")

. (Join-Path $PSScriptRoot "runtime-package-common.ps1")
Invoke-DeterministicZip -SourceRoot $VisionRoot -OutputPath "vision-assets.zip" -CompressionLevel 9
Write-Host "Vision asset package verified."
