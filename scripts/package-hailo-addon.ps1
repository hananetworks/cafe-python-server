$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")
$Layout = Get-RuntimeModelLayout

$HailoAssetDir = "hailo-assets-package"
if (Test-Path $HailoAssetDir) { Remove-Item $HailoAssetDir -Recurse -Force }
New-Item -ItemType Directory -Path "$HailoAssetDir\models" -Force | Out-Null

$ArchiveInputs = @("models")
$HailoFiles = @()
if ($Layout.HasLocalHailoModels) {
    $HailoFiles = @(Get-ChildItem -Path $Layout.LocalHailoModelsRoot -File -Filter "*.hef" | Select-Object -ExpandProperty FullName)
}

foreach ($file in $HailoFiles) {
    Copy-Item -Path $file -Destination "$HailoAssetDir\models" -Force
}

$QwenHef = $Layout.LocalQwenHefPath
if (Test-Path $QwenHef) {
    Copy-Item -Path $QwenHef -Destination $HailoAssetDir -Force
    $ArchiveInputs += "Qwen2.5-1.5B-Instruct.hef"
} else {
    Write-Host "Qwen2.5-1.5B-Instruct.hef not found. Building Hailo addon without it."
}

Push-Location $HailoAssetDir
7z a -mx=9 "..\hailo-addon.zip" @ArchiveInputs
Pop-Location
