#!/usr/bin/env python3
"""
Kokoro TTS Sidecar for Umi.
Fast local TTS (~1-2s per sentence). English only (lang_code='a').
"""

import os
import sys
import time
import tempfile
import traceback
from pathlib import Path
from typing import Optional

import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from contextlib import asynccontextmanager

# ── Configuration ────────────────────────────────────────────────────────────
PORT = int(os.getenv("KOKORO_PORT", "10203"))
HOST = os.getenv("KOKORO_HOST", "127.0.0.1")
DEFAULT_VOICE = os.getenv("KOKORO_VOICE", "af_bella")
DEFAULT_SPEED = float(os.getenv("KOKORO_SPEED", "1.0"))
DEFAULT_SR = 24000

# ── Lazy model loading ─────────────────────────────────────────────────────────
_pipeline = None

def get_pipeline():
    global _pipeline
    if _pipeline is None:
        from kokoro import KPipeline
        print("[kokoro] Loading KPipeline…", file=sys.stderr, flush=True)
        t0 = time.time()
        _pipeline = KPipeline(lang_code="a")
        print(f"[kokoro] Pipeline ready in {time.time()-t0:.1f}s", file=sys.stderr, flush=True)
    return _pipeline

# ── FastAPI lifespan ─────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        get_pipeline()
    except Exception as e:
        print(f"[kokoro] ERROR preloading: {e}", file=sys.stderr, flush=True)
        traceback.print_exc()
    yield

app = FastAPI(title="Kokoro TTS Sidecar", lifespan=lifespan)

class GenerateRequest(BaseModel):
    text: str
    voice: Optional[str] = None
    speed: Optional[float] = None

@app.get("/health")
async def health():
    return {"status": "ok" if _pipeline is not None else "loading"}

@app.post("/generate")
async def generate(req: GenerateRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    pipeline = get_pipeline()
    voice = req.voice or DEFAULT_VOICE
    speed = req.speed if req.speed is not None else DEFAULT_SPEED

    try:
        t0 = time.time()
        generator = pipeline(req.text, voice=voice, speed=speed)
        audio = None
        for _, _, a in generator:
            audio = a
            break

        if audio is None:
            raise HTTPException(status_code=500, detail="No audio generated")

        gen_time = time.time() - t0
        print(f"[kokoro] Generated in {gen_time:.2f}s (voice={voice}, speed={speed})", file=sys.stderr, flush=True)

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name
        sf.write(tmp_path, audio, DEFAULT_SR)
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
