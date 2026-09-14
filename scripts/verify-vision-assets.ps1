param(
    [string]$VisionRoot = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($VisionRoot)) {
    $VisionRoot = Join-Path $RepoRoot "runtime-models\vision"
} else {
    $VisionRoot = [System.IO.Path]::GetFullPath($VisionRoot)
}
$ManifestPath = Join-Path $VisionRoot "vision-assets.json"
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Vision asset manifest is missing: $ManifestPath"
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if ([int]$Manifest.schemaVersion -ne 1) { throw "Unsupported Vision asset manifest schema." }
if ([string]$Manifest.handoffManifestSha256 -ne "925DA813062A52BDF0C55AB2739F027EB32D2FD7D2478058742DD1D869685672") {
    throw "Vision handoff manifest identity mismatch."
}
$PythonRuntime = $Manifest.pythonRuntime
if ([string]$PythonRuntime.pythonVersion -ne "3.11" -or
    [string]$PythonRuntime.platform -ne "win_amd64" -or
    [string]$PythonRuntime.distribution -ne "opencv-python-headless" -or
    [string]$PythonRuntime.version -ne "4.11.0.86" -or
    [string]$PythonRuntime.wheel -ne "opencv_python_headless-4.11.0.86-cp37-abi3-win_amd64.whl" -or
    [string]$PythonRuntime.wheelSha256 -ne "6C304DF9CAA7A6A5710B91709DD4786BF20A74D57672B3C31F7033CC638174CA" -or
    [string]$PythonRuntime.importPath -ne "site-packages/cv2/__init__.py" -or
    [string]$PythonRuntime.distInfoPath -ne "site-packages/opencv_python_headless-4.11.0.86.dist-info") {
    throw "Vision OpenCV runtime contract mismatch."
}
if ([int]$Manifest.runtimeContract.processOwners -ne 1 -or [int]$Manifest.runtimeContract.vdeviceOwners -ne 1) {
    throw "Vision runtime must declare exactly one process owner and one VDevice owner."
}
if ([int]$Manifest.runtimeContract.queueCapacity -ne 1) { throw "Vision runtime queue capacity must be 1." }
if ([string]$Manifest.runtimeContract.personSchedule -ne "latest-frame-realtime") {
    throw "Person scheduling must retain latest-frame realtime semantics."
}
if ([double]$Manifest.runtimeContract.genderPeriodSeconds -lt 1.0) {
    throw "Gender scheduling must remain at approximately 1 Hz or slower."
}
if (-not [bool]$Manifest.runtimeContract.ageRequiresGenderFaceBbox) {
    throw "Age inference must require a Gender face bbox."
}
if ([double]$Manifest.runtimeContract.ageMaxFrequencyHz -gt 1.0) {
    throw "Age scheduling must remain at 1 Hz or slower."
}
if ([bool]$Manifest.runtimeContract.persistFrames -or [bool]$Manifest.runtimeContract.persistFaceCrops) {
    throw "Vision runtime assets must retain the no-media-persistence policy."
}
if ([bool]$Manifest.productionReady.age) { throw "Age must remain productionReady=false." }
if ([string]$Manifest.runtimeContract.combinedWithWhisperStt -ne "DEVICE_VERIFICATION_REQUIRED") {
    throw "Combined Vision and Whisper STT validation must remain pending."
}
if ([bool]$Manifest.productionReady.combinedWithWhisperStt) {
    throw "Combined Vision and Whisper STT must not be marked production ready."
}
if ([string]$Manifest.validationEvidence.threeVisionModels.status -ne "PASS" -or
    [string]$Manifest.validationEvidence.threeVisionModels.sha256 -ne "FBC9F6074C9460663553D08E1651D521DC1C24D0DF1CCE499982C8FA9DE53E9C" -or
    [int]$Manifest.validationEvidence.threeVisionModels.vdeviceOwners -ne 1 -or
    [int]$Manifest.validationEvidence.threeVisionModels.resourceErrors -ne 0) {
    throw "Vision three-model hardware validation evidence identity mismatch."
}
if ([string]$Manifest.validationEvidence.productionDraft -ne "WRITTEN_NOT_RUN_NOT_VERIFIED" -or
    [string]$Manifest.validationEvidence.combinedWithWhisperStt -ne "DEVICE_VERIFICATION_REQUIRED") {
    throw "Vision validation boundaries must remain explicit."
}

$Camera = $Manifest.cameraContract
if ([string]$Camera.backend -ne "DSHOW" -or [string]$Camera.fourcc -ne "MJPG" -or
    [int]$Camera.width -ne 1920 -or [int]$Camera.height -ne 1080 -or [int]$Camera.fps -ne 30 -or
    -not [bool]$Camera.openTimeParamsRequired) {
    throw "Vision camera contract must remain DSHOW/MJPG/1920x1080@30 with open-time parameters."
}

foreach ($Property in $Manifest.models.PSObject.Properties) {
    $Model = $Property.Value
    $Path = Join-Path $VisionRoot ([string]$Model.file)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$($Property.Name) Vision HEF is missing: $Path"
    }
    $Item = Get-Item -LiteralPath $Path
    if ($Item.Length -ne [int64]$Model.bytes) {
        throw "$($Property.Name) Vision HEF size mismatch."
    }
    $ActualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($ActualHash -ne [string]$Model.sha256) {
        throw "$($Property.Name) Vision HEF SHA256 mismatch."
    }
    if ($Model.metadata) {
        $MetadataPath = Join-Path $VisionRoot ([string]$Model.metadata)
        if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
            throw "$($Property.Name) Vision metadata is missing: $MetadataPath"
        }
    }
    Write-Host "$($Property.Name) Vision HEF: OK"
}
