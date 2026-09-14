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
- Hailo Python binding: `libs/hailort-*.whl`, packaged only in `hailo-addon.zip/site-packages`
- Vision HEFs, metadata, and pinned Windows CPython 3.11 OpenCV runtime: packaged only in
  `vision-assets.zip`, with OpenCV installed under `site-packages/`
- TTS: `runtime-models/tts/**` or the existing `speech-assets.json` fallback

Run `scripts/verify-voiceorder-assets.ps1` before packaging. The script rejects missing or
hash-mismatched VoiceOrder models.

## Content-addressed releases

Each runtime component has an independent source fingerprint and packaging-recipe fingerprint.
Before a release, CI compares them with the latest valid `env-v*` release. An unchanged component
reuses the exact previous ZIP after checking its release SHA-256 and size; it is never recompressed.
Changed components alone are rebuilt with sorted archive entries and archive timestamps disabled.

`env-v1.4.36` is the migration baseline. Its manifest predates source fingerprints, so CI derives
the baseline fingerprints from that Git tag. The first release using the new layout rebuilds the
engine and Hailo addon to move HailoRT out of the engine, while reusing the exact 1.4.36 STT and TTS
archives. Subsequent HailoRT-only changes rebuild only `hailo-addon.zip`.
Vision model or contract changes rebuild only `vision-assets.zip`; they do not change the
HailoRT addon, STT, TTS, or Python engine identities.

## Shared Hailo ownership contract

The runtime packaging boundary does not create a Hailo device. The application execution layer
must keep exactly one Hailo owner process and one `VDevice`, then construct Person, Gender, Age,
and Whisper from that owner. Per-model `VDevice()` construction is forbidden because the target
device reproduced `HAILO_OUT_OF_PHYSICAL_DEVICES(74)`.

Person consumes the latest frame in real time. Gender runs at about 1 Hz, and Age runs at most
once per Gender tick only when a valid face box exists. Both paths use capacity-1/latest-value
semantics, never an accumulating queue. The validated camera contract is DSHOW + MJPG +
1920x1080@30 passed as `VideoCapture.open(...)` parameters. Frames and face crops are memory-only.
The supplied production draft remains NOT RUN / NOT VERIFIED, Age remains production-unready,
and Person + Gender + Age + Whisper STT requires a new combined device validation.

## Compatibility gate

The delivered mini-PC evidence is Python 3.11.9 with HailoRT/SDK/firmware 5.3.0. A different
Hailo wheel or driver combination must be tested on the target mini-PC before release. CPU
fallback and touch ordering remain available when Hailo preparation fails.

The current runtime release consumed by the kiosk is `env-v1.4.38`. The kiosk version and this
tag must stay aligned so an older locally cached runtime cannot satisfy the new VoiceOrder boot.
