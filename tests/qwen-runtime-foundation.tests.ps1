$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

$passed = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:passed++
}
function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:passed++
}

$requirements = Get-Content -LiteralPath (Join-Path $RepoRoot "qwen-runtime-requirements.txt")
Assert-True ($requirements -contains "sherpa-onnx==1.13.8") "sherpa-onnx must be pinned to the validated version"
Assert-True ($requirements -contains "numpy==2.4.6") "NumPy must be pinned to the validated Qwen version"
Assert-True (-not ($requirements -match "openai-whisper")) "Qwen engine must not include CPU Whisper"

$referencePath = Join-Path $RepoRoot "runtime-models\qwen3-asr.json"
$reference = Get-Content -LiteralPath $referencePath -Raw -Encoding utf8 | ConvertFrom-Json
Assert-Equal "external-immutable-download" ([string]$reference.distribution.mode) "Qwen model distribution mode"
Assert-Equal $false ([bool]$reference.distribution.includeInEnvRelease) "Qwen model must not be embedded in env releases"
Assert-Equal $false ([bool]$reference.distribution.includeInGitLfs) "Qwen model must not be stored in Git LFS"
Assert-Equal 878702423 ([int64]$reference.source.archiveSizeBytes) "Qwen archive size"
Assert-Equal 64 ([string]$reference.source.archiveSha256).Length "Qwen archive SHA256 length"

& (Join-Path $RepoRoot "scripts\verify-qwen-model-reference.ps1") -ReferencePath $referencePath

foreach ($scriptName in @(
    "build-qwen-env.ps1",
    "verify-qwen-runtime.ps1",
    "package-qwen-engine.ps1",
    "verify-qwen-model-reference.ps1"
)) {
    $scriptFile = Join-Path $RepoRoot "scripts\$scriptName"
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    Assert-Equal 0 $errors.Count "$scriptName should parse"
}

Write-Host "PASS: $passed Qwen runtime foundation assertions."
