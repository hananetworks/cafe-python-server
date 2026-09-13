$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$BuildTemp = Join-Path $RepoRoot ".runtime-work\build-temp"
if (Test-Path -LiteralPath $BuildTemp) { Remove-Item -LiteralPath $BuildTemp -Recurse -Force }
New-Item -ItemType Directory -Path $BuildTemp -Force | Out-Null
$env:TEMP = $BuildTemp
$env:TMP = $BuildTemp
$env:TMPDIR = $BuildTemp
if ([string]::IsNullOrWhiteSpace($env:PIP_CACHE_DIR)) {
    $env:PIP_CACHE_DIR = Join-Path $RepoRoot ".runtime-work\pip-cache"
}

$EnvName = "python-env"
if (Test-Path $EnvName) { Remove-Item $EnvName -Recurse -Force }
New-Item -ItemType Directory -Path $EnvName -Force | Out-Null

$PythonZipUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
Invoke-WebRequest -Uri $PythonZipUrl -OutFile "python.zip"
Expand-Archive -Path "python.zip" -DestinationPath $EnvName -Force
Remove-Item "python.zip" -Force

Rename-Item -Path "$EnvName\python.exe" -NewName "kiosk_python.exe"
$PythonExe = "$EnvName\kiosk_python.exe"

$PthFile = "$EnvName\python311._pth"
$PthLines = @((Get-Content $PthFile) -replace '#import site', 'import site')
if ($PthLines -notcontains '..\hailo\site-packages') {
    $PthLines += '..\hailo\site-packages'
}
$PthLines | Set-Content $PthFile

Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
& $PythonExe get-pip.py --no-warn-script-location
Remove-Item "get-pip.py" -Force

Write-Host "Installing libraries from requirements.txt..."
& $PythonExe -m pip install -r requirements.txt --no-warn-script-location --extra-index-url https://download.pytorch.org/whl/cpu
if ($LASTEXITCODE -ne 0) { throw "Requirements install failed" }

$PyWin32Dir = "$EnvName\Lib\site-packages\pywin32_system32"
if (Test-Path $PyWin32Dir) {
    Get-ChildItem -Path $PyWin32Dir -Filter "*.dll" | Copy-Item -Destination $EnvName -Force
}

Write-Host "Fixing MeCab dictionary path..."
$SitePackages = "$EnvName\Lib\site-packages"
$UnidicLite = "$SitePackages\unidic_lite"
$Unidic = "$SitePackages\unidic"
$UnidicLiteDicDir = "$UnidicLite\dicdir"
$UnidicDicDir = "$Unidic\dicdir"
$UnidicMecabRc = "$UnidicDicDir\mecabrc"
if (Test-Path $UnidicLite) {
    if (-not (Test-Path $Unidic)) {
        Copy-Item -Path $UnidicLite -Destination $Unidic -Recurse -Force
        Write-Host "  -> Copied 'unidic_lite' to 'unidic' successfully."
    } elseif ((Test-Path $UnidicLiteDicDir) -and (-not (Test-Path $UnidicMecabRc))) {
        Copy-Item -Path $UnidicLiteDicDir -Destination $UnidicDicDir -Recurse -Force
        Write-Host "  -> Repaired missing 'unidic\dicdir' from 'unidic_lite'."
    }
}

Get-ChildItem -Path $EnvName -Include "__pycache__" -Recurse -Directory | Remove-Item -Recurse -Force
