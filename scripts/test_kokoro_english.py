#!/usr/bin/env python3
"""
Kokoro English Female Voice Test - af_bella (Grade A)
Stack final: Kokoro (en) para corto + Qwen3-TTS MLX (es) para largo/clonado
"""

import time
from pathlib import Path
import soundfile as sf

OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/kokoro-en-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

TEST_PHRASES = [
    ("Hello Nico.", "greeting"),
    ("Hello Nico, I'm your assistant.", "intro"),
    ("I found three files. Do you want me to process them?", "status"),
    ("I'm searching through your documents.", "search"),
]

print("=" * 80)
print("KOKORO ENGLISH - Voz af_bella (Grade A, HH hours)")
print("=" * 80)
print("\n🇬🇧🇺🇸 Ingles americano con voz femenina premium")
print("🎙️  Voz: af_bella (calidad A, horas de entrenamiento HH)")
print("⚡ Stack: Kokoro EN (corto) + Qwen3-TTS ES MLX (largo/clonado)\n")

# Cargar Kokoro
try:
    from kokoro import KPipeline
except ImportError:
    print("❌ Kokoro no instalado")
    exit(1)

results = []

# Test af_bella (mejor voz femenina en inglés)
print("=" * 80)
print("🎙️  Voz: af_bella (American Female - Bella)")
print("   Características: Grade A, HH hours training, alta calidad")
print("=" * 80)

pipeline = KPipeline(lang_code="a")  # 'a' = American English

for text, label in TEST_PHRASES:
    print(f"\n   [{label}] '{text[:40]}...' ", end="", flush=True)

    output_file = OUTPUT_DIR / f"kokoro_af_bella_{label}.wav"

    try:
        t0 = time.time()
        generator = pipeline(text, voice="af_bella", speed=1.0)

        for i, (gs, ps, audio) in enumerate(generator):
            sf.write(str(output_file), audio, 24000)

            gen_time = time.time() - t0
            duration = len(audio) / 24000
            rtf = gen_time / duration

            results.append(
                {
                    "voice": "af_bella",
                    "label": label,
                    "text": text,
                    "rtf": rtf,
                    "gen_time": gen_time,
                    "duration": duration,
                }
            )

            print(f"✓ RTF: {rtf:.3f}x ({gen_time:.2f}s / {duration:.2f}s)")
            break

    except Exception as e:
        print(f"❌ Error: {e}")

# También probar af_heart (la otra voz grade A)
print("\n" + "=" * 80)
print("🎙️  Voz: af_heart (American Female - Heart)")
print("   Características: Grade A, voz con carácter/emo")
print("=" * 80)

for text, label in TEST_PHRASES[:2]:  # Solo 2 frases para comparar
    print(f"\n   [{label}] '{text[:40]}...' ", end="", flush=True)

    output_file = OUTPUT_DIR / f"kokoro_af_heart_{label}.wav"

    try:
        t0 = time.time()
        generator = pipeline(text, voice="af_heart", speed=1.0)

        for i, (gs, ps, audio) in enumerate(generator):
            sf.write(str(output_file), audio, 24000)

            gen_time = time.time() - t0
            duration = len(audio) / 24000
            rtf = gen_time / duration

            results.append(
                {
                    "voice": "af_heart",
                    "label": label,
                    "text": text,
                    "rtf": rtf,
                    "gen_time": gen_time,
                    "duration": duration,
                }
            )

            print(f"✓ RTF: {rtf:.3f}x ({gen_time:.2f}s / {duration:.2f}s)")
            break

    except Exception as e:
        print(f"❌ Error: {e}")

# Resumen
print("\n" + "=" * 80)
print("RESULTADOS - KOKORO ENGLISH FEMALE")
print("=" * 80)

if results:
    print(f"\n{'Voz':<15} {'Frase':<15} {'RTF':<8} {'Tiempo':<10}")
    print("-" * 60)

    for r in results:
        print(
            f"{r['voice']:<15} {r['label']:<15} {r['rtf']:<8.3f} {r['gen_time']:<10.2f}s"
        )

    # Promedios
    from collections import defaultdict

    voice_stats = defaultdict(list)
    for r in results:
        voice_stats[r["voice"]].append(r["rtf"])

    print("\n" + "-" * 60)
    print("RTF PROMEDIO:")
    for voice, rtfs in sorted(voice_stats.items()):
        avg = sum(rtfs) / len(rtfs)
        emoji = "⚡" if avg < 0.2 else "✅" if avg < 0.5 else "🆗"
        print(f"  {emoji} {voice}: {avg:.3f}x")

print("\n" + "=" * 80)
print("ARCHIVOS GENERADOS")
print("=" * 80)

wav_files = sorted(OUTPUT_DIR.glob("*.wav"))
if wav_files:
    print(f"✅ {len(wav_files)} archivos en: {OUTPUT_DIR}")
    for f in wav_files:
        size = f.stat().st_size / 1024
        print(f"  • {f.name:<45} ({size:.1f} KB)")
else:
    print("❌ No se generaron archivos")

print("\n" + "=" * 80)
print("STACK FINAL CONFIRMADO - NICOBOT")
print("=" * 80)
print("""
🎯 ESTRATEGIA:

1. OUTPUT DEL AGENTE EN INGLÉS:
   • Hermes genera respuestas en inglés
   • TTS usa voces femeninas premium de Kokoro
   • Acento: American English (natural y profesional)

2. STACK TTS HÍBRIDO:

┌─────────────────────────────────────────────────────────────────┐
│ FRASES CORTAS (< 5 palabras / 500ms)                            │
│ • Kokoro (EN): af_bella o af_heart                             │
│ • RTF: ~0.2-0.4x (3-5× más rápido que tiempo real)              │
│ • "Hello", "Yes", "Got it", "Processing..."                     │
├─────────────────────────────────────────────────────────────────┤
│ FRASES LARGAS / NARRACIÓN / PROGRESO                            │
│ • Qwen3-TTS MLX (ES): Voz de Cristina clonada                  │
│ • RTF: ~0.7-1.2x                                               │
│ • "He encontrado 3 archivos...", "Estoy procesando..."         │
│ • Narración de progreso en español con voz premium             │
└─────────────────────────────────────────────────────────────────┘

✅ VENTAJAS DE ESTE STACK:

• Kokoro (af_bella): Calidad A, voz femenina natural en inglés
• Qwen3-TTS: Voz de Cristina clonada, español nativo
• Ritmo natural: corto en EN (rápido), largo en ES (premium)
• Experiencia fluida: saludos rápidos + narración de calidad

⚡ VELOCIDADES:
• Kokoro af_bella: RTF ~0.34x (3× más rápido que tiempo real)
• Latencia cortos: ~200-400ms para "Hello", "Yes", etc.

🎧 VOCES RECOMENDADAS:
1. af_bella: Voz profesional, clara, moderada (Grade A)
2. af_heart: Voz cálida, expresiva, cercana (Grade A)

💡 Elección recomendada: af_bella para respuestas rápidas claras
""")

print(f"\n✅ Test completado.")
print(f"🎧 Archivos en: {OUTPUT_DIR}")
print(f"\n🎵 Escucha 'kokoro_af_bella_greeting.wav' y 'kokoro_af_heart_greeting.wav'")
print(f"   y elige la voz que prefieras para NicoBot.")
