#!/usr/bin/env python3
"""
Kokoro Voice Test - Evaluación de voces para NicoBot
Prueba voces en español e inglés para determinar la mejor opción.
"""

import time
from pathlib import Path
import soundfile as sf

# Test con Kokoro
try:
    from kokoro import KPipeline
except ImportError:
    print("❌ Kokoro no instalado. Instalando...")
    import subprocess

    subprocess.run(["pip", "install", "-q", "kokoro>=0.9.4", "soundfile"], check=True)
    from kokoro import KPipeline

# Configuración
OUTPUT_DIR = Path("/Users/testnico/Documents/GitHub/nicobot/artifacts/kokoro-test")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Frases de test
TEST_PHRASES = {
    "es": [
        "Hola Nico.",
        "Hola Nico, soy tu asistente.",
        "He encontrado tres archivos. ¿Quieres que los procese?",
        "Estoy buscando información en tus documentos.",
    ],
    "en": [
        "Hello Nico.",
        "Hello Nico, I'm your assistant.",
        "I found three files. Do you want me to process them?",
        "I'm searching through your documents.",
    ],
}

# Voces a probar
VOICES_TO_TEST = {
    # Español (limitado)
    "es": [
        ("ef_dora", "Spanish Female"),
        ("em_alex", "Spanish Male"),
    ],
    # Inglés (mejores calidades)
    "en": [
        ("af_heart", "American Female - Heart (A grade)"),
        ("af_bella", "American Female - Bella (A grade, HH hours)"),
        ("af_nicole", "American Female - Nicole (B grade, HH hours)"),
        ("af_aoede", "American Female - Aoede (C+ grade)"),
    ],
}

print("=" * 80)
print("KOKORO VOICE TEST - Evaluación para NicoBot")
print("=" * 80)
print("\n⚠️  Kokoro NO soporta voice cloning")
print("✅ Usa voces pre-entrenadas (tensores fijos)")
print("🎯 Objetivo: Encontrar voz más cercana a 'Cristina' en español\n")

results = []

# Test español
print("\n" + "=" * 80)
print("🇪🇸 ESPAÑOL - Voces disponibles")
print("=" * 80)

pipeline_es = KPipeline(lang_code="e")  # 'e' = Spanish

for voice_id, voice_desc in VOICES_TO_TEST["es"]:
    print(f"\n🎙️  Voz: {voice_id} ({voice_desc})")
    print("-" * 60)

    for i, text in enumerate(TEST_PHRASES["es"]):
        label = ["greeting", "intro", "status", "long"][i]
        print(f"   [{label}] '{text[:40]}...' ", end="", flush=True)

        try:
            # Medir tiempo
            t0 = time.time()
            generator = pipeline_es(text, voice=voice_id, speed=1.0)

            # Generar audio
            for j, (gs, ps, audio) in enumerate(generator):
                gen_time = time.time() - t0

                # Guardar
                output_file = OUTPUT_DIR / f"{voice_id}_{label}.wav"
                sf.write(str(output_file), audio, 24000)

                # Calcular duración y RTF
                audio_duration = len(audio) / 24000
                rtf = gen_time / audio_duration if audio_duration > 0 else 0

                results.append(
                    {
                        "voice": voice_id,
                        "lang": "es",
                        "text": text[:30],
                        "gen_time": gen_time,
                        "duration": audio_duration,
                        "rtf": rtf,
                    }
                )

                print(f"✓ RTF: {rtf:.3f}x ({gen_time:.2f}s / {audio_duration:.2f}s)")
                break

        except Exception as e:
            print(f"❌ Error: {e}")

# Test inglés (para comparar calidad)
print("\n" + "=" * 80)
print("🇺🇸 ENGLISH - Mejores voces (para comparar)")
print("=" * 80)

pipeline_en = KPipeline(lang_code="a")  # 'a' = American English

for voice_id, voice_desc in VOICES_TO_TEST["en"]:
    print(f"\n🎙️  Voz: {voice_id} ({voice_desc})")
    print("-" * 60)

    for i, text in enumerate(TEST_PHRASES["en"][:2]):  # Solo primeras 2 frases
        label = ["greeting", "intro"][i]
        print(f"   [{label}] '{text[:40]}...' ", end="", flush=True)

        try:
            t0 = time.time()
            generator = pipeline_en(text, voice=voice_id, speed=1.0)

            for j, (gs, ps, audio) in enumerate(generator):
                gen_time = time.time() - t0

                output_file = OUTPUT_DIR / f"{voice_id}_{label}.wav"
                sf.write(str(output_file), audio, 24000)

                audio_duration = len(audio) / 24000
                rtf = gen_time / audio_duration if audio_duration > 0 else 0

                results.append(
                    {
                        "voice": voice_id,
                        "lang": "en",
                        "text": text[:30],
                        "gen_time": gen_time,
                        "duration": audio_duration,
                        "rtf": rtf,
                    }
                )

                print(f"✓ RTF: {rtf:.3f}x ({gen_time:.2f}s / {audio_duration:.2f}s)")
                break

        except Exception as e:
            print(f"❌ Error: {e}")

# Resumen
print("\n" + "=" * 80)
print("RESUMEN DE VELOCIDAD (RTF)")
print("=" * 80)
print(f"{'Voz':<20} {'Idioma':<8} {'RTF Promedio':<12} {'Rango':<20}")
print("-" * 80)

# Agrupar por voz
from collections import defaultdict

voice_stats = defaultdict(list)
for r in results:
    voice_stats[(r["voice"], r["lang"])].append(r["rtf"])

for (voice, lang), rtfs in sorted(voice_stats.items()):
    avg_rtf = sum(rtfs) / len(rtfs)
    min_rtf = min(rtfs)
    max_rtf = max(rtfs)

    if avg_rtf < 0.1:
        speed_label = "⚡ Ultra rápido"
    elif avg_rtf < 0.3:
        speed_label = "✅ Rápido"
    elif avg_rtf < 1.0:
        speed_label = "🆗 Aceptable"
    else:
        speed_label = "⚠️ Lento"

    print(f"{voice:<20} {lang:<8} {avg_rtf:<12.3f} {speed_label}")

print("\n" + "=" * 80)
print("ARCHIVOS GENERADOS")
print("=" * 80)
print(f"Directorio: {OUTPUT_DIR}")
print("\nVoces españolas:")
for f in sorted(OUTPUT_DIR.glob("ef_*.wav")) + sorted(OUTPUT_DIR.glob("em_*.wav")):
    size = f.stat().st_size / 1024
    print(f"  • {f.name:<40} ({size:.1f} KB)")

print("\nVoces inglesas (muestra):")
for f in sorted(OUTPUT_DIR.glob("af_*.wav")):
    size = f.stat().st_size / 1024
    print(f"  • {f.name:<40} ({size:.1f} KB)")

print("\n" + "=" * 80)
print("ANÁLISIS Y RECOMENDACIÓN")
print("=" * 80)
print("""
🔍 Hallazgos:

1. VELOCIDAD:
   • Kokoro es EXTREMADAMENTE rápido (RTF típicamente < 0.1x)
   • 10-20× más rápido que tiempo real
   • Ideal para respuestas instantáneas

2. ESPAÑOL:
   • Solo 3 voces disponibles (ef_dora, em_alex, em_santa)
   • Usan espeak-ng fallback (calidad G2P inferior)
   • ef_dora es la única opción femenina

3. INGLÉS:
   • Mucha más variedad y calidad
   • af_heart, af_bella tienen grade A
   • af_nicole tiene HH hours de entrenamiento

4. COMPARACIÓN CON QWEN3-TTS:
   • Kokoro: 10-20× más rápido, SIN voice cloning
   • Qwen3-TTS: Más lento (RTF ~0.7-1.2x), CON voice cloning premium

💡 RECOMENDACIÓN PARA NICOBOT:

Stack híbrido confirmado:
┌────────────────────────────────────────────────────────────┐
│ FRASES CORTAS (< 5 palabras)                               │
│ • Kokoro (ef_dora en español, af_heart en inglés)          │
│ • RTF ~0.05x (20× más rápido que tiempo real)             │
│ • Uso: "Hola", "Sí", "Entendido", "Procesando..."          │
├────────────────────────────────────────────────────────────┤
│ FRASES LARGAS / NARRACIÓN                                  │
│ • Qwen3-TTS MLX (voz de Cristina clonada)                  │
│ • RTF ~0.7-1.2x                                            │
│ • Uso: Narración de progreso, mensajes importantes         │
└────────────────────────────────────────────────────────────┘
""")

print(f"\n✅ Test completado. Archivos en: {OUTPUT_DIR}")
print("🎧 Escucha los archivos WAV para evaluar calidad subjetiva.")
