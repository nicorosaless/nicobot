# Backend and Packaging Plan (Electron-first)

## Goal

Ship a downloadable macOS app quickly with:
- Electron frontend
- Local Python backend service
- Embedded STT/TTS pipeline

## Backend scope (frozen for frontend handoff)

- Runtime entrypoint: `spoken_assistant_ptt.py`
- Pipeline: `Parakeet v3` -> `ES->EN` -> `Kokoro`
- Input: push-to-talk toggle (`F7`, fallback `r`/`space`)
- Metrics: `stt_seconds`, `tts_seconds`

## Minimal backend service contract for Electron

Implement a thin local API wrapper around existing logic:

- `GET /health`
  - returns readiness + model preload state
- `POST /record/start`
  - starts recording session
- `POST /record/stop`
  - stops recording and returns transcription/translation/tts status
- `GET /metrics/last`
  - returns timings of last processed turn

## Packaging strategy

### Recommended

- Keep Python backend as packaged local service.
- Electron starts backend child process on app boot.
- UI interacts with backend via localhost API.

### Why

- Fastest implementation path.
- Clear separation of concerns.
- No premature Rust rewrite.

## Build outputs

1. **Backend bundle**
   - packaged Python runtime + dependencies
2. **Electron app**
   - macOS `.app`
3. **Installer**
   - signed `.dmg`

## Signing/notarization checklist

- Developer ID cert configured
- Hardened runtime enabled
- Notarization + staple workflow
- Verify install on clean machine

## Rust migration note

Rust backend remains optional and deferred.

Only migrate when profiling proves Python orchestration is a real bottleneck or packaging footprint requires it.
