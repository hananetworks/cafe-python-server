param(
    [string]$OutputDirectory = "qwen-env",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$OutputDirectory = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDirectory))
$WorkRoot = Join-Path $RepoRoot ".runtime-work\qwen-engine"
$DownloadRoot = Join-Path $WorkRoot "downloads"
$Requirements = Join-Path $RepoRoot "qwen-runtime-requirements.txt"

if (-not (Test-Path -LiteralPath $Requirements -PathType Leaf)) {
    throw "Qwen runtime requirements are missing: $Requirements"
}

if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not $Force) {
        throw "Qwen runtime already exists: $OutputDirectory. Re-run with -Force to rebuild it."
    }
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputDirectory, $DownloadRoot -Force | Out-Null

$PythonZip = Join-Path $DownloadRoot "python-3.11.9-embed-amd64.zip"
$PythonZipUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"

if (-not (Test-Path -LiteralPath $PythonZip -PathType Leaf)) {
    Write-Host "Downloading embedded Python 3.11.9..."
    Invoke-WebRequest -Uri $PythonZipUrl -OutFile $PythonZip
} else {
    Write-Host "Reusing cached embedded Python archive."
}

Expand-Archive -LiteralPath $PythonZip -DestinationPath $OutputDirectory -Force
Rename-Item -LiteralPath (Join-Path $OutputDirectory "python.exe") -NewName "qwen_python.exe"

$PythonExe = Join-Path $OutputDirectory "qwen_python.exe"
$PthFile = Join-Path $OutputDirectory "python311._pth"
$Pth = @((Get-Content -LiteralPath $PthFile) -replace '#import site', 'import site')
$Pth | Set-Content -LiteralPath $PthFile -Encoding ascii

$GetPip = Join-Path $WorkRoot "get-pip.py"
if (-not (Test-Path -LiteralPath $GetPip -PathType Leaf)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $GetPip
}

$env:TEMP = Join-Path $WorkRoot "temp"
$env:TMP = $env:TEMP
$env:TMPDIR = $env:TEMP
New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($env:PIP_CACHE_DIR)) {
    $env:PIP_CACHE_DIR = Join-Path $RepoRoot ".runtime-work\pip-cache-qwen"
}

& $PythonExe $GetPip --no-warn-script-location
if ($LASTEXITCODE -ne 0) { throw "Qwen get-pip failed." }

& $PythonExe -m pip install -r $Requirements --no-warn-script-location
if ($LASTEXITCODE -ne 0) { throw "Qwen runtime requirements install failed." }

Get-ChildItem -LiteralPath $OutputDirectory -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

& (Join-Path $PSScriptRoot "verify-qwen-runtime.ps1") -PythonExe $PythonExe
if ($LASTEXITCODE -ne 0) { throw "Qwen runtime verification failed." }

Write-Host "Qwen runtime build: PASS"
Write-Host "Runtime path:" $OutputDirectory
