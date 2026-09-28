# Qwen Natural VoiceOrder runtime migration

This branch introduces the isolated Qwen runtime foundation only.

## Validated product runtime

The mini-PC validation environment that passed Natural VoiceOrder uses:

- Python 3.11.9
- `sherpa-onnx==1.13.8`
- `numpy==2.4.6`
- Qwen3-ASR 0.6B INT8
- 3 inference threads

The existing kiosk/TTS Python engine remains separate and keeps its existing
dependency set. In particular, its NumPy version is not changed by this phase.

## Model distribution policy

The 878,702,423-byte Qwen model archive is **not** stored in this Git repository,
Git LFS, `qwen-engine.zip`, or an `env-v*` release asset.

`runtime-models/qwen3-asr.json` pins the upstream immutable archive URL, byte size,
SHA-256 and install location. A future kiosk bootstrap change will:

1. read the pinned model reference,
2. reuse an installed model when its SHA-256 matches,
3. download the model only when missing or mismatched,
4. verify SHA-256 before activation.

This avoids downloading and re-uploading the ~879 MB model on every runtime release.

## This phase does not yet change

- the current `env-v*` release manifest/package plan,
- the current kiosk bootstrap installer,
- legacy CPU/Hailo Whisper release assets,
- TTS/Vision packaging.

Those changes follow only after the isolated Qwen engine can be built and verified
reproducibly on the company PC.
