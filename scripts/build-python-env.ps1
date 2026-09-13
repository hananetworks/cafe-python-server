param(
    [string]$ReuseEngineZip = "",
    [string]$ReuseSttAssetZip = "",
    [string]$ReuseTtsCoreAssetZip = ""
)

$ErrorActionPreference = "Stop"

$EnvName = "python-env"
if (Test-Path $EnvName) { Remove-Item $EnvName -Recurse -Force }
New-Item -ItemType Directory -Path $EnvName -Force | Out-Null

if (-not [string]::IsNullOrWhiteSpace($ReuseEngineZip) -and (Test-Path $ReuseEngineZip)) {
    Write-Host "Reusing cached python engine package..."
    7z x $ReuseEngineZip "-o$EnvName" -y | Out-Null
    $PythonExe = "$EnvName\kiosk_python.exe"
} else {
    $PythonZipUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
    Invoke-WebRequest -Uri $PythonZipUrl -OutFile "python.zip"
    Expand-Archive -Path "python.zip" -DestinationPath $EnvName -Force
    Remove-Item "python.zip" -Force

    Rename-Item -Path "$EnvName\python.exe" -NewName "kiosk_python.exe"
    $PythonExe = "$EnvName\kiosk_python.exe"

    $PthFile = "$EnvName\python311._pth"
    (Get-Content $PthFile) -replace '#import site', 'import site' | Set-Content $PthFile

    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile "get-pip.py"
    & $PythonExe get-pip.py --no-warn-script-location
    Remove-Item "get-pip.py" -Force

    Write-Host "Installing libraries from requirements.txt..."
    & $PythonExe -m pip install -r requirements.txt --no-warn-script-location --extra-index-url https://download.pytorch.org/whl/cpu
    if ($LASTEXITCODE -ne 0) { throw "Requirements install failed" }

    Write-Host "Installing HailoRT local wheel..."
    $HailoWheel = Get-ChildItem -Path "libs" -Filter "hailort-*.whl" | Select-Object -First 1
    if ($HailoWheel) {
        Write-Host "Found wheel: $($HailoWheel.Name)"
        & $PythonExe -m pip install $HailoWheel.FullName --no-warn-script-location
    } else {
        Write-Error "FATAL: HailoRT .whl file not found in 'libs/' directory."
        exit 1
    }

    if ($LASTEXITCODE -ne 0) { throw "HailoRT wheel install failed" }

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
            Write-Host "  -> Repaired missing 'unidic\\dicdir' from 'unidic_lite'."
        }
    }
}

$CanReuseSttAssets = -not [string]::IsNullOrWhiteSpace($ReuseSttAssetZip) -and (Test-Path $ReuseSttAssetZip)
$CanReuseTtsCoreAssets = -not [string]::IsNullOrWhiteSpace($ReuseTtsCoreAssetZip) -and (Test-Path $ReuseTtsCoreAssetZip)
$ShouldPrepareSpeechAssets = (-not $CanReuseSttAssets) -or (-not $CanReuseTtsCoreAssets)

if ($CanReuseSttAssets -or $CanReuseTtsCoreAssets) {
    Write-Host "Reusing cached speech assets where available..."
}

if ($ShouldPrepareSpeechAssets) {
    Write-Host "Building missing speech assets from source..."
    $prepareArgs = @{
        PythonExe = $PythonExe
        EnvName = $EnvName
    }
    if ($CanReuseTtsCoreAssets) { $prepareArgs.SkipTtsSetup = $true }
    if ($CanReuseSttAssets) { $prepareArgs.SkipSttSetup = $true }
    .\scripts\prepare-speech-assets.ps1 @prepareArgs
}

Get-ChildItem -Path $EnvName -Include "__pycache__" -Recurse -Directory | Remove-Item -Recurse -Force
