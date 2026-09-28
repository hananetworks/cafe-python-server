param(
    [string]$SourceDirectory = "qwen-env",
    [string]$OutputPath = "qwen-engine.zip"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$SourceDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $SourceDirectory))
$OutputPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputPath))

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Qwen runtime source is missing: $SourceDirectory"
}

$PythonExe = Join-Path $SourceDirectory "qwen_python.exe"
& (Join-Path $PSScriptRoot "verify-qwen-runtime.ps1") -PythonExe $PythonExe

Invoke-DeterministicZip -SourceRoot $SourceDirectory -OutputPath $OutputPath -CompressionLevel 9

$archive = Get-Item -LiteralPath $OutputPath
if ($archive.Length -lt 1MB) {
    throw "qwen-engine.zip is unexpectedly small: $($archive.Length) bytes."
}

$entries = & 7z l -slt $OutputPath
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect qwen-engine.zip." }
foreach ($requiredEntry in @("Path = qwen_python.exe", "Path = python311._pth")) {
    if ($entries -notcontains $requiredEntry) {
        throw "qwen-engine.zip is missing required root entry: $requiredEntry"
    }
}

Write-Host "Qwen engine package: PASS"
Write-Host "Archive:" $OutputPath
Write-Host "Size   :" $archive.Length
