param(
    [string]$PlanPath = "runtime-package-plan.json",
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string[]]$Components = @(),
    [string]$BaseAssetDirectory = "",
    [string]$DestinationDirectory = "."
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "runtime-package-common.ps1")

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding utf8 | ConvertFrom-Json
$destination = [System.IO.Path]::GetFullPath($DestinationDirectory)
New-Item -ItemType Directory -Path $destination -Force | Out-Null

$packages = @($plan.packages | Where-Object {
    $_.action -eq "reuse" -and ($Components.Count -eq 0 -or $_.component -in $Components)
})

foreach ($package in $packages) {
    $target = Join-Path $destination ([string]$package.file)
    $validExisting = (Test-Path -LiteralPath $target -PathType Leaf) -and
        ((Get-Item -LiteralPath $target).Length -eq [int64]$package.baseSize) -and
        ((Get-RequiredFileHash -Path $target) -eq [string]$package.baseSha256)

    if (-not $validExisting) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        if ($BaseAssetDirectory) {
            $source = Join-Path $BaseAssetDirectory ([string]$package.file)
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Previous release asset is missing: $source"
            }
            Copy-Item -LiteralPath $source -Destination $target
        } else {
            if ([string]::IsNullOrWhiteSpace($Repository)) { throw "Repository is required to download release assets." }
            & gh release download $plan.baseRelease --repo $Repository --pattern ([string]$package.file) --dir $destination --clobber
            if ($LASTEXITCODE -ne 0) { throw "Failed to download $($package.file) from $($plan.baseRelease)." }
        }
    }

    $actualSize = (Get-Item -LiteralPath $target).Length
    if ($actualSize -ne [int64]$package.baseSize) {
        throw "$($package.file) size mismatch: expected $($package.baseSize), got $actualSize."
    }
    $actualHash = Get-RequiredFileHash -Path $target
    if ($actualHash -ne [string]$package.baseSha256) {
        throw "$($package.file) SHA256 mismatch while reusing $($plan.baseRelease)."
    }
    Write-Host "Reused exact release asset: $($package.file)"
}
