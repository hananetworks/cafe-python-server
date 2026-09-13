# Cafe Python runtime architecture

## Process boundary

The packaged Python environment is shared, while the long-lived processes are separate:

- `api_server.py`: local FastAPI TTS server
- `voiceorder_host.py`: request-scoped JSONL Guided VoiceOrder host
- `cpu_whisper_worker.py`: CPU Whisper fallback child owned by the VoiceOrder host

Electron starts and warms the TTS server and VoiceOrder host during kiosk boot. Both remain
loaded in `READY_IDLE`; microphone capture is owned by the renderer and exists only during a
guided turn. Electron closes the workers with the application and retries an unexpected
VoiceOrder process exit with bounded backoff.

## Runtime assets

- CPU fallback: `runtime-models/stt/small.pt`
- Hailo primary: `runtime-models/hailo/models/Whisper-Small.hef`
- TTS: `runtime-models/tts/**` or the existing `speech-assets.json` fallback

Run `scripts/verify-voiceorder-assets.ps1` before packaging. The script rejects missing or
hash-mismatched VoiceOrder models.

## Compatibility gate

The delivered mini-PC evidence is Python 3.11.9 with HailoRT/SDK/firmware 5.3.0. A different
Hailo wheel or driver combination must be tested on the target mini-PC before release. CPU
fallback and touch ordering remain available when Hailo preparation fails.

The first runtime release consumed by the kiosk is `env-v1.4.35`. The kiosk version and this
tag must stay aligned so an older locally cached runtime cannot satisfy the new VoiceOrder boot.
