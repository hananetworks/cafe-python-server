param(
    [string]$ArchivePath = "vision-assets.zip",
    [string]$ExpectedVersion = "",
    [string]$PythonExe = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Vision archive is missing: $ArchivePath"
}

& 7z t $ArchivePath | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Vision archive integrity test failed." }

$TestRoot = Join-Path $RepoRoot (".runtime-test\vision-package-{0}" -f [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
try {
    & 7z x $ArchivePath "-o$TestRoot" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract the Vision archive." }

    & (Join-Path $PSScriptRoot "verify-vision-assets.ps1") -VisionRoot $TestRoot
    $Manifest = Get-Content -LiteralPath (Join-Path $TestRoot "vision-assets.json") -Raw -Encoding utf8 | ConvertFrom-Json
    $Runtime = $Manifest.pythonRuntime

    $VersionPath = Join-Path $TestRoot "version.txt"
    if (-not (Test-Path -LiteralPath $VersionPath -PathType Leaf)) { throw "Vision archive is missing version.txt." }
    $ActualVersion = (Get-Content -LiteralPath $VersionPath -Raw -Encoding utf8).Trim()
    if ([string]::IsNullOrWhiteSpace($ActualVersion)) { throw "Vision archive version.txt is empty." }
    if ($ExpectedVersion -and $ActualVersion -ne $ExpectedVersion) {
        throw "Vision archive version mismatch: expected $ExpectedVersion, got $ActualVersion."
    }

    $ImportPath = Join-Path $TestRoot ([string]$Runtime.importPath)
    if (-not (Test-Path -LiteralPath $ImportPath -PathType Leaf)) {
        throw "Vision archive is missing the OpenCV import package: $($Runtime.importPath)"
    }
    $DistInfoPath = Join-Path $TestRoot ([string]$Runtime.distInfoPath)
    $RecordPath = Join-Path $DistInfoPath "RECORD"
    if (-not (Test-Path -LiteralPath $RecordPath -PathType Leaf)) {
        throw "Vision archive is missing the OpenCV wheel RECORD metadata."
    }

    $SitePackages = Join-Path $TestRoot "site-packages"
    $Records = @(Import-Csv -LiteralPath $RecordPath -Header "Path", "Hash", "Size")
    if ($Records.Count -lt 20) { throw "OpenCV wheel RECORD is unexpectedly small." }
    foreach ($Record in $Records) {
        $RelativePath = [string]$Record.Path
        if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
            throw "OpenCV wheel RECORD contains an unsafe path: $RelativePath"
        }
        $InstalledPath = Join-Path $SitePackages $RelativePath
        if (-not (Test-Path -LiteralPath $InstalledPath -PathType Leaf)) {
            throw "OpenCV wheel installation is incomplete: $RelativePath"
        }
        if ($Record.Size -match '^\d+$' -and (Get-Item -LiteralPath $InstalledPath).Length -ne [int64]$Record.Size) {
            throw "OpenCV wheel file size mismatch: $RelativePath"
        }
    }

    if ([string]::IsNullOrWhiteSpace($PythonExe)) {
        $PythonExe = (Get-Command python -ErrorAction Stop).Source
    }
    $PythonVersion = (& $PythonExe --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $PythonVersion -notmatch '^Python 3\.11(?:\.|$)') {
        throw "Vision runtime verification requires CPython 3.11, got '$PythonVersion'."
    }

    $PreviousSitePackages = $env:CAFE_VISION_SITE_PACKAGES
    $env:CAFE_VISION_SITE_PACKAGES = $SitePackages
    try {
        $Probe = @'
import os
import pathlib
import sys

site_packages = pathlib.Path(os.environ["CAFE_VISION_SITE_PACKAGES"]).resolve()
sys.path.insert(0, str(site_packages))
import cv2

module_path = pathlib.Path(cv2.__file__).resolve()
if site_packages not in module_path.parents:
    raise RuntimeError(f"OpenCV loaded outside Vision package: {module_path}")
if cv2.__version__ != "4.11.0":
    raise RuntimeError(f"Unexpected OpenCV version: {cv2.__version__}")
if not callable(cv2.VideoCapture):
    raise RuntimeError("cv2.VideoCapture is unavailable")
print(f"OpenCV {cv2.__version__}: {module_path}")
print("cv2.VideoCapture: OK")
'@
        $ProbePath = Join-Path $TestRoot "verify_cv2_runtime.py"
        Write-Utf8NoBom -Path $ProbePath -Content $Probe
        $ProbeOutput = & $PythonExe $ProbePath 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Packaged OpenCV import probe failed:`n$($ProbeOutput -join "`n")" }
        $ProbeOutput | Write-Host
    } finally {
        $env:CAFE_VISION_SITE_PACKAGES = $PreviousSitePackages
    }

    Write-Host "Vision package version, HEFs, full OpenCV wheel installation, import, and VideoCapture: OK"
} finally {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
