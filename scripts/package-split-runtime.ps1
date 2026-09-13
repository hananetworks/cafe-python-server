param(
    [switch]$SkipEnginePackage,
    [switch]$SkipSttPackage,
    [switch]$SkipTtsPackage
)

$ErrorActionPreference = "Stop"

# Compatibility wrapper. Release CI invokes component-specific packagers so a
# Hailo packaging change cannot invalidate STT or TTS package identities.
if (-not $SkipEnginePackage) { & (Join-Path $PSScriptRoot "package-engine.ps1") }
if (-not $SkipSttPackage) { & (Join-Path $PSScriptRoot "package-stt-assets.ps1") }
if (-not $SkipTtsPackage) {
    . (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")
    $layout = Get-RuntimeModelLayout
    $components = @("ttsCore")
    $packages = if ($layout.HasLocalTtsHfPackages) { @($layout.LocalTtsHfPackages) } else { @($layout.LegacyTtsHfPackages) }
    $components += @($packages | ForEach-Object { Convert-TtsPackageNameToKey -Name $_.File })
    & (Join-Path $PSScriptRoot "package-tts-assets.ps1") -Components $components
}
