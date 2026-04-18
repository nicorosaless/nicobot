# NicoBot Application Roadmap

**Last updated:** 18 Apr 2026
**Current phase:** Backend stable, moving to Electron frontend + packaging

## Decisions locked

- Frontend framework: **Electron** (fastest path to shippable desktop app).
- Backend runtime: **Python** for now (`spoken_assistant_ptt.py`).
- STT: **Parakeet v3** via NeMo.
- TTS: **Kokoro** (`af_bella`).
- Interaction model: push-to-talk toggle (`F7`, fallback `r`/`space`).

## Rust backend decision

Current recommendation: **do not migrate backend to Rust yet**.

Why:
- Biggest latency costs are model inference and I/O, not Python control flow.
- Python ecosystem is already integrated and working.
- Moving to Rust now slows delivery of frontend and packaging milestones.

When to reconsider Rust:
- If end-to-end profiling shows Python orchestration >10-15% of total turn time.
- If we need a smaller single-binary backend footprint for distribution.
- If reliability constraints require stricter concurrency/memory guarantees.

## Roadmap phases

### Phase A - Backend stabilization (now)

- [x] Single runtime entrypoint.
- [x] Preload models before first recording.
- [x] Show per-turn timing metrics (STT/TTS).
- [ ] Extract backend modules (`audio`, `stt`, `translate`, `tts`, `session`).
- [ ] Add structured logs and error codes.

### Phase B - Electron app shell

- [x] Create Electron app with 3 core states:
  - idle
  - recording
  - processing/speaking
- [x] Wire UI controls to backend actions.
- [x] Render latency metrics in UI for each turn.
- [ ] Add first-run setup panel (mic permissions, model warmup).

### Phase C - Backend/UI integration contract

- [ ] Expose local backend API (localhost):
  - `GET /health`
  - `POST /record/start`
  - `POST /record/stop`
  - `GET /metrics/last`
- [ ] Define stable payload schema for frontend.
- [ ] Add reconnect and backend restart handling from Electron.

### Phase D - Packaging and distribution

- [ ] Bundle backend runtime and app shell together.
- [ ] Build signed macOS `.app`.
- [ ] Generate distributable `.dmg`.
- [ ] Add first-run guidance and diagnostics.
- [ ] Validate clean install on a fresh macOS user account.

## Acceptance criteria for "frontend can start"

- Backend starts and reaches healthy state consistently.
- Recording cycle is deterministic (toggle start/stop).
- Turn metrics are emitted every run.
- Known errors have clear user-facing messages.

## Acceptance criteria for "ready to ship alpha"

- Electron app controls backend end-to-end with no terminal needed.
- First-time user can install, grant permissions, and complete one full turn.
- Crash recovery/restart path works.
- Build pipeline produces reproducible macOS artifacts.
