param(
    [Parameter(Mandatory = $true)][string]$PythonExe,
    [Parameter(Mandatory = $true)][string[]]$Components
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")

$layout = Get-RuntimeModelLayout
$config = $layout.LegacyConfig
$assetRoot = "tts-assets-package"
if (Test-Path $assetRoot) { Remove-Item $assetRoot -Recurse -Force }
New-Item -ItemType Directory -Path "$assetRoot\huggingface\hub" -Force | Out-Null

$prepareCore = $Components -contains "ttsCore"
$selectedRepos = @()
if ($config) {
    $selectedRepos = @($config.tts.huggingFaceRepos | Where-Object {
        $component = Convert-TtsPackageNameToKey -Name $_.zipFile
        $Components -contains $component
    })
}

if ($prepareCore) {
    $piperDir = Join-Path $assetRoot "piper_models"
    $sherpaDir = Join-Path $assetRoot ("sherpa_models\{0}" -f $(if ($config) { $config.tts.sherpaModelDir } else { "vits-mms-tgl" }))
    $nltkDir = Join-Path $assetRoot "nltk_data"
    New-Item -ItemType Directory -Path $piperDir, $sherpaDir, $nltkDir -Force | Out-Null

    if ($layout.HasLocalTtsCore) {
        Copy-Item -Path (Join-Path $layout.LocalTtsCoreRoot "piper_models\*") -Destination $piperDir -Recurse -Force
        Copy-Item -Path (Join-Path $layout.LocalTtsCoreRoot "sherpa_models\*") -Destination (Join-Path $assetRoot "sherpa_models") -Recurse -Force
        $localNltk = Join-Path $layout.LocalTtsCoreRoot "nltk_data"
        if (Test-Path $localNltk) {
            Copy-Item -Path (Join-Path $localNltk "*") -Destination $nltkDir -Recurse -Force
        }
    } elseif (-not $config) {
        throw "TTS core sources and runtime-models/speech-assets.json are both missing."
    }
}

if (-not $prepareCore -and $selectedRepos.Count -eq 0) {
    Write-Host "Selected TTS packages use local sources; no preparation is needed."
    return
}

$request = [ordered]@{
    prepareCore = $prepareCore -and -not $layout.HasLocalTtsCore
    piperVoiceRepo = if ($config) { $config.tts.piperVoiceRepo } else { $null }
    piperFiles = if ($config) { @($config.tts.piperFiles) } else { @() }
    sherpaRepo = if ($config) { $config.tts.sherpaRepo } else { $null }
    sherpaModelDir = if ($config) { $config.tts.sherpaModelDir } else { "vits-mms-tgl" }
    sherpaFiles = if ($config) { @($config.tts.sherpaFiles) } else { @() }
    nltkResources = if ($config) { @($config.tts.nltkResources) } else { @() }
    huggingFaceRepos = @($selectedRepos)
}
$requestPath = Join-Path $assetRoot "_prepare-request.json"
[System.IO.File]::WriteAllText($requestPath, ($request | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

& $PythonExe -c @"
import json, os, shutil, sys
try:
    from huggingface_hub import hf_hub_download, snapshot_download
    import nltk
except ImportError:
    print('required TTS download dependencies not found'); sys.exit(1)

root = os.path.abspath(r'$assetRoot')
with open(r'$requestPath', 'r', encoding='utf-8') as fp:
    request = json.load(fp)

hf_home = os.path.join(root, 'huggingface')
hub_cache = os.path.join(hf_home, 'hub')
os.environ['HF_HOME'] = hf_home
os.environ['HUGGINGFACE_HUB_CACHE'] = hub_cache
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'

if request['prepareCore']:
    piper_dir = os.path.join(root, 'piper_models')
    for fpath in request['piperFiles']:
        hf_hub_download(repo_id=request['piperVoiceRepo'], filename=fpath, local_dir=piper_dir, local_dir_use_symlinks=False)

    sherpa_dir = os.path.join(root, 'sherpa_models', request['sherpaModelDir'])
    for fpath in request['sherpaFiles']:
        downloaded = hf_hub_download(repo_id=request['sherpaRepo'], filename=fpath)
        shutil.copy(downloaded, os.path.join(sherpa_dir, os.path.basename(fpath)))

    nltk_dir = os.path.join(root, 'nltk_data')
    for resource_name in request['nltkResources']:
        if not nltk.download(resource_name, download_dir=nltk_dir, quiet=True):
            raise RuntimeError(f'NLTK download failed: {resource_name}')

for repo in request['huggingFaceRepos']:
    kwargs = {'repo_id': repo['repo_id'], 'cache_dir': hub_cache}
    if repo.get('allow_patterns'):
        kwargs['allow_patterns'] = repo['allow_patterns']
    snapshot_download(**kwargs)
"@
if ($LASTEXITCODE -ne 0) { throw "TTS asset preparation failed." }

Remove-Item -LiteralPath $requestPath -Force
