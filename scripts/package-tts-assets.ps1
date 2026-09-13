param([Parameter(Mandatory = $true)][string[]]$Components)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")
. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")

$layout = Get-RuntimeModelLayout

if ($Components -contains "ttsCore") {
    Invoke-DeterministicZip -SourceRoot "tts-assets-package" -OutputPath "tts-core-assets.zip" -CompressionLevel 3 -ExcludePatterns @(
        '^huggingface(?:/|$)',
        '^_[^/]+\.json$'
    )
    Write-Host "Packaged ttsCore."
}

$packages = if ($layout.HasLocalTtsHfPackages) { @($layout.LocalTtsHfPackages) } else { @($layout.LegacyTtsHfPackages) }
foreach ($package in $packages) {
    $component = Convert-TtsPackageNameToKey -Name $package.File
    if ($Components -notcontains $component) { continue }

    if ($layout.HasLocalTtsHfPackages) {
        $source = $package.SourceDir
        Invoke-DeterministicZip -SourceRoot $source -OutputPath $package.File -CompressionLevel 1
    } else {
        $hub = "tts-assets-package\huggingface\hub"
        $source = @($package.CacheDirs | ForEach-Object { Join-Path $hub $_ } | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
        if (-not $source) { throw "Prepared TTS source is missing for $component." }
        $sourceName = [Regex]::Escape((Split-Path -Leaf $source))
        Invoke-DeterministicZip -SourceRoot $hub -OutputPath $package.File -CompressionLevel 1 -IncludePatterns @("^$sourceName(?:/|$)")
    }
    Write-Host "Packaged $component."
}
