param(
    [switch]$SkipEnginePackage,
    [switch]$SkipSttPackage,
    [switch]$SkipTtsPackage
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")
$Layout = Get-RuntimeModelLayout

Write-Host "Packaging engine runtime..."
if ($SkipEnginePackage) {
    Write-Host "Reusing previous python-engine.zip"
} else {
    if (Test-Path "python-engine.zip") { Remove-Item "python-engine.zip" -Force }
    Push-Location "python-env"
    # Exclude only archive-root runtime asset folders. Recursive excludes like
    # -xr!models also strip package paths such as Lib/site-packages/torchaudio/models.
    $engineZipArgs = @(
        "a",
        "-mx=9",
        "..\python-engine.zip",
        "*",
        "-x!models",
        "-x!models\*",
        "-x!tts_models",
        "-x!tts_models\*"
    )
    & 7z @engineZipArgs
    $EnginePackageExitCode = $LASTEXITCODE
    Pop-Location
    if ($EnginePackageExitCode -ne 0) {
        throw "7-Zip failed to create python-engine.zip (exit=$EnginePackageExitCode)."
    }
}

if (-not (Test-Path "python-engine.zip")) {
    throw "python-engine.zip was not created."
}

$EngineArchive = Get-Item "python-engine.zip"
if ($EngineArchive.Length -lt 1MB) {
    throw "python-engine.zip is unexpectedly small: $($EngineArchive.Length) bytes."
}

& 7z t "python-engine.zip"
if ($LASTEXITCODE -ne 0) {
    throw "python-engine.zip failed the 7-Zip integrity test."
}

$EngineEntries = & 7z l -slt "python-engine.zip"
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect python-engine.zip."
}
foreach ($RequiredEntry in @("Path = kiosk_python.exe", "Path = python311._pth")) {
    if ($EngineEntries -notcontains $RequiredEntry) {
        throw "python-engine.zip is missing required root entry: $RequiredEntry"
    }
}
Write-Host "Engine package verified: kiosk_python.exe and python311._pth are present."

Write-Host "Packaging STT assets..."
if ($SkipSttPackage) {
    Write-Host "Reusing previous stt-assets.zip"
} else {
    if (Test-Path "stt-assets.zip") { Remove-Item "stt-assets.zip" -Force }
    if ($Layout.HasLocalStt) {
        Push-Location $Layout.LocalSttRoot
        7z a -mx=9 "..\..\stt-assets.zip" "*"
        Pop-Location
    } else {
        throw "STT model source not found in runtime-models\\stt."
    }
}

Write-Host "Packaging TTS assets..."
if ($SkipTtsPackage) {
    Write-Host "Reusing previous TTS asset packages"
} else {
    Push-Location "tts-assets-package"
    7z a -mx=3 "..\tts-core-assets.zip" "piper_models" "sherpa_models" "nltk_data"
    Pop-Location

    $HubDir = "tts-assets-package\huggingface\hub"
    if ($Layout.HasLocalTtsHfPackages) {
        foreach ($package in @($Layout.LocalTtsHfPackages)) {
            if (Test-Path $package.File) { Remove-Item $package.File -Force }
            Push-Location $package.SourceDir
            Write-Host "Packaging local TTS HF asset: $($package.File)..."
            7z a -mx=1 "..\..\..\$($package.File)" "*"
            Pop-Location
        }
    } else {
        Push-Location $HubDir
        foreach ($package in @($Layout.LegacyTtsHfPackages)) {
            $sourceDir = $package.CacheDirs | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($sourceDir) {
                if (Test-Path "..\..\..\$($package.File)") { Remove-Item "..\..\..\$($package.File)" -Force }
                Write-Host "Packaging TTS HF cache: $($package.Name) from $sourceDir..."
                7z a -mx=1 "..\..\..\$($package.File)" $sourceDir
            } else {
                Write-Host "Skipping missing TTS HF cache: $($package.CacheDirs -join ', ')"
            }
        }
        Pop-Location
    }
}
