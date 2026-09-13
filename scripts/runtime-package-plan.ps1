$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "runtime-package-common.ps1")
. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")

$script:MigrationBaseRelease = "env-v1.4.36"

function Get-GitTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $text = & git show "${Ref}:$Path" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return ($text -join "`n")
}

function Get-GitTreeRecords {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [string]$IncludePattern = "",
        [string]$ExcludePattern = ""
    )

    $lines = @(& git ls-tree -r --full-tree $Ref -- @Paths 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect git ref '$Ref'."
    }

    $records = foreach ($line in $lines) {
        if ($line -notmatch '^[0-9]+\s+blob\s+([0-9a-f]+)\t(.+)$') { continue }
        $oid = $Matches[1]
        $path = $Matches[2].Replace('\', '/')
        if ($IncludePattern -and $path -notmatch $IncludePattern) { continue }
        if ($ExcludePattern -and $path -match $ExcludePattern) { continue }
        "$path`0$oid"
    }
    return @($records | Sort-Object)
}

function Get-RecordFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Records
    )

    return Get-Sha256Text -Text ("$Label`n" + (($Records | Sort-Object) -join "`n"))
}

function Get-TtsConfigAtRef {
    param([Parameter(Mandatory = $true)][string]$Ref)

    $text = Get-GitTextFile -Ref $Ref -Path "runtime-models/speech-assets.json"
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Get-TtsPackageDefinitionsAtRef {
    param([Parameter(Mandatory = $true)][string]$Ref)

    $definitions = @()
    $localRecords = Get-GitTreeRecords -Ref $Ref -Paths @("runtime-models/tts/hf") -ExcludePattern '/\.gitkeep$'
    $localRoots = @($localRecords | ForEach-Object {
        $path = ($_ -split "`0", 2)[0]
        if ($path -match '^(runtime-models/tts/hf/tts-hf-[^/]+)/') { $Matches[1] }
    } | Sort-Object -Unique)

    if ($localRoots.Count -gt 0) {
        foreach ($root in $localRoots) {
            $name = Split-Path -Leaf $root
            $file = "$name.zip"
            $definitions += [pscustomobject][ordered]@{
                component = Convert-TtsPackageNameToKey -Name $file
                file = $file
                required = $false
                extractTo = "python/tts/hf/hub"
                kind = "ttsHfLocal"
                sourcePath = $root
                configKey = $null
            }
        }
        return $definitions
    }

    $config = Get-TtsConfigAtRef -Ref $Ref
    if ($config) {
        foreach ($repo in @($config.tts.huggingFaceRepos)) {
            $definitions += [pscustomobject][ordered]@{
                component = Convert-TtsPackageNameToKey -Name $repo.zipFile
                file = [string]$repo.zipFile
                required = $false
                extractTo = "python/tts/hf/hub"
                kind = "ttsHfConfig"
                sourcePath = $null
                configKey = [string]$repo.key
            }
        }
    }
    return $definitions
}

function Get-PackageDefinitionsAtRef {
    param([Parameter(Mandatory = $true)][string]$Ref)

    $definitions = @(
        [pscustomobject][ordered]@{ component = "engine"; file = "python-engine.zip"; required = $true; extractTo = "python/engine"; kind = "engine"; sourcePath = $null; configKey = $null },
        [pscustomobject][ordered]@{ component = "stt"; file = "stt-assets.zip"; required = $true; extractTo = "python/stt"; kind = "stt"; sourcePath = "runtime-models/stt"; configKey = $null },
        [pscustomobject][ordered]@{ component = "hailo"; file = "hailo-addon.zip"; required = $false; extractTo = "python/hailo"; kind = "hailo"; sourcePath = "runtime-models/hailo"; configKey = $null },
        [pscustomobject][ordered]@{ component = "ttsCore"; file = "tts-core-assets.zip"; required = $true; extractTo = "python/tts/core"; kind = "ttsCore"; sourcePath = "runtime-models/tts/core"; configKey = $null }
    )
    $definitions += @(Get-TtsPackageDefinitionsAtRef -Ref $Ref)
    return $definitions
}

function Get-TtsRepoConfigRecord {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$ZipFile
    )

    $repo = @($Config.tts.huggingFaceRepos) | Where-Object { $_.zipFile -eq $ZipFile } | Select-Object -First 1
    if (-not $repo) { return $null }
    $record = [ordered]@{
        repo_id = $repo.repo_id
        zipFile = $repo.zipFile
        cacheDirs = @($repo.cacheDirs)
        allow_patterns = @($repo.allow_patterns)
    }
    return ($record | ConvertTo-Json -Compress -Depth 6)
}

function Get-ComponentSourceFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)]$Definition
    )

    switch ($Definition.kind) {
        "engine" {
            $records = @(Get-GitTreeRecords -Ref $Ref -Paths @("requirements.txt"))
            $records += @(Get-GitTreeRecords -Ref $Ref -Paths @("libs") -IncludePattern '\.whl$' -ExcludePattern '/hailort-[^/]+\.whl$')
            $records += "embedded-python`03.11.9"
            $records += "get-pip`0https://bootstrap.pypa.io/get-pip.py"
            return Get-RecordFingerprint -Label "engine-source-v1" -Records $records
        }
        "stt" {
            $records = Get-GitTreeRecords -Ref $Ref -Paths @($Definition.sourcePath) -ExcludePattern '/\.gitkeep$'
            return Get-RecordFingerprint -Label "stt-source-v1" -Records $records
        }
        "hailo" {
            $records = @(Get-GitTreeRecords -Ref $Ref -Paths @("runtime-models/hailo") -ExcludePattern '/\.gitkeep$')
            $records += @(Get-GitTreeRecords -Ref $Ref -Paths @("libs") -IncludePattern '/hailort-[^/]+\.whl$')
            return Get-RecordFingerprint -Label "hailo-source-v1" -Records $records
        }
        "ttsCore" {
            $local = Get-GitTreeRecords -Ref $Ref -Paths @($Definition.sourcePath) -ExcludePattern '/\.gitkeep$'
            if ($local.Count -gt 0) {
                return Get-RecordFingerprint -Label "tts-core-local-v1" -Records $local
            }
            $config = Get-TtsConfigAtRef -Ref $Ref
            if (-not $config) { throw "TTS configuration is missing at $Ref." }
            $record = [ordered]@{
                piperVoiceRepo = $config.tts.piperVoiceRepo
                piperFiles = @($config.tts.piperFiles)
                sherpaRepo = $config.tts.sherpaRepo
                sherpaModelDir = $config.tts.sherpaModelDir
                sherpaFiles = @($config.tts.sherpaFiles)
                nltkResources = @($config.tts.nltkResources)
            } | ConvertTo-Json -Compress -Depth 6
            return Get-RecordFingerprint -Label "tts-core-config-v1" -Records @($record)
        }
        "ttsHfLocal" {
            $records = Get-GitTreeRecords -Ref $Ref -Paths @($Definition.sourcePath) -ExcludePattern '/\.gitkeep$'
            return Get-RecordFingerprint -Label "tts-hf-local-v1:$($Definition.component)" -Records $records
        }
        "ttsHfConfig" {
            $config = Get-TtsConfigAtRef -Ref $Ref
            if (-not $config) { throw "TTS configuration is missing at $Ref." }
            $record = Get-TtsRepoConfigRecord -Config $config -ZipFile $Definition.file
            if (-not $record) { throw "TTS package config is missing for $($Definition.file) at $Ref." }
            return Get-RecordFingerprint -Label "tts-hf-config-v1:$($Definition.component)" -Records @($record)
        }
        default { throw "Unknown package kind: $($Definition.kind)" }
    }
}

function Get-RecipeFingerprint {
    param([Parameter(Mandatory = $true)]$Definition)

    $files = switch ($Definition.kind) {
        "engine" { @("scripts/build-python-env.ps1", "scripts/package-engine.ps1") }
        "stt" { @("scripts/package-stt-assets.ps1") }
        "hailo" { @("scripts/package-hailo-addon.ps1") }
        { $_ -in @("ttsCore", "ttsHfLocal", "ttsHfConfig") } { @("scripts/prepare-speech-assets.ps1", "scripts/package-tts-assets.ps1", "scripts/get-runtime-model-layout.ps1") }
        default { throw "Unknown package kind: $($Definition.kind)" }
    }

    $records = foreach ($file in $files) {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package recipe file is missing: $file" }
        $normalized = [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
        "$file`0$(Get-Sha256Text -Text $normalized)"
    }
    return Get-RecordFingerprint -Label "package-recipe-v1:$($Definition.kind)" -Records $records
}

function Get-LegacyRecipeFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$BaseRelease,
        [Parameter(Mandatory = $true)]$Definition,
        [Parameter(Mandatory = $true)][string]$CurrentRecipeFingerprint
    )

    if ($BaseRelease -ne $script:MigrationBaseRelease) { return $null }
    if ($Definition.kind -in @("stt", "ttsCore", "ttsHfLocal", "ttsHfConfig")) {
        # env-v1.4.36 used the same archive layout for these components. The new
        # package-specific scripts only isolate the old commands from each other.
        return $CurrentRecipeFingerprint
    }
    return "legacy-$($Definition.kind)-recipe"
}

function Get-ManifestPackage {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Component
    )

    $property = $Manifest.packages.PSObject.Properties[$Component]
    if ($property) { return $property.Value }
    return $null
}

function New-PackageDecision {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentSourceFingerprint,
        [Parameter(Mandatory = $true)][string]$CurrentRecipeFingerprint,
        [AllowNull()][string]$BaseSourceFingerprint,
        [AllowNull()][string]$BaseRecipeFingerprint
    )

    if ($BaseSourceFingerprint -and $BaseRecipeFingerprint -and
        $CurrentSourceFingerprint -eq $BaseSourceFingerprint -and
        $CurrentRecipeFingerprint -eq $BaseRecipeFingerprint) {
        return "reuse"
    }
    return "rebuild"
}

function New-RuntimePackagePlan {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentRef,
        [Parameter(Mandatory = $true)][string]$CurrentRelease,
        [Parameter(Mandatory = $true)][string]$BaseRelease,
        [Parameter(Mandatory = $true)]$BaseManifest,
        [Parameter(Mandatory = $true)]$BaseAssets
    )

    $definitions = @(Get-PackageDefinitionsAtRef -Ref $CurrentRef)
    $baseDefinitions = @{}
    if ($BaseRelease -eq $script:MigrationBaseRelease) {
        foreach ($definition in @(Get-PackageDefinitionsAtRef -Ref $BaseRelease)) {
            $baseDefinitions[$definition.component] = $definition
        }
    }

    $assetMap = @{}
    foreach ($asset in @($BaseAssets)) { $assetMap[[string]$asset.name] = $asset }

    $packages = foreach ($definition in $definitions) {
        $component = [string]$definition.component
        $basePackage = Get-ManifestPackage -Manifest $BaseManifest -Component $component
        $sourceFingerprint = Get-ComponentSourceFingerprint -Ref $CurrentRef -Definition $definition
        $recipeFingerprint = Get-RecipeFingerprint -Definition $definition
        $baseSourceFingerprint = $null
        $baseRecipeFingerprint = $null

        if ($basePackage) {
            if ($basePackage.sourceFingerprint) {
                $baseSourceFingerprint = [string]$basePackage.sourceFingerprint
                $baseRecipeFingerprint = [string]$basePackage.recipeFingerprint
            } elseif ($BaseRelease -eq $script:MigrationBaseRelease -and $baseDefinitions.ContainsKey($component)) {
                $baseSourceFingerprint = Get-ComponentSourceFingerprint -Ref $BaseRelease -Definition $baseDefinitions[$component]
                $baseRecipeFingerprint = Get-LegacyRecipeFingerprint -BaseRelease $BaseRelease -Definition $definition -CurrentRecipeFingerprint $recipeFingerprint
            }
        }

        $action = New-PackageDecision -CurrentSourceFingerprint $sourceFingerprint -CurrentRecipeFingerprint $recipeFingerprint -BaseSourceFingerprint $baseSourceFingerprint -BaseRecipeFingerprint $baseRecipeFingerprint
        $baseFile = if ($basePackage -and $basePackage.asset) { [string]$basePackage.asset } elseif ($basePackage) { [string]$basePackage.file } else { "" }
        $asset = if ($baseFile -and $assetMap.ContainsKey($baseFile)) { $assetMap[$baseFile] } else { $null }
        $baseSize = if ($basePackage -and $basePackage.size) { [int64]$basePackage.size } elseif ($asset) { [int64]$asset.size } else { 0 }
        $baseSha = if ($basePackage) { [string]$basePackage.sha256 } else { "" }
        $baseVersion = if ($basePackage -and $basePackage.version) { [string]$basePackage.version } else { "" }

        if ($action -eq "reuse" -and (-not $basePackage -or -not $baseSha -or $baseSize -le 0 -or -not $asset)) {
            throw "Cannot reuse $component because the $BaseRelease metadata or asset '$baseFile' is incomplete."
        }

        [pscustomobject][ordered]@{
            component = $component
            kind = [string]$definition.kind
            file = [string]$definition.file
            required = [bool]$definition.required
            extractTo = [string]$definition.extractTo
            sourceFingerprint = $sourceFingerprint
            recipeFingerprint = $recipeFingerprint
            packageFingerprint = Get-Sha256Text -Text ("package-v1`n$sourceFingerprint`n$recipeFingerprint")
            action = $action
            version = if ($action -eq "reuse") { $baseVersion } else { $CurrentRelease }
            baseSha256 = if ($action -eq "reuse") { $baseSha.ToUpperInvariant() } else { "" }
            baseSize = if ($action -eq "reuse") { $baseSize } else { 0 }
        }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        sourceFingerprintAlgorithm = "git-tree-sha256-v1"
        currentRef = $CurrentRef
        releaseVersion = $CurrentRelease
        baseRelease = $BaseRelease
        baseTtsVersion = [string]$BaseManifest.ttsVersion
        packages = @($packages)
    }
}
