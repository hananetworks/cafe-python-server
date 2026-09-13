$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$repoRoot = Split-Path $PSScriptRoot -Parent
$sttRoot = Join-Path $repoRoot "runtime-models\stt"
if (-not (Test-Path -LiteralPath $sttRoot -PathType Container) -or @(Get-ChildItem -LiteralPath $sttRoot -Recurse -File -Force).Count -eq 0) {
    throw "STT model source not found in runtime-models\stt."
}
Invoke-DeterministicZip -SourceRoot $sttRoot -OutputPath "stt-assets.zip" -CompressionLevel 9
Write-Host "STT asset package verified."
