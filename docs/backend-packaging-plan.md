# Backend & Packaging Plan

## Current backend status

- Main runtime entrypoint: `spoken_assistant_ptt.py`
- Input flow: push-to-talk (`F7`, fallback `r`/space)
- Pipeline: `Parakeet (STT)` -> `ES->EN translation` -> `Kokoro (af_bella)`
- Metrics printed after each run:
  - STT time
  - TTS generation time

## Backend cleanup completed

- Kept only the runtime-oriented backend file:
  - `spoken_assistant_ptt.py`
- Legacy/experimental files removed from root:
  - `parakeet_coreml.py`
  - `spoken_assistant_whisper.py`
  - `spoken_assistant_parakeet.py`
- Cleaned heavy local artifacts and caches from repo tracking.

## Backend hardening checklist (next)

1. Split `spoken_assistant_ptt.py` into modules:
   - `backend/audio_io.py`
   - `backend/stt.py`
   - `backend/translate.py`
   - `backend/tts.py`
   - `backend/app.py`
2. Add structured logs (`json`) and error codes.
3. Add a simple local API layer for frontend integration:
   - `/health`
   - `/start_recording`
   - `/stop_and_process`
4. Add smoke tests for non-audio logic.

## Packaging strategy (macOS)

### Recommended path

- Package backend as a local service binary using `pyinstaller`.
- Keep frontend as separate app shell (Tauri/Electron/SwiftUI), talking to localhost.

### Why this split

- Faster iteration on frontend without rebuilding STT/TTS internals each time.
- Clear failure boundaries and easier diagnostics.
- Easier future migration to native frontend.

## Packaging milestones

1. **Backend binary**
   - Add `pyinstaller` spec for `spoken_assistant_ptt.py`
   - Produce reproducible build in CI.
2. **App shell**
   - Launch backend on app startup.
   - Poll `/health` until ready.
3. **Installer/distribution**
   - Create signed `.app` + `.dmg`.
   - Add first-run permissions guidance (microphone/accessibility if needed).

## Frontend handoff contract

The frontend can start with these assumptions:

- Backend exposes deterministic states:
  - `idle`
  - `recording`
  - `processing`
  - `speaking`
- Backend returns timing metrics per turn:
  - `stt_seconds`
  - `tts_seconds`
  - `total_seconds`

This allows immediate UI work while backend continues to harden.
