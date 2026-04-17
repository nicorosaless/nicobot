#!/usr/bin/env python3
"""
Parler TTS Test - Voz femenina española (Olivia)
Alternativa a Piper con mejor calidad
"""

import time
import sys
from pathlib import Path
import soundfile as sf
import torch

OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/parler-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

TEST_PHRASES = [
    ("Hola Nico.", "greeting"),
    ("¿Cómo estás?", "howareyou"),
    ("He encontrado tres archivos.", "status"),
]

print("=" * 80)
print("PARLER TTS TEST - Voz Olivia (español de España)")
print("=" * 80)
print("\n🇪🇸 Probando voz femenina española con Parler TTS")
print("🎙️  Speaker: Olivia (48,489 muestras de entrenamiento)")
print("📊 Modelo: parler-tts-mini-multilingual-v1.1 (0.9B params)\n")

# Verificar/instalar dependencias
try:
    from parler_tts import ParlerTTSForConditionalGeneration
    from transformers import AutoTokenizer
except ImportError:
    print("❌ Parler TTS no instalado.")
    print("📦 Instalando...")
    import subprocess

    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "-q",
            "git+https://github.com/huggingface/parler-tts.git",
        ],
        check=True,
    )
    from parler_tts import ParlerTTSForConditionalGeneration
    from transformers import AutoTokenizer

# Cargar modelo
print("🔄 Cargando modelo...")
device = "mps" if torch.backends.mps.is_available() else "cpu"
print(f"   Dispositivo: {device}")

model = ParlerTTSForConditionalGeneration.from_pretrained(
    "parler-tts/parler-tts-mini-multilingual-v1.1"
).to(device)

tokenizer = AutoTokenizer.from_pretrained(
    "parler-tts/parler-tts-mini-multilingual-v1.1"
)
description_tokenizer = AutoTokenizer.from_pretrained(
    model.config.text_encoder._name_or_path
)

print("✅ Modelo cargado\n")

results = []

# Probar diferentes descripciones de voz femenina
descriptions = [
    "Olivia's voice is clear and natural, delivering speech at a moderate pace with a warm tone.",
    "A female speaker delivers a slightly expressive and animated speech with a moderate speed and pitch. The recording is of very high quality, with the speaker's voice sounding clear and very close up.",
]

for desc_idx, description in enumerate(descriptions):
    print(f"\n{'=' * 80}")
    print(f"DESCRIPCIÓN DE VOZ #{desc_idx + 1}")
    print(f"{'=' * 80}")
    print(f'"{description[:70]}..."')

    for text, label in TEST_PHRASES:
        print(f"\n   [{label}] '{text[:30]}...' ", end="", flush=True)

        try:
            t0 = time.time()

            # Preparar inputs
            input_ids = description_tokenizer(
                description, return_tensors="pt"
            ).input_ids.to(device)
            prompt_input_ids = tokenizer(text, return_tensors="pt").input_ids.to(device)

            # Generar
            generation = model.generate(
                input_ids=input_ids,
                prompt_input_ids=prompt_input_ids,
                max_new_tokens=1000,
            )

            gen_time = time.time() - t0

            # Guardar
            audio_arr = generation.cpu().numpy().squeeze()
            output_file = OUTPUT_DIR / f"parler_olivia_desc{desc_idx}_{label}.wav"
            sf.write(str(output_file), audio_arr, model.config.sampling_rate)

            # Calcular métricas
            duration = len(audio_arr) / model.config.sampling_rate
            rtf = gen_time / duration

            print(f"✓ RTF: {rtf:.3f}x ({gen_time:.1f}s / {duration:.1f}s)")

            results.append(
                {
                    "desc": f"Desc {desc_idx + 1}",
                    "label": label,
                    "rtf": rtf,
                    "gen_time": gen_time,
                    "duration": duration,
                    "file": str(output_file),
                }
            )

        except Exception as e:
            print(f"❌ Error: {e}")

# Resumen
print("\n" + "=" * 80)
print("RESULTADOS - PARLER TTS (Olivia)")
print("=" * 80)

if results:
    print(f"\n{'Descripción':<15} {'Frase':<15} {'RTF':<8} {'Tiempo':<10} {'Duración'}")
    print("-" * 70)

    for r in results:
        print(
            f"{r['desc']:<15} {r['label']:<15} {r['rtf']:<8.3f} {r['gen_time']:<10.1f}s {r['duration']:.1f}s"
        )

    # Promedios
    from collections import defaultdict

    desc_rtfs = defaultdict(list)
    for r in results:
        desc_rtfs[r["desc"]].append(r["rtf"])

    print("\n" + "-" * 70)
    print("RTF PROMEDIO POR DESCRIPCIÓN:")
    for desc, rtfs in desc_rtfs.items():
        avg = sum(rtfs) / len(rtfs)
        print(f"  {desc}: {avg:.3f}x")

print("\n" + "=" * 80)
print("ARCHIVOS GENERADOS")
print("=" * 80)
wav_files = sorted(OUTPUT_DIR.glob("*.wav"))
if wav_files:
    print(f"✅ {len(wav_files)} archivos en: {OUTPUT_DIR}")
    for f in wav_files:
        size = f.stat().st_size / 1024
        print(f"  • {f.name:<50} {size:>6.1f} KB")
else:
    print("❌ No se generaron archivos")

print("\n" + "=" * 80)
print("ANÁLISIS - PARLER TTS VS PIPER")
print("=" * 80)
print("""
🎯 COMPARACIÓN:

┌────────────────┬─────────────────┬─────────────────┐
│                │ Parler TTS      │ Piper           │
├────────────────┼─────────────────┼─────────────────┤
│ Modelo         │ 0.9B params     │ ONNX (ligero)   │
│ Calidad        │ ⭐⭐⭐ Alta       │ ⭐⭐ Básica       │
│ Velocidad      │ RTF ~0.5-2x     │ RTF ~0.1-0.5x   │
│ Voz ES         │ Olivia (fem)    │ mls_10246, etc. │
│ Acento         │ Español España  │ Español España  │
│ Control        │ Descripción     │ Fija            │
└────────────────┴─────────────────┴─────────────────┘

✅ VENTAJAS DE PARLER TTS:
   • Mejor calidad de audio que Piper
   • Control mediante descripción de voz
   • Speaker específica "Olivia" entrenada con 48k muestras
   • Modelo más moderno (multilingual v1.1)

⚠️ DESVENTAJAS:
   • Más lento que Piper
   • Requiere más memoria (0.9B params)
   • Primera generación tarda en cargar el modelo

💡 RECOMENDACIÓN:

Si Olivia suena bien:
┌──────────────────────────────────────────────────────────────┐
│ FRASES CORTAS (< 5 palabras)                                 │
│ • Parler TTS con Olivia (mejor calidad que Piper)           │
│ • Aceptar RTF ~0.5-1x (sigue siendo rápido)                 │
├──────────────────────────────────────────────────────────────┤
│ FRASES LARGAS                                                │
│ • Qwen3-TTS MLX (Cristina clonada)                          │
│ • RTF ~0.7-1.2x                                             │
└──────────────────────────────────────────────────────────────┘

Si Olivia NO suena bien:
• Buscar otras speakers en español
• Probar Fish Speech (más complejo pero mejor calidad)
• Considerar usar solo Qwen3-TTS para todo (más lento pero calidad garantizada)
""")

print(f"\n✅ Test completado.")
print(f"🎧 Archivos en: {OUTPUT_DIR}")
print(f"\n🎵 Escucha los archivos 'parler_olivia_desc*_greeting.wav'")
print(f"   y dime si Olivia tiene la calidad que buscas.")
