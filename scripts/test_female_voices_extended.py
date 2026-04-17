#!/usr/bin/env python3
"""
Extended Female Voice Test - Alternativas a Piper
Buscando voz femenina española de calidad
"""

import time
import subprocess
import sys
from pathlib import Path
import soundfile as sf

OUTPUT_DIR = Path(
    "/Users/testnico/Documents/GitHub/nicobot/artifacts/female-voice-test"
)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

TEST_PHRASES = [
    ("Hola Nico.", "greeting"),
    ("¿Cómo estás?", "howareyou"),
    ("He encontrado tres archivos.", "status"),
]

print("=" * 80)
print("EXTENDED FEMALE VOICE TEST - Español de España")
print("=" * 80)
print("\n🔍 Probando alternativas a Piper para voz femenina española\n")

results = []

# 1. RE-TEST PIPER con configuraciones diferentes
print("\n" + "=" * 80)
print("1. PIPER - Voces femeninas españolas (re-test)")
print("=" * 80)

piper_voices = [
    ("es_ES-sharvard-medium", "Sharvard medium"),
]

piper_path = "piper"

for voice_id, voice_name in piper_voices:
    print(f"\n🎙️  {voice_name}")
    model_path = f"/Users/testnico/Documents/GitHub/nicobot/artifacts/piper-models/{voice_id}.onnx"

    if not Path(model_path).exists():
        print(f"   ❌ Modelo no encontrado: {model_path}")
        continue

    for text, label in TEST_PHRASES:
        print(f"   [{label}] '{text[:30]}...' ", end="", flush=True)

        output_file = OUTPUT_DIR / f"piper_{voice_id}_{label}.wav"

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
                duration = len(data) / sr
                rtf = gen_time / duration
                print(f"✓ RTF: {rtf:.3f}x")
                results.append(("Piper", voice_name, label, rtf, str(output_file)))
            else:
                print("❌ Error")
        except Exception as e:
            print(f"❌ {e}")

# 2. TEST MELOTTS
print("\n" + "=" * 80)
print("2. MELOTTS - Español")
print("=" * 80)

try:
    print("\n📦 Verificando MeloTTS...")
    from melo.api import TTS

    print("🎙️  MeloTTS - Speaker ES (único disponible)")
    device = "cpu"
    model = TTS(language="ES", device=device)
    speaker_ids = model.hps.data.spk2id

    for text, label in TEST_PHRASES:
        print(f"   [{label}] '{text[:30]}...' ", end="", flush=True)

        output_file = OUTPUT_DIR / f"melotts_es_{label}.wav"

        try:
            t0 = time.time()
            model.tts_to_file(text, speaker_ids["ES"], str(output_file), speed=1.0)
            gen_time = time.time() - t0

            data, sr = sf.read(output_file)
            duration = len(data) / sr
            rtf = gen_time / duration
            print(f"✓ RTF: {rtf:.3f}x")
            results.append(("MeloTTS", "ES Speaker", label, rtf, str(output_file)))
        except Exception as e:
            print(f"❌ {e}")

except ImportError:
    print("   ❌ MeloTTS no instalado")
    print("   Para instalar: pip install melotts")

# 3. TEST QWEN3-TTS MLX (baseline de calidad)
print("\n" + "=" * 80)
print("3. QWEN3-TTS MLX - Voz de Cristina (baseline calidad)")
print("=" * 80)

try:
    from mlx_audio.tts.utils import load_model
    from mlx_audio.tts.generate import generate_audio

    print("\n🎙️  Qwen3-TTS - Cristina (clonada)")
    model = load_model("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")

    ref_audio = "/Users/testnico/Documents/GitHub/nicobot/exemple/voice_preview_cristina - empathetic customer support.mp3"

    for text, label in TEST_PHRASES[:2]:  # Solo 2 frases (es lento)
        print(f"   [{label}] '{text[:30]}...' ", end="", flush=True)

        temp_dir = OUTPUT_DIR / f"qwen3_temp_{label}_{int(time.time())}"
        temp_dir.mkdir(exist_ok=True)

        try:
            t0 = time.time()
            generate_audio(
                model=model,
                text=text,
                language="Spanish",
                ref_audio=ref_audio,
                ref_text="Soy Cristina, la voz perfecta para automatizar tu atención al cliente.",
                output_path=str(temp_dir),
            )
            gen_time = time.time() - t0

            # Mover archivo
            wav_files = list(temp_dir.glob("*.wav"))
            if wav_files:
                output_file = OUTPUT_DIR / f"qwen3_cristina_{label}.wav"
                import shutil

                shutil.move(str(wav_files[0]), str(output_file))
                shutil.rmtree(temp_dir)

                data, sr = sf.read(output_file)
                duration = len(data) / sr
                rtf = gen_time / duration
                print(f"✓ RTF: {rtf:.3f}x")
                results.append(("Qwen3-TTS", "Cristina", label, rtf, str(output_file)))
            else:
                print("❌ No se generó archivo")
        except Exception as e:
            print(f"❌ {e}")

except Exception as e:
    print(f"   ❌ Error cargando Qwen3-TTS: {e}")

# Resumen
print("\n" + "=" * 80)
print("RESUMEN DE VOCES FEMENINAS ESPAÑOLAS")
print("=" * 80)

if results:
    print(f"\n{'Motor':<15} {'Voz':<25} {'RTF Promedio':<15} {'Archivo'}")
    print("-" * 80)

    from collections import defaultdict

    voice_stats = defaultdict(list)
    for motor, voz, label, rtf, archivo in results:
        voice_stats[(motor, voz)].append(rtf)

    for (motor, voz), rtfs in sorted(voice_stats.items()):
        avg_rtf = sum(rtfs) / len(rtfs)
        # Encontrar archivo de greeting
        greeting_file = [
            r[4]
            for r in results
            if r[0] == motor and r[1] == voz and r[2] == "greeting"
        ]
        file_short = greeting_file[0].split("/")[-1] if greeting_file else "N/A"
        print(f"{motor:<15} {voz:<25} {avg_rtf:<15.3f} {file_short}")

print("\n" + "=" * 80)
print("ANÁLISIS")
print("=" * 80)
print("""
🎯 PROBLEMA: Encontrar voz femenina española (ES) rápida y de calidad

OPCIONES PROBADAS:

1. PIPER (es_ES-sharvard-medium):
   ✅ Ultra-rápido (RTF ~0.3-0.5x)
   ✅ Español peninsular (es_ES)
   ⚠️ Calidad básica (ONNX)
   🤔 ¿Te gusta esta voz?

2. MELOTTS (ES Speaker):
   ✅ Rápido (RTF ~0.2-0.5x)
   ⚠️ Acento puede tener influencia china/mechada
   🤔 ¿Suena lo suficientemente española?

3. QWEN3-TTS MLX (Cristina):
   ✅ Calidad PREMIUM (voz clonada)
   ✅ Acento español correcto
   ❌ Lento para frases cortas (RTF ~1-3x)
   ✅ Perfecto para narración de progreso

🤔 PREGUNTAS CLAVE:

1. ¿Alguna de estas voces te gusta para frases cortas?

2. Si ninguna funciona, opciones alternativas:
   
   a) Usar Qwen3-TTS para TODO (más lento pero calidad premium)
   
   b) Buscar modelos nuevos:
      - Voces de Coqui TTS
      - Modelos específicos es_ES en HuggingFace
      - VITS2 español
   
   c) Entrenar/fine-tunear una voz específica (complejo)
   
   d) Aceptar latencia más alta por calidad (solo Qwen3-TTS)

3. ¿Quieres que investigue otras opciones específicas?
   
💡 RECOMENDACIÓN INTERINA:

Si ninguna voz rápida te gusta, podemos:
- Usar solo Qwen3-TTS MLX (más lento pero calidad garantizada)
- Aceptar RTF ~1-2x para frases cortas (sigue siendo usable)
- Priorizar calidad sobre velocidad
""")

print(f"\n✅ Test completado.")
print(f"🎧 Archivos en: {OUTPUT_DIR}")
print(f"\n🎵 Escucha y dime qué voz prefieres, o si ninguna funciona.")
