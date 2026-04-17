#!/usr/bin/env python3
"""
Qwen3-TTS Voice Clone Test: Cristina (EN) → Spanish
"""

import torch
import soundfile as sf
from pathlib import Path
from qwen_tts import Qwen3TTSModel

# Paths
REF_AUDIO = "/Users/testnico/Documents/GitHub/nicobot/exemple/voice_preview_cristina - empathetic customer support.mp3"
OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/qwen3-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Primero necesitamos la transcripción del audio de referencia
# Como no la tenemos exacta, usamos x_vector_only_mode=True
# que solo usa el embedding de speaker sin necesitar ref_text

print("=" * 60)
print("Qwen3-TTS Voice Clone: Cristina (EN) → Spanish")
print("=" * 60)

# Cargar modelo Base (para voice clone)
print("\n1. Cargando modelo Qwen3-TTS-12Hz-0.6B-Base...")
model = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-0.6B-Base",  # Versión más ligera para pruebas
    device_map="cpu",  # Usar CPU (o "cuda:0" si hay GPU)
    dtype=torch.float32,  # float32 para CPU
)
print("   Modelo cargado.")

# Test 1: Voice Clone con x_vector_only_mode (sin transcripción)
print("\n2. Generando voice clone (x_vector_only_mode)...")
text_spanish = "Hola Nico, soy tu asistente de voz. Estoy aquí para ayudarte con cualquier tarea que necesites. Hablo español correctamente sin acento extranjero."

try:
    wavs, sr = model.generate_voice_clone(
        text=text_spanish,
        language="Spanish",
        ref_audio=REF_AUDIO,
        x_vector_only_mode=True,  # No necesita ref_text
        max_new_tokens=2048,
    )
    output_file = OUTPUT_DIR / "cristina_es_xvector_only.wav"
    sf.write(str(output_file), wavs[0], sr)
    print(f"   ✓ Generado: {output_file}")
except Exception as e:
    print(f"   ✗ Error: {e}")

# Test 2: Voice Clone con transcripción (mejor calidad)
# Usamos una transcripción aproximada basada en "empathetic customer support"
print("\n3. Generando voice clone (con ref_text aproximada)...")
ref_text_approx = "Hi, I'm Cristina. I'm here to help you with your customer support needs. How can I assist you today?"

try:
    wavs, sr = model.generate_voice_clone(
        text=text_spanish,
        language="Spanish",
        ref_audio=REF_AUDIO,
        ref_text=ref_text_approx,  # Transcripción aproximada
        x_vector_only_mode=False,
        max_new_tokens=2048,
    )
    output_file = OUTPUT_DIR / "cristina_es_with_reftext.wav"
    sf.write(str(output_file), wavs[0], sr)
    print(f"   ✓ Generado: {output_file}")
except Exception as e:
    print(f"   ✗ Error: {e}")

# Test 3: También probar con el modelo más grande si hay recursos
print("\n4. Prueba completada.")
print(f"\nArchivos generados en: {OUTPUT_DIR}")
print("\nNota: Si el español tiene acento inglés, la solución es:")
print("  1. Crear dataset en español con Voice Design")
print("  2. Hacer fine-tuning del modelo Base")
print("  3. O usar referencia de audio en español nativo")
