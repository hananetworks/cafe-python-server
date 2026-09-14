$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $repoRoot "scripts\runtime-package-common.ps1")
. (Join-Path $repoRoot "scripts\runtime-package-plan.ps1")

$passed = 0
function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:passed++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw $Message }
    $script:passed++
}

function Get-Actions {
    param([hashtable]$Base, [hashtable]$Current)
    $result = @{}
    foreach ($component in $Current.Keys) {
        $result[$component] = New-PackageDecision `
            -CurrentSourceFingerprint $Current[$component] `
            -CurrentRecipeFingerprint "recipe-$component" `
            -BaseSourceFingerprint $Base[$component] `
            -BaseRecipeFingerprint "recipe-$component"
    }
    return $result
}

$testRoot = Join-Path $repoRoot (".runtime-test\{0}" -f [Guid]::NewGuid().ToString("N"))
$hadGitHubRefName = Test-Path Env:GITHUB_REF_NAME
$originalGitHubRefName = $env:GITHUB_REF_NAME
$env:GITHUB_REF_NAME = $null
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $visionDefinition = @(Get-PackageDefinitionsAtRef -Ref "HEAD") | Where-Object component -eq "vision" | Select-Object -First 1
    Assert-Equal "vision-assets.zip" $visionDefinition.file "Vision must use an independent archive"
    Assert-Equal "python/vision" $visionDefinition.extractTo "Vision must install into its own runtime root"
    Assert-Equal $false $visionDefinition.required "Vision assets remain optional for older kiosk deployments"
    $visionContract = Get-Content -LiteralPath (Join-Path $repoRoot "runtime-models\vision\vision-assets.json") -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-Equal "3.11" $visionContract.pythonRuntime.pythonVersion "Vision OpenCV must target CPython 3.11"
    Assert-Equal "win_amd64" $visionContract.pythonRuntime.platform "Vision OpenCV must target 64-bit Windows"
    Assert-Equal "opencv-python-headless" $visionContract.pythonRuntime.distribution "Vision must use headless OpenCV"
    Assert-Equal "4.11.0.86" $visionContract.pythonRuntime.version "Vision OpenCV must be pinned"
    Assert-Equal "site-packages/cv2/__init__.py" $visionContract.pythonRuntime.importPath "Vision OpenCV must use the kiosk activation path"
    Assert-Equal 64 ([string]$visionContract.pythonRuntime.wheelSha256).Length "Vision OpenCV wheel must have a pinned SHA256"

    # A wheel-only Hailo source change must not select STT or any TTS package.
    $base = @{ engine = "engine-a"; stt = "stt-a"; hailo = "hailo-a"; vision = "vision-a"; ttsCore = "core-a"; ttsKo = "ko-a"; ttsEn = "en-a" }
    $current = $base.Clone(); $current.hailo = "hailo-b"
    $actions = Get-Actions -Base $base -Current $current
    Assert-Equal "rebuild" $actions.hailo "Hailo should rebuild"
    Assert-Equal "reuse" $actions.engine "Engine should reuse after Hailo separation"
    Assert-Equal "reuse" $actions.stt "STT should reuse after a Hailo change"
    Assert-Equal "reuse" $actions.vision "Vision should reuse after a Hailo change"
    Assert-Equal "reuse" $actions.ttsCore "TTS core should reuse after a Hailo change"
    Assert-Equal "reuse" $actions.ttsKo "Korean TTS should reuse after a Hailo change"

    # Real repository refs: env-v1.4.35 -> HEAD changed the HailoRT wheel, while
    # the new engine boundary deliberately excludes that wheel.
    $headDefinitions = @{}; foreach ($definition in @(Get-PackageDefinitionsAtRef -Ref "HEAD")) { $headDefinitions[$definition.component] = $definition }
    $oldDefinitions = @{}; foreach ($definition in @(Get-PackageDefinitionsAtRef -Ref "env-v1.4.35")) { $oldDefinitions[$definition.component] = $definition }
    Assert-Equal (Get-ComponentSourceFingerprint -Ref "env-v1.4.35" -Definition $oldDefinitions.engine) (Get-ComponentSourceFingerprint -Ref "HEAD" -Definition $headDefinitions.engine) "Hailo wheel changes must not change the engine source fingerprint"
    Assert-Equal $false ((Get-ComponentSourceFingerprint -Ref "env-v1.4.35" -Definition $oldDefinitions.hailo) -eq (Get-ComponentSourceFingerprint -Ref "HEAD" -Definition $headDefinitions.hailo)) "Hailo wheel changes must change the Hailo source fingerprint"
    Assert-Equal (Get-ComponentSourceFingerprint -Ref "env-v1.4.35" -Definition $oldDefinitions.stt) (Get-ComponentSourceFingerprint -Ref "HEAD" -Definition $headDefinitions.stt) "Hailo wheel changes must not change STT source"
    Assert-Equal (Get-ComponentSourceFingerprint -Ref "env-v1.4.35" -Definition $oldDefinitions.ttsCore) (Get-ComponentSourceFingerprint -Ref "HEAD" -Definition $headDefinitions.ttsCore) "Hailo wheel changes must not change TTS core source"

    # An STT source change selects only STT.
    $current = $base.Clone(); $current.stt = "stt-b"
    $actions = Get-Actions -Base $base -Current $current
    Assert-Equal "rebuild" $actions.stt "STT should rebuild"
    Assert-Equal "reuse" $actions.engine "Engine should reuse after an STT change"
    Assert-Equal "reuse" $actions.hailo "Hailo should reuse after an STT change"
    Assert-Equal "reuse" $actions.ttsCore "TTS core should reuse after an STT change"

    # One language model change selects only that archive.
    $current = $base.Clone(); $current.ttsKo = "ko-b"
    $actions = Get-Actions -Base $base -Current $current
    Assert-Equal "rebuild" $actions.ttsKo "Korean TTS should rebuild"
    Assert-Equal "reuse" $actions.ttsEn "English TTS should reuse"
    Assert-Equal "reuse" $actions.ttsCore "TTS core should reuse after a language-only change"
    Assert-Equal "reuse" $actions.stt "STT should reuse after a language-only change"

    # A Vision model or contract change selects only the Vision archive.
    $current = $base.Clone(); $current.vision = "vision-b"
    $actions = Get-Actions -Base $base -Current $current
    Assert-Equal "rebuild" $actions.vision "Vision should rebuild"
    Assert-Equal "reuse" $actions.engine "Engine should reuse after a Vision change"
    Assert-Equal "reuse" $actions.stt "STT should reuse after a Vision change"
    Assert-Equal "reuse" $actions.hailo "Hailo addon should reuse after a Vision change"
    Assert-Equal "reuse" $actions.ttsCore "TTS core should reuse after a Vision change"

    $ttsConfig = Get-Content -LiteralPath (Join-Path $repoRoot "runtime-models\speech-assets.json") -Raw -Encoding utf8 | ConvertFrom-Json
    $changedConfig = ($ttsConfig | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    ($changedConfig.tts.huggingFaceRepos | Where-Object zipFile -eq "tts-hf-melo-ko.zip").repo_id = "example/changed-ko"
    $koBefore = Get-TtsRepoConfigRecord -Config $ttsConfig -ZipFile "tts-hf-melo-ko.zip"
    $koAfter = Get-TtsRepoConfigRecord -Config $changedConfig -ZipFile "tts-hf-melo-ko.zip"
    $enBefore = Get-TtsRepoConfigRecord -Config $ttsConfig -ZipFile "tts-hf-melo-en.zip"
    $enAfter = Get-TtsRepoConfigRecord -Config $changedConfig -ZipFile "tts-hf-melo-en.zip"
    Assert-Equal $false ($koBefore -eq $koAfter) "Changed language config should change only its source record"
    Assert-Equal $enBefore $enAfter "Unchanged language config should retain its source record"

    # The deterministic packager produces the same bytes for unchanged content.
    $source = Join-Path $testRoot "source"
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $source "b.txt"), "bravo")
    [System.IO.File]::WriteAllText((Join-Path $source "a.txt"), "alpha")
    $zip1 = Join-Path $testRoot "first.zip"
    $zip2 = Join-Path $testRoot "second.zip"
    Invoke-DeterministicZip -SourceRoot $source -OutputPath $zip1 -CompressionLevel 1
    (Get-Item (Join-Path $source "a.txt")).LastWriteTime = (Get-Date).AddDays(1)
    Invoke-DeterministicZip -SourceRoot $source -OutputPath $zip2 -CompressionLevel 1
    Assert-Equal (Get-RequiredFileHash $zip1) (Get-RequiredFileHash $zip2) "Archive hash should ignore source timestamps"

    $hub = Join-Path $testRoot "hub"
    New-Item -ItemType Directory -Path (Join-Path $hub "models--selected"), (Join-Path $hub "models--other") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $hub "models--selected\model.bin"), "selected")
    [System.IO.File]::WriteAllText((Join-Path $hub "models--other\model.bin"), "other")
    $selectedZip = Join-Path $testRoot "selected.zip"
    Invoke-DeterministicZip -SourceRoot $hub -OutputPath $selectedZip -CompressionLevel 1 -IncludePatterns @('^models--selected(?:/|$)')
    $selectedEntries = & 7z l -slt $selectedZip
    Assert-Equal $true ($selectedEntries -contains 'Path = models--selected\model.bin') "HF archive should retain its cache directory root"
    Assert-Equal $false ($selectedEntries -contains 'Path = models--other\model.bin') "HF archive should exclude unrelated languages"

    # A cache miss still copies the exact previous release asset.
    $baseAssets = Join-Path $testRoot "base-assets"
    $reuseOutput = Join-Path $testRoot "reuse-output"
    New-Item -ItemType Directory -Path $baseAssets, $reuseOutput -Force | Out-Null
    $baseZip = Join-Path $baseAssets "stt-assets.zip"
    Copy-Item -LiteralPath $zip1 -Destination $baseZip
    $baseHash = Get-RequiredFileHash $baseZip
    $baseSize = (Get-Item $baseZip).Length
    $plan = [ordered]@{
        schemaVersion = 1; sourceFingerprintAlgorithm = "git-tree-sha256-v1"; releaseVersion = "env-vNext"; baseRelease = "env-v1.4.36"; baseTtsVersion = "env-v1.4.36"; packages = @(
            [ordered]@{ component = "stt"; file = "stt-assets.zip"; required = $true; extractTo = "python/stt"; sourceFingerprint = "source"; recipeFingerprint = "recipe"; packageFingerprint = "package"; action = "reuse"; version = "env-v1.4.36"; baseSha256 = $baseHash; baseSize = $baseSize }
        )
    }
    $planPath = Join-Path $testRoot "reuse-plan.json"
    Write-Utf8NoBom -Path $planPath -Content ($plan | ConvertTo-Json -Depth 8)
    & (Join-Path $repoRoot "scripts\reuse-runtime-assets.ps1") -PlanPath $planPath -BaseAssetDirectory $baseAssets -DestinationDirectory $reuseOutput
    Assert-Equal $baseHash (Get-RequiredFileHash (Join-Path $reuseOutput "stt-assets.zip")) "Reused archive SHA256 should stay identical"

    # Missing or corrupt previous assets abort reuse.
    $badPlan = $plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $badPlan.packages[0].baseSha256 = "0" * 64
    $badPlanPath = Join-Path $testRoot "bad-plan.json"
    Write-Utf8NoBom -Path $badPlanPath -Content ($badPlan | ConvertTo-Json -Depth 8)
    Assert-Throws { & (Join-Path $repoRoot "scripts\reuse-runtime-assets.ps1") -PlanPath $badPlanPath -BaseAssetDirectory $baseAssets -DestinationDirectory (Join-Path $testRoot "bad-output") } "Hash mismatch should abort reuse"
    Assert-Throws { & (Join-Path $repoRoot "scripts\reuse-runtime-assets.ps1") -PlanPath $planPath -BaseAssetDirectory (Join-Path $testRoot "missing-assets") -DestinationDirectory (Join-Path $testRoot "missing-output") } "Missing previous asset should abort reuse"

    # Generated manifest metadata must match every archive exactly.
    $manifestOutput = Join-Path $testRoot "manifest-output"
    New-Item -ItemType Directory -Path $manifestOutput -Force | Out-Null
    Copy-Item -LiteralPath $baseZip -Destination (Join-Path $manifestOutput "stt-assets.zip")
    $manifestPlanPath = Join-Path $testRoot "manifest-plan.json"
    Write-Utf8NoBom -Path $manifestPlanPath -Content ($plan | ConvertTo-Json -Depth 8)
    & (Join-Path $repoRoot "scripts\generate-runtime-artifacts.ps1") -PlanPath $manifestPlanPath -OutputDirectory $manifestOutput
    & (Join-Path $repoRoot "scripts\verify-runtime-artifacts.ps1") -ManifestPath (Join-Path $manifestOutput "runtime-manifest.json") -AssetDirectory $manifestOutput -PlanPath $manifestPlanPath
    $manifest = Get-Content (Join-Path $manifestOutput "runtime-manifest.json") -Raw | ConvertFrom-Json
    Assert-Equal $baseHash $manifest.packages.stt.sha256 "Manifest SHA256 should match the archive"
    Assert-Equal $baseSize $manifest.packages.stt.size "Manifest size should match the archive"

    # A rebuilt Vision archive gets its own top-level/component version and hash.
    $visionPlan = $plan | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $visionPlan.packages += [pscustomobject][ordered]@{
        component = "vision"; file = "vision-assets.zip"; required = $false; extractTo = "python/vision"
        sourceFingerprint = "vision-source"; recipeFingerprint = "vision-recipe"; packageFingerprint = "vision-package"
        action = "rebuild"; version = "env-vNext"; baseSha256 = ""; baseSize = 0
    }
    Copy-Item -LiteralPath $baseZip -Destination (Join-Path $manifestOutput "vision-assets.zip")
    Write-Utf8NoBom -Path $manifestPlanPath -Content ($visionPlan | ConvertTo-Json -Depth 8)
    & (Join-Path $repoRoot "scripts\generate-runtime-artifacts.ps1") -PlanPath $manifestPlanPath -OutputDirectory $manifestOutput
    & (Join-Path $repoRoot "scripts\verify-runtime-artifacts.ps1") -ManifestPath (Join-Path $manifestOutput "runtime-manifest.json") -AssetDirectory $manifestOutput -PlanPath $manifestPlanPath
    $visionManifest = Get-Content (Join-Path $manifestOutput "runtime-manifest.json") -Raw | ConvertFrom-Json
    Assert-Equal "env-vNext" $visionManifest.visionVersion "Manifest must expose the Vision component version"
    Assert-Equal $baseHash $visionManifest.packages.vision.sha256 "Vision manifest SHA256 should match its archive"

    # Every PowerShell entry point must parse before CI starts a release build.
    foreach ($scriptFile in Get-ChildItem -LiteralPath (Join-Path $repoRoot "scripts") -Filter "*.ps1") {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Equal 0 $errors.Count "$($scriptFile.Name) should parse"
    }

    Write-Host "PASS: $passed runtime packaging assertions."
} finally {
    if ($hadGitHubRefName) {
        $env:GITHUB_REF_NAME = $originalGitHubRefName
    } else {
        Remove-Item Env:GITHUB_REF_NAME -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
