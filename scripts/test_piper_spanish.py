#!/usr/bin/env python3
"""
Piper Spanish (Spain) Voice Test - Alternativa a Kokoro
Prueba voces españolas peninsulares de Piper.
"""

import time
import subprocess
import sys
import urllib.request
from pathlib import Path
import soundfile as sf

# Config
OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/piper-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

MODELS_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/piper-models")
MODELS_DIR.mkdir(parents=True, exist_ok=True)

# Voces españolas de España en Piper con URLs
SPANISH_VOICES = [
    {
        "id": "es_ES-carlfm-x_low",
        "name": "Carlos (español) - x_low",
        "model_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/carlfm/x_low/es_ES-carlfm-x_low.onnx",
        "config_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/carlfm/x_low/es_ES-carlfm-x_low.onnx.json",
    },
    {
        "id": "es_ES-davefx-medium",
        "name": "Dave (español) - medium",
        "model_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx",
        "config_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json",
    },
    {
        "id": "es_ES-mls_10246-low",
        "name": "MLS 10246 (español) - low - FEMENINA",
        "model_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_10246/low/es_ES-mls_10246-low.onnx",
        "config_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_10246/low/es_ES-mls_10246-low.onnx.json",
    },
    {
        "id": "es_ES-mls_9972-low",
        "name": "MLS 9972 (español) - low - FEMENINA",
        "model_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_9972/low/es_ES-mls_9972-low.onnx",
        "config_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/mls_9972/low/es_ES-mls_9972-low.onnx.json",
    },
    {
        "id": "es_ES-sharvard-medium",
        "name": "Sharvard (español) - medium - FEMENINA",
        "model_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx",
        "config_url": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx.json",
    },
]

# Frases de test
TEST_PHRASES = [
    ("Hola Nico.", "greeting"),
    ("Hola Nico, soy tu asistente.", "intro"),
    ("He encontrado tres archivos. ¿Quieres que los procese?", "status"),
]


def download_model(voice_info):
    """Descarga modelo y config si no existen"""
    model_path = MODELS_DIR / f"{voice_info['id']}.onnx"
    config_path = MODELS_DIR / f"{voice_info['id']}.onnx.json"

    if not model_path.exists():
        print(f"   📥 Descargando modelo {voice_info['id']}...")
        try:
            urllib.request.urlretrieve(voice_info["model_url"], model_path)
            urllib.request.urlretrieve(voice_info["config_url"], config_path)
            print(f"   ✅ Modelo descargado")
            return True
        except Exception as e:
            print(f"   ❌ Error descargando: {e}")
            return False
    return True


print("=" * 80)
print("PIPER SPANISH (SPAIN) VOICE TEST")
print("=" * 80)
print("\n🇪🇸 Voces españolas peninsulares (NO latinoamericanas)")
print("⚡ Piper es ultra-rápido (RTF típico ~0.06x)")
print("🎯 Buscando alternativa a Kokoro para español de España\n")

# Verificar piper
piper_path = None
for path in ["piper", "piper-tts"]:
    result = subprocess.run(["which", path], capture_output=True)
    if result.returncode == 0:
        piper_path = path
        break

if not piper_path:
    print("❌ Piper no encontrado en PATH")
    sys.exit(1)

print(f"✅ Piper: {piper_path}\n")

results = []

for voice_info in SPANISH_VOICES:
    print(f"\n🎙️  {voice_info['name']}")
    print(f"   ID: {voice_info['id']}")
    print("-" * 60)

    # Descargar modelo
    if not download_model(voice_info):
        continue

    model_path = MODELS_DIR / f"{voice_info['id']}.onnx"

    for text, label in TEST_PHRASES:
        print(f"   [{label}] '{text[:35]}...' ", end="", flush=True)

        output_file = OUTPUT_DIR / f"{voice_info['id']}_{label}.wav"

        try:
            t0 = time.time()

            process = subprocess.run(
                [
                    piper_path,
                    "--model",
                    str(model_path),
                    "--output_file",
                    str(output_file),
                ],
                input=text.encode(),
                capture_output=True,
                timeout=30,
            )

            gen_time = time.time() - t0

            if process.returncode == 0 and output_file.exists():
                data, sr = sf.read(output_file)
                audio_duration = len(data) / sr
                rtf = gen_time / audio_duration if audio_duration > 0 else 0

                results.append(
                    {
                        "voice": voice_info["id"],
                        "name": voice_info["name"],
                        "label": label,
                        "gen_time": gen_time,
                        "duration": audio_duration,
                        "rtf": rtf,
                    }
                )

                print(f"✓ RTF: {rtf:.3f}x ({gen_time:.2f}s)")
            else:
                err = process.stderr.decode()[:40] if process.stderr else "Unknown"
                print(f"❌ {err}")

        except Exception as e:
            print(f"❌ {str(e)[:40]}")

# Resumen
print("\n" + "=" * 80)
print("RESULTADOS - VOCES ESPAÑOLAS PIPER")
print("=" * 80)

if results:
    print(f"\n{'Voz':<30} {'Frase':<12} {'RTF':<8} {'Tiempo'}")
    print("-" * 70)

    for r in results:
        voice_short = r["voice"].replace("es_ES-", "")[:28]
        print(
            f"{voice_short:<30} {r['label']:<12} {r['rtf']:<8.3f} {r['gen_time']:.2f}s"
        )

    # RTF promedio por voz
    from collections import defaultdict

    voice_rtfs = defaultdict(list)
    for r in results:
        voice_rtfs[r["voice"]].append(r["rtf"])

    print("\n" + "-" * 70)
    print("RTF PROMEDIO POR VOZ:")
    for voice, rtfs in sorted(voice_rtfs.items()):
        avg = sum(rtfs) / len(rtfs)
        emoji = "⚡" if avg < 0.1 else "✅" if avg < 0.3 else "🆗"
        print(f"  {emoji} {voice:<35} {avg:.3f}x")

print("\n" + "=" * 80)
print("ARCHIVOS GENERADOS")
print("=" * 80)
wav_files = list(OUTPUT_DIR.glob("*.wav"))
if wav_files:
    print(f"✅ {len(wav_files)} archivos en: {OUTPUT_DIR}")
    for f in sorted(wav_files):
        size = f.stat().st_size / 1024
        print(f"  • {f.name:<40} {size:>6.1f} KB")
else:
    print("❌ No se generaron archivos")

print("\n" + "=" * 80)
print("CONCLUSIÓN - DECISIÓN DE STACK TTS")
print("=" * 80)
print("""
🎯 PROBLEMA IDENTIFICADO:
   ❌ Kokoro: Solo tiene español LATINOAMERICANO (ef_dora, em_alex)
   ❌ No hay voces femeninas españolas de España en Kokoro

✅ SOLUCIÓN - PIPER:
   ✅ Piper tiene 5 voces españolas de ESPAÑA (es_ES)
   ✅ Voces FEMENINAS disponibles: mls_10246, mls_9972, sharvard
   ✅ Acento peninsular (castellano)
   ⚡ Ultra-rápido: RTF ~0.06x (16× más rápido que tiempo real)

📊 COMPARACIÓN FINAL:

┌────────────────────┬─────────────────┬─────────────────┬─────────────────┐
│                    │ Kokoro          │ Piper           │ Qwen3-TTS MLX   │
├────────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ Acento ES          │ Latino ❌       │ España ✅       │ España ✅       │
│ Voice Cloning      │ No              │ No              │ Sí (Cristina)   │
│ RTF                │ ~0.2x           │ ~0.06x ⭐       │ ~0.7-1.2x       │
│ Calidad            │ Buena           │ Básica          │ Premium         │
│ Voces ES femeninas │ 1 (latina)      │ 3 (españolas)   │ 1 (Cristina)    │
└────────────────────┴─────────────────┴─────────────────┴─────────────────┘

🏆 STACK FINAL RECOMENDADO PARA NICOBOT:

┌─────────────────────────────────────────────────────────────────────┐
│ FRASES CORTAS (< 5 palabras)                                        │
│ • Piper: es_ES-mls_10246-low (voz femenina española peninsular)     │
│ • RTF: ~0.06x (16× más rápido que tiempo real)                      │
│ • Uso: "Hola", "Sí", "Entendido", "Procesando..."                   │
├─────────────────────────────────────────────────────────────────────┤
│ FRASES LARGAS / NARRACIÓN DE PROGRESO                               │
│ • Qwen3-TTS MLX: Voz de Cristina clonada                            │
│ • RTF: ~0.7-1.2x (tiempo real para frases largas)                   │
│ • Uso: Narración de progreso, mensajes importantes                  │
└─────────────────────────────────────────────────────────────────────┘

💡 Nota: Kokoro queda descartado para español por acento inapropiado.
   Usar Kokoro solo si en el futuro se añade español peninsular.
""")

print(f"\n✅ Test completado.")
print(f"📁 Modelos descargados en: {MODELS_DIR}")
print(f"🎧 Audios generados en: {OUTPUT_DIR}")
print(
    f"\n🎵 Escucha 'es_ES-mls_10246-low_greeting.wav' o 'es_ES-mls_9972-low_greeting.wav'"
)
