param(
    [Parameter(Mandatory = $true)]
    [string]$PythonExe,

    [Parameter(Mandatory = $true)]
    [string]$EnvName,

    [switch]$SkipTtsSetup,

    [switch]$SkipSttSetup
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "get-runtime-model-layout.ps1")
$Layout = Get-RuntimeModelLayout

function ConvertTo-JsonArrayLiteral {
    param(
        [Parameter(Mandatory = $true)]
        $Value,

        [int]$Depth = 2
    )

    $items = @($Value)
    if ($items.Count -eq 0) {
        return "[]"
    }

    return ($items | ConvertTo-Json -Compress -Depth $Depth)
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$SpeechAssetConfig = $Layout.LegacyConfig
$PiperVoiceFiles = @()
$SherpaModelFiles = @()
$TtsHubRepos = @()
$NltkResources = @()
$PiperVoiceRepo = $null
$SherpaRepo = $null
$SherpaModelSubdir = "vits-mms-tgl"

if ($SpeechAssetConfig) {
    $PiperVoiceFiles = @($SpeechAssetConfig.tts.piperFiles)
    $SherpaModelFiles = @($SpeechAssetConfig.tts.sherpaFiles)
    $TtsHubRepos = @($SpeechAssetConfig.tts.huggingFaceRepos)
    $NltkResources = @($SpeechAssetConfig.tts.nltkResources)
    $PiperVoiceRepo = $SpeechAssetConfig.tts.piperVoiceRepo
    $SherpaRepo = $SpeechAssetConfig.tts.sherpaRepo
    $SherpaModelSubdir = $SpeechAssetConfig.tts.sherpaModelDir
}

if (-not $SkipTtsSetup) {
    Write-Host "Preparing TTS model assets..."
    $TtsAssetDir = "tts-assets-package"
    if (Test-Path $TtsAssetDir) { Remove-Item $TtsAssetDir -Recurse -Force }
    $PiperModelDir = Join-Path $TtsAssetDir "piper_models"
    $SherpaModelDir = Join-Path $TtsAssetDir "sherpa_models\$SherpaModelSubdir"
    New-Item -ItemType Directory -Path $PiperModelDir -Force | Out-Null
    New-Item -ItemType Directory -Path $SherpaModelDir -Force | Out-Null
    New-Item -ItemType Directory -Path "$TtsAssetDir\huggingface\hub" -Force | Out-Null
    New-Item -ItemType Directory -Path "$TtsAssetDir\nltk_data" -Force | Out-Null

    $LocalNltkDir = Join-Path $Layout.LocalTtsCoreRoot "nltk_data"
    if ($Layout.HasLocalTtsCore) {
        Write-Host "  -> Using local TTS core folders from runtime-models\\tts\\core"
        Copy-Item -Path (Join-Path $Layout.LocalTtsCoreRoot "piper_models\*") -Destination $PiperModelDir -Recurse -Force
        Copy-Item -Path (Join-Path $Layout.LocalTtsCoreRoot "sherpa_models\*") -Destination (Join-Path $TtsAssetDir "sherpa_models") -Recurse -Force
        $PiperVoiceFiles = @()
        $SherpaModelFiles = @()

        if (Test-Path $LocalNltkDir) {
            Copy-Item -Path (Join-Path $LocalNltkDir "*") -Destination "$TtsAssetDir\nltk_data" -Recurse -Force
            $NltkResources = @()
        }
    }

    if ($Layout.HasLocalTtsHfPackages) {
        Write-Host "  -> Using local HF model folders from runtime-models\\tts\\hf"
        $TtsHubRepos = @()
    }

    $PiperVoiceFilesJson = ConvertTo-JsonArrayLiteral -Value $PiperVoiceFiles
    $SherpaModelFilesJson = ConvertTo-JsonArrayLiteral -Value $SherpaModelFiles
    $TtsHubReposJson = ConvertTo-JsonArrayLiteral -Value $TtsHubRepos -Depth 4
    $NltkResourcesJson = ConvertTo-JsonArrayLiteral -Value $NltkResources
    $PiperVoiceFilesJsonPath = Join-Path $TtsAssetDir "_piper_files.json"
    $SherpaModelFilesJsonPath = Join-Path $TtsAssetDir "_sherpa_files.json"
    $TtsHubReposJsonPath = Join-Path $TtsAssetDir "_hf_repos.json"
    $NltkResourcesJsonPath = Join-Path $TtsAssetDir "_nltk_resources.json"

    Write-Utf8NoBomFile -Path $PiperVoiceFilesJsonPath -Content $PiperVoiceFilesJson
    Write-Utf8NoBomFile -Path $SherpaModelFilesJsonPath -Content $SherpaModelFilesJson
    Write-Utf8NoBomFile -Path $TtsHubReposJsonPath -Content $TtsHubReposJson
    Write-Utf8NoBomFile -Path $NltkResourcesJsonPath -Content $NltkResourcesJson

    & $PythonExe -c @"
import json, os, shutil, sys
try:
    from huggingface_hub import hf_hub_download, snapshot_download
    import nltk
except ImportError:
    print('required TTS download dependencies not found'); sys.exit(1)

piper_dir = r'$PiperModelDir'
hf_home = r'$TtsAssetDir\huggingface'
hub_cache = os.path.join(hf_home, 'hub')
nltk_dir = r'$TtsAssetDir\nltk_data'
os.environ['HF_HOME'] = hf_home
os.environ['HUGGINGFACE_HUB_CACHE'] = hub_cache
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'

with open(r'$PiperVoiceFilesJsonPath', 'r', encoding='utf-8') as fp:
    piper_files = json.load(fp)
with open(r'$SherpaModelFilesJsonPath', 'r', encoding='utf-8') as fp:
    sherpa_files = json.load(fp)
with open(r'$TtsHubReposJsonPath', 'r', encoding='utf-8') as fp:
    hf_repos = json.load(fp)
with open(r'$NltkResourcesJsonPath', 'r', encoding='utf-8') as fp:
    nltk_resources = json.load(fp)

print('Downloading Piper models...')
for fpath in piper_files:
    fname = fpath.split('/')[-1]
    try:
        hf_hub_download(repo_id=r'''$PiperVoiceRepo''', filename=fpath, local_dir=piper_dir, local_dir_use_symlinks=False)
        print(f' - OK: {fname}')
    except Exception:
        print(f' - FAIL: {fname}')

sherpa_dir = r'$SherpaModelDir'

print('Downloading Sherpa models...')
for fpath in sherpa_files:
    fname = fpath.split('/')[-1]
    try:
        down_path = hf_hub_download(repo_id=r'''$SherpaRepo''', filename=fpath)
        shutil.copy(down_path, os.path.join(sherpa_dir, fname))
        print(f' - OK: {fname}')
    except Exception as e:
        print(f' - FAIL: {fname} ({e})')

print('Downloading HuggingFace cache for MeloTTS...')
for repo in hf_repos:
    repo_id = repo['repo_id']
    kwargs = {'repo_id': repo_id, 'cache_dir': hub_cache}
    allow_patterns = repo.get('allow_patterns')
    if allow_patterns:
        kwargs['allow_patterns'] = allow_patterns
    try:
        snapshot_download(**kwargs)
        print(f' - OK: {repo_id}')
    except Exception as e:
        print(f' - FAIL: {repo_id} ({e})')

print('Downloading NLTK resources...')
for resource_name in nltk_resources:
    try:
        nltk.download(resource_name, download_dir=nltk_dir, quiet=True)
        print(f' - OK: {resource_name}')
    except Exception as e:
        print(f' - FAIL: {resource_name} ({e})')
"@
} else {
    Write-Host "Skipping TTS model setup. Reusing cached TTS assets."
}

if (-not $SkipSttSetup) {
    Write-Host "Checking STT model assets..."
    if ($Layout.HasLocalStt) {
        Write-Host "  -> Using local STT folders from runtime-models\\stt"
    } else {
        Write-Host "Warning: no STT model source found in runtime-models\\stt."
    }
} else {
    Write-Host "Skipping STT model setup. Reusing cached STT assets."
}
