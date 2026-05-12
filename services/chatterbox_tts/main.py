#!/usr/bin/env python3
"""
Chatterbox-Turbo TTS Sidecar for Umi.
Precarga el modelo en startup y sirve generación vía FastAPI.
Soporta MPS (Metal) en macOS Apple Silicon, con fallback a CPU.
"""

import os
import sys
import time
import tempfile
import traceback
from pathlib import Path
from typing import Optional

import torch
import torchaudio as ta
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

# ── Configuration from env ───────────────────────────────────────────────────
DEVICE = os.getenv("CHATTERBOX_DEVICE", "auto")
VOICES_DIR = Path(os.getenv("CHATTERBOX_VOICES_DIR", Path(__file__).parent / "voices"))
DEFAULT_VOICE_ID = os.getenv("CHATTERBOX_DEFAULT_VOICE_ID", "cristina")
PORT = int(os.getenv("CHATTERBOX_PORT", "10202"))
HOST = os.getenv("CHATTERBOX_HOST", "127.0.0.1")

# ── Device selection ─────────────────────────────────────────────────────────
def pick_device():
    if DEVICE != "auto":
        return DEVICE
    if torch.backends.mps.is_available():
        return "mps"
    return "cpu"

DEVICE_FINAL = pick_device()
print(f"[chatterbox] Using device: {DEVICE_FINAL}", file=sys.stderr, flush=True)

# ── Lazy model loading ───────────────────────────────────────────────────────
_model = None
_sr = None

def get_model():
    global _model, _sr
    if _model is None:
        from chatterbox.tts_turbo import ChatterboxTurboTTS
        print("[chatterbox] Loading ChatterboxTurboTTS model…", file=sys.stderr, flush=True)
        t0 = time.time()
        _model = ChatterboxTurboTTS.from_pretrained(device=DEVICE_FINAL)
        _sr = _model.sr
        print(f"[chatterbox] Model loaded in {time.time() - t0:.1f}s (sr={_sr})", file=sys.stderr, flush=True)
    return _model, _sr

# ── Voice resolution ─────────────────────────────────────────────────────────
def resolve_voice_path(voice_id: Optional[str]) -> Optional[Path]:
    voice_id = voice_id or DEFAULT_VOICE_ID
    candidates = [
        VOICES_DIR / f"{voice_id}_ref.wav",
        VOICES_DIR / f"{voice_id}.wav",
        VOICES_DIR / f"{voice_id}.mp3",
        VOICES_DIR / voice_id,
    ]
    for c in candidates:
        if c.exists():
            return c
    return None

# ── FastAPI app ──────────────────────────────────────────────────────────────
app = FastAPI(title="Chatterbox Turbo TTS Sidecar")

class GenerateRequest(BaseModel):
    text: str
    voice_id: Optional[str] = None

@app.on_event("startup")
async def startup():
    # Warm-up: preload model on first request or eager here
    try:
        get_model()
    except Exception as e:
        print(f"[chatterbox] ERROR preloading model: {e}", file=sys.stderr, flush=True)
        traceback.print_exc()

@app.get("/health")
async def health():
    healthy = _model is not None
    return {"status": "ok" if healthy else "loading", "device": DEVICE_FINAL, "model_loaded": healthy}

@app.post("/generate")
async def generate(req: GenerateRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    model, sr = get_model()

    voice_path = resolve_voice_path(req.voice_id)
    if voice_path is None:
        # If no voice reference found, we cannot clone; return informative error
        raise HTTPException(
            status_code=400,
            detail=f"No voice reference found for '{req.voice_id or DEFAULT_VOICE_ID}' in {VOICES_DIR}"
        )

    try:
        t0 = time.time()
        wav = model.generate(req.text, audio_prompt_path=str(voice_path))
        gen_time = time.time() - t0
        print(f"[chatterbox] Generated {len(wav)} samples in {gen_time:.2f}s", file=sys.stderr, flush=True)

        # Write to temporary WAV file and read bytes
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name
        ta.save(tmp_path, wav, sr)
        with open(tmp_path, "rb") as f:
            audio_bytes = f.read()
        os.unlink(tmp_path)

        return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
