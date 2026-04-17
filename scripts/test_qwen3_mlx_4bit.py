#!/usr/bin/env python3
"""
Qwen3-TTS MLX 4-bit Benchmark - Máxima velocidad
Comparativa: 8-bit vs 4-bit
"""

import time
import os
import shutil
from pathlib import Path

from mlx_audio.tts.utils import load_model
from mlx_audio.tts.generate import generate_audio
import soundfile as sf

# Config
REF_AUDIO = "/Users/testnico/Documents/GitHub/nicobot/exemple/voice_preview_cristina - empathetic customer support.mp3"
REF_TEXT = "Soy Cristina, la voz perfecta para automatizar tu atención al cliente, ventas u operaciones. ¿En qué puedo ayudarte?"
OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/qwen3-mlx-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Modelos a comparar
MODELS = {
    "8-bit": "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
    "6-bit": "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-6bit",
    "4-bit": "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit",
}

# Frases de test (incluyendo largas)
TEST_PHRASES = [
    ("Hola Nico.", "greeting"),
    ("Hola Nico, soy tu asistente.", "intro"),
    ("He encontrado tres archivos en tu sistema. ¿Quieres que los procese?", "status"),
    (
        "Estoy buscando información en tus documentos. Esto puede tomar unos momentos porque necesito revisar cada archivo cuidadosamente.",
        "long",
    ),
]

print("=" * 80)
print("Qwen3-TTS MLX Benchmark: 8-bit vs 6-bit vs 4-bit")
print("=" * 80)
print("Goal: Encontrar el modelo más rápido sin reventar la RAM")
print("=" * 80)

results = {}

for model_name, model_id in MODELS.items():
    print(f"\n\n{'=' * 80}")
    print(f"Modelo: {model_name}")
    print(f"ID: {model_id}")
    print("=" * 80)

    try:
        # Cargar modelo
        print("\n1. Cargando modelo...")
        t0 = time.time()
        model = load_model(model_id)
        load_time = time.time() - t0
        print(f"   ✓ Cargado en {load_time:.2f}s")

        model_results = []

        # Test cada frase
        for text, label in TEST_PHRASES:
            print(f"\n   [{label}] '{text[:50]}...'")

            temp_dir = OUTPUT_DIR / f"temp_{model_name}_{label}_{int(time.time())}"
            temp_dir.mkdir(exist_ok=True)

            t0 = time.time()
            generate_audio(
                model=model,
                text=text,
                language="Spanish",
                ref_audio=REF_AUDIO,
                ref_text=REF_TEXT,  # Pre-computado para no perder tiempo
                output_path=str(temp_dir),
            )
            gen_time = time.time() - t0

            # Medir duración
            audio_files = list(temp_dir.glob("*.wav"))
            if audio_files:
                data, sr = sf.read(audio_files[0])
                audio_duration = len(data) / sr
                rtf = gen_time / audio_duration

                model_results.append(
                    {
                        "label": label,
                        "text": text[:40],
                        "gen_time": gen_time,
                        "audio_duration": audio_duration,
                        "rtf": rtf,
                    }
                )

                print(
                    f"      ⏱️  {gen_time:.2f}s | 🎵 {audio_duration:.2f}s | 📊 RTF: {rtf:.2f}x"
                )

                # Guardar muestra
                if label == "status":
                    final_path = OUTPUT_DIR / f"{model_name}_{label}_cristina.wav"
                    shutil.copy(audio_files[0], final_path)

            # Cleanup
            shutil.rmtree(temp_dir, ignore_errors=True)

        results[model_name] = model_results

        # Liberar memoria
        del model
        import mlx.core as mx

        mx.clear_cache()

    except Exception as e:
        print(f"   ❌ Error: {e}")
        results[model_name] = []

# Resumen comparativo
print("\n\n" + "=" * 80)
print("RESUMEN COMPARATIVO")
print("=" * 80)

print(f"\n{'Frase':<45} {'8-bit':>10} {'6-bit':>10} {'4-bit':>10}")
print("-" * 80)

for i, (text, label) in enumerate(TEST_PHRASES):
    short_text = text[:42] + "..." if len(text) > 45 else text
    rtf_8 = (
        results.get("8-bit", [])[i]["rtf"] if i < len(results.get("8-bit", [])) else "-"
    )
    rtf_6 = (
        results.get("6-bit", [])[i]["rtf"] if i < len(results.get("6-bit", [])) else "-"
    )
    rtf_4 = (
        results.get("4-bit", [])[i]["rtf"] if i < len(results.get("4-bit", [])) else "-"
    )

    print(f"{short_text:<45} {str(rtf_8):>10} {str(rtf_6):>10} {str(rtf_4):>10}")

print("-" * 80)
print("\nMenor RTF = Mejor (más rápido que tiempo real)")
print("\n✅ Test completado!")
