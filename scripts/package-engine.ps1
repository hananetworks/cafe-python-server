$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

Invoke-DeterministicZip -SourceRoot "python-env" -OutputPath "python-engine.zip" -CompressionLevel 9 -ExcludePatterns @(
    '^models(?:/|$)',
    '^tts_models(?:/|$)'
)

$archive = Get-Item -LiteralPath "python-engine.zip"
if ($archive.Length -lt 1MB) {
    throw "python-engine.zip is unexpectedly small: $($archive.Length) bytes."
}
$entries = & 7z l -slt "python-engine.zip"
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect python-engine.zip." }
foreach ($requiredEntry in @("Path = kiosk_python.exe", "Path = python311._pth")) {
    if ($entries -notcontains $requiredEntry) {
        throw "python-engine.zip is missing required root entry: $requiredEntry"
    }
}
Write-Host "Engine package verified."
