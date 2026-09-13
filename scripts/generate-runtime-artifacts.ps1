$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")

function Get-RequiredHash {
    param([string]$Path)

    return (Get-FileHash $Path -Algorithm SHA256).Hash
}

$releaseVersion = $env:GITHUB_REF_NAME
if ([string]::IsNullOrWhiteSpace($releaseVersion)) { $releaseVersion = "env-dev" }

$ttsPackages = @(
    @{ Key = "ttsCore"; File = "tts-core-assets.zip"; Required = $true; ExtractTo = "python/tts/core"; VersionField = "ttsCoreVersion" }
)

foreach ($hfZip in @(Get-ChildItem -Path $PWD -File -Filter "tts-hf-*.zip" | Sort-Object Name)) {
    $key = Convert-TtsPackageNameToKey -Name $hfZip.Name
    $ttsPackages += @{
        Key = $key
        File = $hfZip.Name
        Required = $false
        ExtractTo = "python/tts/hf/hub"
        VersionField = "$($key)Version"
    }
}

$hashEngine = Get-RequiredHash "python-engine.zip"
$hashStt = Get-RequiredHash "stt-assets.zip"
$hashTtsCore = Get-RequiredHash "tts-core-assets.zip"
$hashHailo = Get-RequiredHash "hailo-addon.zip"
$ttsPackages = foreach ($ttsPackage in $ttsPackages) {
    $package = $ttsPackage.Clone()
    if ($package.Key -eq "ttsCore") {
        $package.Hash = $hashTtsCore
    }
    $package
}

@(
    "Engine: $hashEngine"
    "STT: $hashStt"
    "TTS-CORE: $hashTtsCore"
    "HAILO: $hashHailo"
) | Set-Content -Encoding Ascii hash.txt

$packageMap = [ordered]@{
    engine = @{ required = $true; version = $releaseVersion; file = "python-engine.zip"; sha256 = $hashEngine; extractTo = "python/engine" }
    stt    = @{ required = $true; version = $releaseVersion; file = "stt-assets.zip"; sha256 = $hashStt; extractTo = "python/stt" }
    hailo  = @{ required = $false; version = $releaseVersion; file = "hailo-addon.zip"; sha256 = $hashHailo; extractTo = "python/hailo" }
}

$manifest = [ordered]@{
    manifestVersion = 1
    engineVersion = $releaseVersion
    sttVersion = $releaseVersion
    ttsVersion = $releaseVersion
    ttsCoreVersion = $releaseVersion
    hailoVersion = $releaseVersion
    packages = $packageMap
}

foreach ($ttsPackage in $ttsPackages) {
    if (Test-Path $ttsPackage.File) {
        if (-not $ttsPackage.Hash) {
            $ttsPackage.Hash = Get-RequiredHash $ttsPackage.File
        }
        "$($ttsPackage.Key): $($ttsPackage.Hash)" | Add-Content -Encoding Ascii hash.txt
        $packageMap[$ttsPackage.Key] = @{
            required = $ttsPackage.Required
            version = $releaseVersion
            file = $ttsPackage.File
            sha256 = $ttsPackage.Hash
            extractTo = $ttsPackage.ExtractTo
        }
        $manifest[$ttsPackage.VersionField] = $releaseVersion
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText(
    (Join-Path $PWD "runtime-manifest.json"),
    $manifestJson,
    [System.Text.UTF8Encoding]::new($false)
)

$manifestPath = Join-Path $PWD "runtime-manifest.json"
$manifestSha256Path = Join-Path $PWD "runtime-manifest.json.sha256"
$manifestHash = Get-RequiredHash $manifestPath

"$manifestHash  runtime-manifest.json" | Set-Content -Path $manifestSha256Path -Encoding Ascii
