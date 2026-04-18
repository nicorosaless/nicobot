# NicoBot

Local voice assistant backend for macOS, now transitioning to an Electron app.

## Status

- Backend is operational and cleaned for productization.
- Next major milestone: Electron frontend + app packaging.

## Current backend

- Entrypoint: `spoken_assistant_ptt.py`
- Pipeline: `Parakeet v3 (STT, es)` -> `ES->EN translation` -> `Kokoro (af_bella)`
- Push-to-talk controls:
  - `F7` toggle record on/off
  - fallback `r` and `space`
  - `q` quit
- Per-turn metrics printed:
  - STT time
  - TTS generation time

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python spoken_assistant_ptt.py
```

## Project layout

```text
nicobot/
├── spoken_assistant_ptt.py
├── requirements.txt
├── docs/
│   ├── roadmap/ai-infra-roadmap.md
│   └── backend-packaging-plan.md
├── scripts/
└── artifacts/.gitkeep
```

## Roadmap docs

- Application roadmap: `docs/roadmap/ai-infra-roadmap.md`
- Backend + packaging plan: `docs/backend-packaging-plan.md`

## Platform notes

- macOS microphone permission must be enabled for your terminal/app.
- First model load can take time (download/warmup).

## Architectural decision (current)

- Frontend: **Electron**.
- Backend: **Python** now; Rust deferred until profiling justifies migration.
