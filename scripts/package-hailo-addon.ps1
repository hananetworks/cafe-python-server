$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$HailoModelsRoot = Join-Path $RepoRoot "runtime-models\hailo\models"
$QwenHef = Join-Path $RepoRoot "runtime-models\hailo\Qwen2.5-1.5B-Instruct.hef"
$HailoWheels = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "libs") -File -Filter "hailort-*.whl")
if ($HailoWheels.Count -ne 1) {
    throw "Exactly one HailoRT wheel is required in libs/."
}

$HailoAssetDir = "hailo-assets-package"
if (Test-Path $HailoAssetDir) { Remove-Item $HailoAssetDir -Recurse -Force }
New-Item -ItemType Directory -Path "$HailoAssetDir\models" -Force | Out-Null
New-Item -ItemType Directory -Path "$HailoAssetDir\site-packages" -Force | Out-Null

& 7z x $HailoWheels[0].FullName "-o$HailoAssetDir\site-packages" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to unpack $($HailoWheels[0].Name)." }
if (-not (Test-Path -LiteralPath "$HailoAssetDir\site-packages\hailo_platform" -PathType Container)) {
    throw "HailoRT wheel does not contain hailo_platform."
}

$HailoFiles = @()
if (Test-Path -LiteralPath $HailoModelsRoot -PathType Container) {
    $HailoFiles = @(Get-ChildItem -LiteralPath $HailoModelsRoot -File -Filter "*.hef" | Select-Object -ExpandProperty FullName)
}
if ($HailoFiles.Count -eq 0) { throw "No Hailo HEF models were found in runtime-models\hailo\models." }

foreach ($file in $HailoFiles) {
    Copy-Item -Path $file -Destination "$HailoAssetDir\models" -Force
}

if (Test-Path $QwenHef) {
    Copy-Item -Path $QwenHef -Destination $HailoAssetDir -Force
} else {
    Write-Host "Qwen2.5-1.5B-Instruct.hef not found. Building Hailo addon without it."
}

. (Join-Path $PSScriptRoot "runtime-package-common.ps1")
Invoke-DeterministicZip -SourceRoot $HailoAssetDir -OutputPath "hailo-addon.zip" -CompressionLevel 9
Write-Host "Hailo addon includes $($HailoWheels[0].Name) and model assets."
