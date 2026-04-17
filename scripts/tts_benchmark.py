#!/usr/bin/env python3
"""Simple local TTS tester.

Edit only these values:
- TEXT_TO_GENERATE: text to synthesize
- ENGINE_CHOICE: 1, 2 or 3

Engines:
1 = kokoro
2 = melotts
3 = piper
4 = cosyvoice2_zero_shot

Output:
- Writes one WAV file to artifacts/tts-benchmark/simple/
"""

from __future__ import annotations

import datetime as dt
import sys
import wave
from pathlib import Path


# -----------------------------
# CHANGE ONLY THESE TWO LINES
# -----------------------------
TEXT_TO_GENERATE = "Hola, esta es una prueba de texto a voz para NicoBot."
ENGINE_CHOICE = 1  # 1=kokoro, 2=melotts, 3=piper, 4=cosyvoice2_zero_shot


# -----------------------------
# Optional defaults (only touch if needed)
# -----------------------------
KOKORO_LANG_CODE = "e"
KOKORO_VOICE = "ef_dora"

MELO_LANGUAGE = "ES"
MELO_SPEAKER = "ES"

# IMPORTANT: Set this path if you choose ENGINE_CHOICE = 3
PIPER_MODEL_PATH = ""

# IMPORTANT: Set these if you choose ENGINE_CHOICE = 4
COSYVOICE_MODEL_DIR = ""
COSYVOICE_PROMPT_WAV = ""
COSYVOICE_PROMPT_TEXT = ""


def output_path(engine_name: str) -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path("artifacts/tts-benchmark/simple")
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir / f"{engine_name}_{ts}.wav"


def run_kokoro(text: str) -> Path:
    try:
        import numpy as np
        import soundfile as sf
        from kokoro import KPipeline
    except Exception as exc:
        raise RuntimeError(
            "Kokoro dependencies not installed. Install with: "
            "pip install kokoro soundfile"
        ) from exc

    pipeline = KPipeline(lang_code=KOKORO_LANG_CODE)
    chunks = []
    for _, _, audio in pipeline(text, voice=KOKORO_VOICE, speed=1.0):
        chunks.append(audio)

    if not chunks:
        raise RuntimeError("Kokoro produced no audio")

    audio_concat = np.concatenate(chunks)
    sample_rate = 24000
    out = output_path("kokoro")
    sf.write(out, audio_concat, sample_rate)
    return out


def run_melotts(text: str) -> Path:
    try:
        from melo.api import TTS as MeloTTS
    except Exception as exc:
        raise RuntimeError(
            "MeloTTS dependencies not installed. Install with: pip install git+https://github.com/myshell-ai/MeloTTS.git"
        ) from exc

    model = MeloTTS(language=MELO_LANGUAGE, device="auto")
    speaker_ids = model.hps.data.spk2id
    if MELO_SPEAKER not in speaker_ids:
        raise RuntimeError(
            f"Melo speaker '{MELO_SPEAKER}' not found. Available: {sorted(speaker_ids.keys())}"
        )

    out = output_path("melotts")
    model.tts_to_file(text, speaker_ids[MELO_SPEAKER], str(out), speed=1.0)
    return out


def run_piper(text: str) -> Path:
    if not PIPER_MODEL_PATH.strip():
        raise RuntimeError(
            "PIPER_MODEL_PATH is empty. Set it in scripts/tts_benchmark.py before using ENGINE_CHOICE = 3"
        )

    model_path = Path(PIPER_MODEL_PATH).expanduser().resolve()
    if not model_path.exists():
        raise RuntimeError(f"Piper model not found: {model_path}")

    try:
        from piper import PiperVoice, SynthesisConfig
    except Exception as exc:
        raise RuntimeError(
            "Piper dependencies not installed. Install with: pip install piper-tts"
        ) from exc

    voice = PiperVoice.load(str(model_path))
    config = SynthesisConfig(length_scale=1.0, noise_scale=0.667, noise_w_scale=0.8)
    out = output_path("piper")

    with wave.open(str(out), "wb") as wav:
        wrote_header = False
        for chunk in voice.synthesize(text, syn_config=config):
            if not wrote_header:
                wav.setnchannels(chunk.sample_channels)
                wav.setsampwidth(chunk.sample_width)
                wav.setframerate(chunk.sample_rate)
                wrote_header = True
            wav.writeframesraw(chunk.audio_int16_bytes)

    if out.stat().st_size == 0:
        raise RuntimeError("Piper produced empty WAV")
    return out


def run_cosyvoice(text: str) -> Path:
    if not COSYVOICE_MODEL_DIR.strip():
        raise RuntimeError(
            "COSYVOICE_MODEL_DIR is empty. Set it in scripts/tts_benchmark.py before using ENGINE_CHOICE = 4"
        )
    if not COSYVOICE_PROMPT_WAV.strip():
        raise RuntimeError(
            "COSYVOICE_PROMPT_WAV is empty. Set it in scripts/tts_benchmark.py before using ENGINE_CHOICE = 4"
        )
    if not COSYVOICE_PROMPT_TEXT.strip():
        raise RuntimeError(
            "COSYVOICE_PROMPT_TEXT is empty. Set it in scripts/tts_benchmark.py before using ENGINE_CHOICE = 4"
        )

    model_dir = Path(COSYVOICE_MODEL_DIR).expanduser().resolve()
    if not model_dir.exists():
        raise RuntimeError(f"CosyVoice model dir not found: {model_dir}")

    prompt_wav = Path(COSYVOICE_PROMPT_WAV).expanduser().resolve()
    if not prompt_wav.exists():
        raise RuntimeError(f"CosyVoice prompt wav not found: {prompt_wav}")

    try:
        import torchaudio
        from cosyvoice.cli.cosyvoice import AutoModel
    except Exception as exc:
        raise RuntimeError(
            "CosyVoice dependencies not installed in current env. Install CosyVoice and its requirements first."
        ) from exc

    model = AutoModel(model_dir=str(model_dir))
    out = output_path("cosyvoice2")
    wrote = False
    for item in model.inference_zero_shot(
        text,
        COSYVOICE_PROMPT_TEXT,
        str(prompt_wav),
        stream=False,
    ):
        torchaudio.save(str(out), item["tts_speech"], model.sample_rate)
        wrote = True
        break

    if not wrote or not out.exists() or out.stat().st_size == 0:
        raise RuntimeError("CosyVoice produced no audio")
    return out


def main() -> int:
    if ENGINE_CHOICE not in (1, 2, 3, 4):
        print("ENGINE_CHOICE must be 1, 2, 3 or 4")
        return 1

    text = TEXT_TO_GENERATE.strip()
    if not text:
        print("TEXT_TO_GENERATE is empty")
        return 1

    try:
        if ENGINE_CHOICE == 1:
            out = run_kokoro(text)
            engine = "kokoro"
        elif ENGINE_CHOICE == 2:
            out = run_melotts(text)
            engine = "melotts"
        elif ENGINE_CHOICE == 3:
            out = run_piper(text)
            engine = "piper"
        else:
            out = run_cosyvoice(text)
            engine = "cosyvoice2"

        print(f"OK: {engine} generated WAV")
        print(f"File: {out}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
