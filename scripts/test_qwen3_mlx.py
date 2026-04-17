#!/usr/bin/env python3
"""
Qwen3-TTS MLX Benchmark - Optimizado para Apple Silicon
Prueba de velocidad con MLX nativo (no PyTorch MPS)
"""

import time
import os
import sys
from pathlib import Path

# Añadir el venv al path si es necesario
# sys.path.insert(0, "/Users/testnico/Documents/GitHub/nicobot/artifacts/qwen3-mlx-venv/lib/python3.12/site-packages")

from mlx_audio.tts.utils import load_model
from mlx_audio.tts.generate import generate_audio
import soundfile as sf

# Config
REF_AUDIO = "/Users/testnico/Documents/GitHub/nicobot/exemple/voice_preview_cristina - empathetic customer support.mp3"
OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/qwen3-mlx-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Descargar modelo 0.6B Base (más rápido) - 8bit cuantizado
MODEL_NAME = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"

print("=" * 70)
print("Qwen3-TTS MLX Benchmark - Apple Silicon Optimizado")
print("=" * 70)
print(f"Modelo: {MODEL_NAME}")
print(f"Dispositivo: Apple Silicon (MLX GPU)")
print("-" * 70)

# Cargar modelo
print("\n1. Cargando modelo...")
t0 = time.time()
model = load_model(MODEL_NAME)
load_time = time.time() - t0
print(f"   ✓ Modelo cargado en {load_time:.2f}s")

# Test frases
test_phrases = [
    ("Hola Nico.", "greeting"),
    ("Hola Nico, soy tu asistente.", "intro"),
    ("Hola Nico, soy tu asistente de voz. Estoy aquí para ayudarte.", "short"),
    ("He encontrado tres archivos en tu sistema. ¿Quieres que los procese?", "status"),
]

print("\n2. Benchmark de velocidad (Voice Clone)")
print("-" * 70)

results = []

for text, label in test_phrases:
    print(f"\n   [{label}] '{text[:40]}...'")

    # Generar
    temp_dir = OUTPUT_DIR / f"temp_{label}_{int(time.time())}"
    temp_dir.mkdir(exist_ok=True)

    t0 = time.time()
    generate_audio(
        model=model,
        text=text,
        language="Spanish",
        ref_audio=REF_AUDIO,
        ref_text="",  # x_vector only mode
        output_path=str(temp_dir),
    )
    gen_time = time.time() - t0

    # Medir duración del audio generado
    audio_files = list(temp_dir.glob("*.wav"))
    if audio_files:
        audio_path = audio_files[0]
        data, sr = sf.read(audio_path)
        audio_duration = len(data) / sr
        rtf = gen_time / audio_duration

        # Mover a output final
        final_path = OUTPUT_DIR / f"{label}_cristina.wav"
        os.rename(audio_path, final_path)

        results.append((label, text, gen_time, audio_duration, rtf))
        print(
            f"      Tiempo: {gen_time:.2f}s | Audio: {audio_duration:.2f}s | RTF: {rtf:.2f}x"
        )

        # Cleanup
        import shutil

        shutil.rmtree(temp_dir, ignore_errors=True)

print("\n" + "=" * 70)
print("RESUMEN DE RESULTADOS")
print("=" * 70)
print(f"{'Texto':<30} {'Generación':<12} {'Audio':<8} {'RTF':<8}")
print("-" * 70)
for label, text, gen_time, audio_dur, rtf in results:
    short_text = text[:27] + "..." if len(text) > 30 else text
    print(f"{short_text:<30} {gen_time:>6.2f}s      {audio_dur:>5.2f}s   {rtf:>6.2f}x")

print("-" * 70)
avg_rtf = sum(r[4] for r in results) / len(results)
print(f"RTF Promedio: {avg_rtf:.2f}x")

print("\n" + "=" * 70)
print("INTERPRETACIÓN:")
print("-" * 70)
if avg_rtf < 1.0:
    print("✅ RTF < 1.0: Más rápido que tiempo real - ¡PERFECTO!")
elif avg_rtf < 2.0:
    print("✅ RTF 1-2x: Aceptable para interacción en tiempo real")
elif avg_rtf < 4.0:
    print("⚠️  RTF 2-4x: Usable pero con delay notable")
else:
    print("❌ RTF > 4x: Muy lento para uso conversacional")

print("\n" + "=" * 70)
print("COMPARATIVA MLX vs PyTorch:")
print("-" * 70)
print("PyTorch CPU: RTF ~5-7x (observado anteriormente)")
print("PyTorch MPS: RTF ~12x (más lento que CPU)")
print(f"MLX Native:  RTF ~{avg_rtf:.2f}x (este test)")
print("=" * 70)
print("\n✅ Test completado. Archivos guardados en:", OUTPUT_DIR)
