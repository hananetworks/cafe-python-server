# runtime-models

이 폴더는 배포용 모델의 기준 위치입니다.

다른 사람이 작업할 때는 먼저 이 폴더를 보면 됩니다.  
STT와 Hailo는 여기 있는 파일이 그대로 패키징에 들어갑니다.

## 현재 상태

- STT: `runtime-models/` 실물 폴더 기준
- Hailo: `runtime-models/` 실물 폴더 기준
- Vision: `runtime-models/vision/` 실물 폴더 기준
- TTS: 실물 폴더가 있으면 우선 사용, 없으면 `speech-assets.json` fallback 사용

## 폴더 구조

```text
runtime-models/
  stt/
    small.pt
  hailo/
    models/
      Whisper-Small.hef
    Qwen2.5-1.5B-Instruct.hef
  vision/
    vision-assets.json
    # The package recipe adds version.txt and the complete pinned OpenCV wheel
    # installation under site-packages/.
    models/
      person/yolov8n.hef
      gender/yolo26-gender-best.hef
      gender/metadata.yaml
      age/yolo26-age-best.hef
      age/metadata.yaml
  tts/
    core/
      piper_models/
        ...
      sherpa_models/
        ...
      nltk_data/
        ...
    hf/
      tts-hf-bert-base-uncased/
        models--google-bert--bert-base-uncased/
          ...
      tts-hf-melo-ko/
        models--myshell-ai--MeloTTS-Korean/
          ...
  speech-assets.json
```

## 폴더별 의미

### `stt/`

- 이 안의 내용은 그대로 `stt-assets.zip`에 들어갑니다.
- STT 모델을 바꿀 때는 여기만 수정하면 됩니다.

### `hailo/models/`

- 이 안의 `.hef` 파일은 `hailo-addon.zip`의 `models/`로 들어갑니다.
- Guided VoiceOrder는 `Whisper-Small.hef`를 사용합니다.

### `hailo/Qwen2.5-1.5B-Instruct.hef`

- 있으면 `hailo-addon.zip`에 같이 포함됩니다.
- 없으면 없이 빌드됩니다.

### `vision/`

- Person/Gender/Age HEF, 실행 계약 메타데이터와 Windows CPython 3.11용으로 고정한
  `opencv-python-headless` 전체 wheel 설치 결과를 `vision-assets.zip`으로 별도 패키징합니다.
- 압축 내부의 OpenCV 경로는 `site-packages/cv2/`이며 wheel의 DLL/PYD/data/dist-info를
  모두 유지합니다.
- `scripts/verify-vision-assets.ps1`가 파일 크기, SHA-256, 단일 VDevice 계약 및
  `Age productionReady=false`를 확인합니다.
- Vision 변경은 VoiceOrder Hailo addon이나 STT/TTS package fingerprint를 바꾸지 않습니다.

### `tts/core/`

- `piper_models`, `sherpa_models`, `nltk_data`를 넣는 자리입니다.
- 실물 파일이 들어 있으면 `tts-core-assets.zip`은 이 폴더 기준으로 만들어집니다.

### `tts/hf/`

- `tts-hf-*` 폴더 단위로 개별 zip이 만들어집니다.
- 예:
  - `tts-hf-bert-base-uncased` -> `tts-hf-bert-base-uncased.zip`
  - `tts-hf-melo-ko` -> `tts-hf-melo-ko.zip`

### `speech-assets.json`

- 현재 TTS fallback 전용 설정 파일입니다.
- `runtime-models/tts/`에 실물 모델이 없을 때만 사용합니다.

## 작업 방법

### STT/Hailo만 바꿀 때

1. `runtime-models/` 아래 파일 교체
2. `scripts/verify-voiceorder-assets.ps1` 실행
3. 커밋
4. 태그 푸시

### TTS를 기존 방식으로 유지할 때

1. `speech-assets.json` 또는 관련 스크립트 확인
2. 커밋
3. 태그 푸시

### TTS도 실물 폴더 방식으로 바꿀 때

1. `tts/core/`, `tts/hf/`에 실제 모델 파일 배치
2. fallback 없이도 빌드되는지 확인
3. 필요하면 이후 `speech-assets.json` 의존 제거
