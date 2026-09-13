$ErrorActionPreference = "Stop"

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
    } finally {
        $sha.Dispose()
    }
}

function Get-RequiredFileHash {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-DeterministicZip {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [int]$CompressionLevel = 9,
        [string[]]$IncludePatterns = @(),
        [string[]]$ExcludePatterns = @()
    )

    $source = (Resolve-Path -LiteralPath $SourceRoot).Path
    $output = [System.IO.Path]::GetFullPath($OutputPath)
    $files = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($source.Length).TrimStart('\', '/').Replace('\', '/')
    } | Where-Object {
        $relative = $_
        ($IncludePatterns.Count -eq 0 -or ($IncludePatterns | Where-Object { $relative -match $_ })) -and
            -not ($ExcludePatterns | Where-Object { $relative -match $_ })
    } | Sort-Object)

    if ($files.Count -eq 0) {
        throw "No files found to package under $source"
    }

    $workRoot = Join-Path (Split-Path -Parent $output) ".runtime-work"
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    $listPath = Join-Path $workRoot ("7zip-{0}.txt" -f [Guid]::NewGuid().ToString("N"))
    Write-Utf8NoBom -Path $listPath -Content (($files -join "`n") + "`n")

    try {
        if (Test-Path -LiteralPath $output) {
            Remove-Item -LiteralPath $output -Force
        }
        Push-Location $source
        try {
            & 7z a -tzip "-mx=$CompressionLevel" -mtc=off -mta=off -mtm=off $output "@$listPath"
            if ($LASTEXITCODE -ne 0) {
                throw "7-Zip failed to create $output (exit=$LASTEXITCODE)."
            }
        } finally {
            Pop-Location
        }
    } finally {
        if (Test-Path -LiteralPath $listPath) {
            Remove-Item -LiteralPath $listPath -Force
        }
    }

    & 7z t $output | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Archive integrity test failed: $output"
    }
}

# This helper is deliberately not part of every component recipe fingerprint.
# If an output-affecting archive rule changes here, update the affected
# component-specific package script(s) in the same commit so only those recipe
# fingerprints advance.

function Write-GitHubOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        "$Name=$Value" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
}
