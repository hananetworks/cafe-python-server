$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$Assets = @(
    @{
        Name = "CPU Whisper checkpoint"
        Path = Join-Path $RepoRoot "runtime-models\stt\small.pt"
        Sha256 = "9ECF779972D90BA49C06D968637D720DD632C55BBF19D441FB42BF17A411E794"
    },
    @{
        Name = "Hailo Whisper HEF"
        Path = Join-Path $RepoRoot "runtime-models\hailo\models\Whisper-Small.hef"
        Sha256 = "48161D62F788329A200EB6A94F6A241623F49267F20D749F5C3495949A8B4470"
    }
)

foreach ($Asset in $Assets) {
    if (-not (Test-Path -LiteralPath $Asset.Path -PathType Leaf)) {
        throw "$($Asset.Name) is missing: $($Asset.Path)"
    }
    $Actual = (Get-FileHash -LiteralPath $Asset.Path -Algorithm SHA256).Hash
    if ($Actual -ne $Asset.Sha256) {
        throw "$($Asset.Name) SHA256 mismatch."
    }
    Write-Host "$($Asset.Name): OK"
}

$HailoWheels = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "libs") -File -Filter "hailort-*.whl")
if ($HailoWheels.Count -ne 1) {
    throw "Exactly one HailoRT wheel is required in libs/."
}
if ($HailoWheels[0].Name -notmatch '^hailort-5\.3\.0-') {
    Write-Warning (
        "The delivered device evidence is HailoRT/SDK/Firmware 5.3.0, but the repository wheel is " +
        "$($HailoWheels[0].Name). Hailo primary requires target-device compatibility verification."
    )
}
