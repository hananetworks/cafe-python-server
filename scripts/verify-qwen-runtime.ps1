param(
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $PythonExe = Join-Path $RepoRoot "qwen-env\qwen_python.exe"
}
$PythonExe = [System.IO.Path]::GetFullPath($PythonExe)

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Qwen Python executable is missing: $PythonExe"
}

$Probe = @'
import importlib.metadata as m
import numpy
import sherpa_onnx

expected_sherpa = "1.13.8"
expected_numpy = "2.4.6"

actual_sherpa = m.version("sherpa-onnx")
actual_numpy = numpy.__version__

if actual_sherpa != expected_sherpa:
    raise SystemExit(f"SHERPA_VERSION_MISMATCH:{actual_sherpa}")
if actual_numpy != expected_numpy:
    raise SystemExit(f"NUMPY_VERSION_MISMATCH:{actual_numpy}")
if not hasattr(sherpa_onnx.OfflineRecognizer, "from_qwen3_asr"):
    raise SystemExit("QWEN3_API_MISSING")

print("python      :", __import__("sys").version.split()[0])
print("sherpa-onnx:", actual_sherpa)
print("numpy       :", actual_numpy)
print("qwen3_api   : True")
'@

$Probe | & $PythonExe -
if ($LASTEXITCODE -ne 0) {
    throw "Qwen runtime Python probe failed."
}

Write-Host "Qwen runtime verification: PASS"
