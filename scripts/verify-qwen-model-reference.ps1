param(
    [string]$ReferencePath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($ReferencePath)) {
    $ReferencePath = Join-Path $RepoRoot "runtime-models\qwen3-asr.json"
}

if (-not (Test-Path -LiteralPath $ReferencePath -PathType Leaf)) {
    throw "Qwen model reference is missing: $ReferencePath"
}

$reference = Get-Content -LiteralPath $ReferencePath -Raw -Encoding utf8 | ConvertFrom-Json

if ([int]$reference.schemaVersion -ne 1) { throw "Unsupported Qwen model reference schema." }
if ([string]$reference.modelId -ne "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25") {
    throw "Unexpected Qwen model id."
}

$source = $reference.source
if ([string]$source.provider -ne "k2-fsa/sherpa-onnx") { throw "Unexpected Qwen model provider." }
if ([string]$source.url -notmatch '^https://github\.com/k2-fsa/sherpa-onnx/releases/download/') {
    throw "Qwen model URL must be pinned to the official sherpa-onnx GitHub release."
}
if ([string]$source.archiveName -ne "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2") {
    throw "Unexpected Qwen archive name."
}
if ([int64]$source.archiveSizeBytes -ne 878702423) { throw "Unexpected Qwen archive size." }
$sha = ([string]$source.archiveSha256).ToLowerInvariant()
if ($sha -ne "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96") {
    throw "Unexpected Qwen archive SHA256."
}

$runtime = $reference.runtime
if ([string]$runtime.pythonVersion -ne "3.11.9") { throw "Qwen Python must stay pinned to 3.11.9." }
if ([string]$runtime.sherpaOnnxVersion -ne "1.13.8") { throw "Qwen sherpa-onnx must stay pinned to 1.13.8." }
if ([string]$runtime.numpyVersion -ne "2.4.6") { throw "Qwen NumPy must stay pinned to 2.4.6." }
if ([int]$runtime.defaultThreads -ne 3) { throw "Qwen default thread count must stay at 3." }

$required = @($reference.install.requiredPaths)
foreach ($path in @("conv_frontend.onnx", "encoder.int8.onnx", "decoder.int8.onnx", "tokenizer")) {
    if ($path -notin $required) { throw "Qwen model reference is missing required path: $path" }
}

$distribution = $reference.distribution
if ([string]$distribution.mode -ne "external-immutable-download") {
    throw "Qwen model must use external immutable download mode."
}
if ([bool]$distribution.includeInEnvRelease) { throw "Qwen model must not be embedded in env-v* releases." }
if ([bool]$distribution.includeInGitLfs) { throw "Qwen model must not be stored in this Git/LFS repository." }
if ([bool]$distribution.redownloadWhenSha256Matches) {
    throw "Qwen model must be reusable when the installed SHA256 already matches."
}

Write-Host "Qwen model reference: PASS"
Write-Host "Model ID          :" $reference.modelId
Write-Host "Archive size      :" $source.archiveSizeBytes
Write-Host "Archive SHA256    :" $source.archiveSha256
Write-Host "Distribution mode :" $distribution.mode
