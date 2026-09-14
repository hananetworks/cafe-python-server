# cafe-python-server

Current Guided VoiceOrder runtime tag: `env-v1.4.37`.

키오스크 런타임용 Python 환경과 런타임 자산을 빌드하고 GitHub Release로 배포하는 저장소입니다.

이 저장소에서 만드는 주요 산출물:

- `python-engine.zip`
- `stt-assets.zip`
- `tts-core-assets.zip`
- `tts-hf-*.zip`
- `hailo-addon.zip`
- `vision-assets.zip`
- `runtime-manifest.json`

`env-v1.4.36` 이후 릴리즈는 패키지별 source/recipe fingerprint를 비교합니다. 내용이 같은
패키지는 이전 릴리즈 ZIP을 다시 압축하지 않고 그대로 복사하므로 SHA-256도 유지됩니다.

## 기본 원칙

- 최종 배포는 항상 `env-v*` 태그 푸시로 합니다.
- VoiceOrder CPU/Hailo 실물 모델은 `runtime-models/` 아래만 수정하면 됩니다.
- TTS는 현재 두 방식이 공존합니다.
  - `runtime-models/tts/...`에 실물 모델을 넣으면 그 폴더를 우선 사용
  - 실물 모델이 없으면 `runtime-models/speech-assets.json` 기준으로 다운로드 fallback 동작

## 폴더 설명

- `runtime-models/`
  - 배포에 쓰는 모델 입력 폴더
- `scripts/`
  - 빌드, 패키징, manifest 생성 스크립트
- `.github/workflows/python-env-deploy.yml`
  - GitHub Actions 배포 워크플로

자세한 모델 폴더 규칙은 [`runtime-models/README.md`](runtime-models/README.md)를 보면 됩니다.

## 어떤 걸 어디서 바꾸는지

### 1. STT 모델 변경

- 위치: `runtime-models/stt/`
- 파일: `runtime-models/stt/small.pt`
- 결과: `stt-assets.zip`에 그대로 반영

### 2. Hailo HEF 변경

- 파일: `runtime-models/hailo/models/Whisper-Small.hef`
- 선택 파일: `runtime-models/hailo/Qwen2.5-1.5B-Instruct.hef`
- 결과: `hailo-addon.zip`에 반영

모델 무결성은 `scripts/verify-voiceorder-assets.ps1`로 확인합니다.

### 3. Vision 모델 변경

- 위치: `runtime-models/vision/`
- 결과: `vision-assets.zip`에만 반영
- 검증: `scripts/verify-vision-assets.ps1`

Vision 패키지는 Person/Gender/Age HEF와 메타데이터만 배포합니다. HailoRT wheel은 기존
`hailo-addon.zip`에 유지되므로 Vision 모델만 바뀌어도 engine/STT/TTS/Hailo addon은
재다운로드하지 않습니다. 실행 계층은 하나의 프로세스와 하나의 `VDevice`에서 세 Vision
InferModel과 Whisper STT를 함께 소유해야 하며, 최종 4모델 동시부하는 실장비 검증 전까지
`DEVICE VERIFICATION REQUIRED`입니다. Age는 계속 `productionReady=false`입니다.

## 프로세스 구성

- TTS: 기존 FastAPI `api_server.py` 프로세스
- VoiceOrder: 키오스크가 시작하는 JSONL worker 프로세스
- 두 프로세스는 동일한 `kiosk_python.exe` 환경을 사용하되 서로 독립적으로 상주합니다.
- 키오스크 시작 시 둘 다 warmup되고, 유휴 상태에서는 모델을 유지한 채 마이크만 닫습니다.

현재 전달 패키지에서 검증된 Hailo 조합은 Windows Python 3.11.9 + HailoRT 5.3.0입니다.
저장소의 Hailo wheel 버전이 다르면 실제 미니PC에서 별도 호환 검증이 필요합니다.

HailoRT wheel은 `hailo-addon.zip/site-packages`에 포함됩니다. Python engine의
`python311._pth`는 `../hailo/site-packages`를 참조하므로 이후 HailoRT wheel 변경은
engine이 아니라 Hailo addon만 갱신합니다. 이 분리 구조로 전환하는 최초 릴리즈에서는
engine과 Hailo addon이 한 번 함께 변경됩니다.

### 4. TTS 실물 모델로 운영할 때

- 위치:
  - `runtime-models/tts/core/piper_models/...`
  - `runtime-models/tts/core/sherpa_models/...`
  - `runtime-models/tts/core/nltk_data/...`
  - `runtime-models/tts/hf/tts-hf-*/...`
- 결과:
  - `tts-core-assets.zip`
  - `tts-hf-*.zip`

### 5. TTS를 기존 방식으로 유지할 때

- 위치: `runtime-models/speech-assets.json`
- 의미: 다운로드할 Piper, Sherpa, Hugging Face, NLTK 목록 정의

## 배포 규칙

### `main` 먼저 푸시한 뒤 태그

아래 파일이 바뀌면 engine source/recipe fingerprint에 영향이 있으므로 `main`을 먼저 올리는 게 좋습니다.

- `requirements.txt`
- `scripts/build-python-env.ps1`
- `scripts/package-engine.ps1`

`libs/hailort-*.whl`은 Hailo addon에만 영향을 줍니다. STT/TTS/Hailo 패키징 스크립트도
각자 담당하는 패키지 fingerprint에만 영향을 줍니다.
공통 archive helper의 출력 규칙을 바꾸는 경우에는 영향을 받는 패키지별 스크립트도 같은
커밋에서 갱신하여 해당 recipe fingerprint만 변경해야 합니다.

권장 순서:

1. `main` 푸시
2. `main` GitHub Actions 완료 확인
3. `env-v1.4.xx` 태그 푸시

### 태그만 푸시

엔진 패키지에 영향이 없는 변경은 태그만 바로 푸시해도 됩니다.

예시:

- `runtime-models/stt/**`
- `runtime-models/hailo/**`
- `runtime-models/tts/**`
- `runtime-models/speech-assets.json`
- `scripts/prepare-speech-assets.ps1`
- `scripts/generate-runtime-artifacts.ps1`
- `.github/workflows/python-env-deploy.yml`

권장 순서:

1. 변경 커밋 확인
2. `env-v1.4.xx` 태그 푸시

## 빠른 운영 요약

- STT/Hailo 바꿀 때는 `runtime-models/`만 수정
- TTS는 지금 당장은 기존 fallback 유지 가능
- 엔진에 영향이 있으면 `main` 먼저
- 최종 배포는 항상 태그
- 릴리즈 전에 `scripts/resolve-runtime-package-plan.ps1`로 `REUSE`/`REBUILD` 결과 확인
- 기존 릴리즈는 덮어쓰지 않으며, 검증된 draft만 공개 릴리즈로 전환
