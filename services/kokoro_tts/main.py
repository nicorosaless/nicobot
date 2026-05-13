#!/usr/bin/env python3
"""
Kokoro TTS Sidecar for Umi.
Fast local TTS (~1-2s per sentence). Supports English (lang_code='a') and Spanish (lang_code='e').
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
DEFAULT_SPEED = float(os.getenv("KOKORO_SPEED", "1.0"))
DEFAULT_SR = 24000

# Maps ISO language code → Kokoro lang_code
LANG_MAP = {"en": "a", "es": "e", "a": "a", "e": "e"}
# Default voice per lang_code
VOICE_DEFAULTS = {"a": os.getenv("KOKORO_VOICE_EN", "af_bella"), "e": os.getenv("KOKORO_VOICE_ES", "ef_dora")}

# ── Shared model + per-language pipelines ────────────────────────────────────
_model = None
_pipelines: dict[str, object] = {}

def get_pipeline(lang_code: str = "e"):
    global _model
    from kokoro import KPipeline, KModel
    if _model is None:
        print("[kokoro] Loading KModel…", file=sys.stderr, flush=True)
        t0 = time.time()
        _model = KModel(repo_id="hexgrad/Kokoro-82M").to("mps").eval()
        print(f"[kokoro] KModel ready in {time.time()-t0:.1f}s", file=sys.stderr, flush=True)
    if lang_code not in _pipelines:
        print(f"[kokoro] Loading KPipeline(lang_code={lang_code!r})…", file=sys.stderr, flush=True)
        t0 = time.time()
        _pipelines[lang_code] = KPipeline(lang_code=lang_code, model=_model)
        print(f"[kokoro] Pipeline({lang_code}) ready in {time.time()-t0:.1f}s", file=sys.stderr, flush=True)
    return _pipelines[lang_code]

# ── FastAPI lifespan ─────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        get_pipeline("e")  # Spanish — primary language for Umi
        get_pipeline("a")  # English — for English responses
    except Exception as e:
        print(f"[kokoro] ERROR preloading: {e}", file=sys.stderr, flush=True)
        traceback.print_exc()
    yield

app = FastAPI(title="Kokoro TTS Sidecar", lifespan=lifespan)

class GenerateRequest(BaseModel):
    text: str
    voice: Optional[str] = None
    speed: Optional[float] = None
    language: Optional[str] = None  # ISO code: "es", "en", or raw lang_code: "a", "e"

@app.get("/health")
async def health():
    return {"status": "ok" if _pipelines else "loading", "languages": list(_pipelines.keys())}

@app.post("/generate")
async def generate(req: GenerateRequest):
    if not req.text or not req.text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    lang_code = LANG_MAP.get(req.language or "e", "e")
    pipeline = get_pipeline(lang_code)
    voice = req.voice or VOICE_DEFAULTS.get(lang_code, "ef_dora")
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
        print(f"[kokoro] Generated in {gen_time:.2f}s (lang={lang_code}, voice={voice}, speed={speed})", file=sys.stderr, flush=True)

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
