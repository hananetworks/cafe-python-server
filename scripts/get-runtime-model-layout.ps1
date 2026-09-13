function Convert-TtsPackageNameToKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    if ($stem.StartsWith("tts-hf-")) {
        $stem = $stem.Substring(7)
    }

    $parts = $stem -split "-"
    $suffix = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        if ($_.Length -eq 1) { $_.ToUpperInvariant() }
        else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join ""

    return "tts$suffix"
}

function Get-RuntimeModelLayout {
    param(
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    )

    $runtimeRoot = Join-Path $RepoRoot "runtime-models"
    $legacyConfigPath = Join-Path $runtimeRoot "speech-assets.json"
    $legacyConfig = $null
    if (Test-Path $legacyConfigPath) {
        $legacyConfig = Get-Content -Path $legacyConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
    }

    $localTtsHfRoot = Join-Path $runtimeRoot "tts\hf"
    $localTtsHfPackages = @()
    if (Test-Path $localTtsHfRoot) {
        foreach ($dir in @(Get-ChildItem -Path $localTtsHfRoot -Directory -Filter "tts-hf-*")) {
            $key = Convert-TtsPackageNameToKey -Name $dir.Name
            $localTtsHfPackages += [pscustomobject]@{
                Name = $dir.Name
                File = "$($dir.Name).zip"
                Key = $key
                VersionField = "$($key)Version"
                SourceDir = $dir.FullName
            }
        }
    }

    $legacyTtsHfPackages = @()
    if ($legacyConfig) {
        foreach ($repo in @($legacyConfig.tts.huggingFaceRepos)) {
            $legacyTtsHfPackages += [pscustomobject]@{
                Name = $repo.key
                File = $repo.zipFile
                Key = $repo.key
                VersionField = $repo.versionField
                CacheDirs = @($repo.cacheDirs)
            }
        }
    }

    return [pscustomobject]@{
        RuntimeRoot = $runtimeRoot
        LocalSttRoot = Join-Path $runtimeRoot "stt"
        HasLocalStt = (Test-Path (Join-Path $runtimeRoot "stt")) -and ((Get-ChildItem -Path (Join-Path $runtimeRoot "stt") -Force | Measure-Object).Count -gt 0)
        LocalHailoRoot = Join-Path $runtimeRoot "hailo"
        LocalHailoModelsRoot = Join-Path $runtimeRoot "hailo\models"
        LocalQwenHefPath = Join-Path $runtimeRoot "hailo\Qwen2.5-1.5B-Instruct.hef"
        HasLocalHailoModels = (Test-Path (Join-Path $runtimeRoot "hailo\models")) -and ((Get-ChildItem -Path (Join-Path $runtimeRoot "hailo\models") -File -Filter "*.hef" -Force | Measure-Object).Count -gt 0)
        LocalTtsCoreRoot = Join-Path $runtimeRoot "tts\core"
        HasLocalTtsCore = (Test-Path (Join-Path $runtimeRoot "tts\core\piper_models")) -and (Test-Path (Join-Path $runtimeRoot "tts\core\sherpa_models"))
        LocalTtsHfRoot = $localTtsHfRoot
        LocalTtsHfPackages = $localTtsHfPackages
        HasLocalTtsHfPackages = $localTtsHfPackages.Count -gt 0
        LegacyConfig = $legacyConfig
        LegacyTtsHfPackages = $legacyTtsHfPackages
    }
}

function Get-ExpectedTtsAssetFiles {
    param(
        [Parameter(Mandatory = $true)]
        $Layout
    )

    $files = @("tts-core-assets.zip")
    if ($Layout.HasLocalTtsHfPackages) {
        $files += @($Layout.LocalTtsHfPackages | ForEach-Object { $_.File })
    } else {
        $files += @($Layout.LegacyTtsHfPackages | ForEach-Object { $_.File })
    }

    return $files
}
