#!/usr/bin/env python3
"""
Spoken-like Assistant - STT (Parakeet) → Translate → TTS (Kokoro)

Este script implementa un asistente de voz similar a Spokenly:
1. Escucha audio del micrófono
2. Usa Parakeet v3 para STT (español)
3. Traduce español → inglés
4. Genera TTS con Kokoro (af_bella)
5. Reproduce el audio

Setup:
    source artifacts/kokoro-venv/bin/activate
    python spoken_assistant.py

O manualmente:
    pip install kokoro soundfile nemo_toolkit['asr'] transformers torch sounddevice numpy
"""

import sys
import time
import threading
import queue
import tempfile
import os
from pathlib import Path
from typing import Optional


# Verificar que estamos en el venv correcto
def check_venv():
    """Verifica que las dependencias estén instaladas"""
    missing = []

    try:
        import numpy as np
    except ImportError:
        missing.append("numpy")

    try:
        import sounddevice as sd
    except ImportError:
        missing.append("sounddevice")

    try:
        import soundfile as sf
    except ImportError:
        missing.append("soundfile")

    try:
        import torch
    except ImportError:
        missing.append("torch")

    try:
        import transformers
    except ImportError:
        missing.append("transformers")

    try:
        from kokoro import KPipeline
    except ImportError:
        missing.append("kokoro")

    if missing:
        print("❌ Faltan dependencias. Ejecuta:")
        print(f"   source artifacts/kokoro-venv/bin/activate")
        print(f"   pip install {' '.join(missing)}")
        print("\n⚠️  Para NeMo (Parakeet), necesitarás:")
        print("   pip install nemo_toolkit['asr']")
        sys.exit(1)


check_venv()

import numpy as np
import sounddevice as sd
import soundfile as sf
import torch


class AudioRecorder:
    """Grabadora de audio con VAD (Voice Activity Detection) simple"""

    def __init__(self, sample_rate: int = 16000, channels: int = 1):
        self.sample_rate = sample_rate
        self.channels = channels
        self.buffer = []
        self.is_recording = False
        self.audio_queue = queue.Queue()

    def vad_simple(self, audio_chunk: np.ndarray, threshold: float = 0.01) -> bool:
        """Detección simple de actividad de voz basada en energía"""
        energy = np.sqrt(np.mean(audio_chunk**2))
        return energy > threshold

    def record_chunk(self, duration: float = 0.5) -> np.ndarray:
        """Graba un chunk de audio"""
        num_samples = int(self.sample_rate * duration)
        chunk = sd.rec(
            num_samples,
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype=np.float32,
        )
        sd.wait()
        return chunk.flatten()

    def record_until_silence(
        self, silence_duration: float = 1.5, max_duration: float = 30.0
    ) -> Optional[np.ndarray]:
        """
        Graba audio hasta detectar silencio o alcanzar duración máxima.
        Similar a Spokenly: espera voz, graba, para cuando hay silencio.
        """
        print("🎙️  Escuchando... (habla ahora)")

        audio_buffer = []
        silence_chunks = 0
        max_silence_chunks = int(silence_duration / 0.5)  # chunks de 0.5s
        max_chunks = int(max_duration / 0.5)
        has_voice = False

        for i in range(max_chunks):
            chunk = self.record_chunk(duration=0.5)

            # Detectar si hay voz en este chunk
            is_voice = self.vad_simple(chunk)

            if is_voice:
                has_voice = True
                silence_chunks = 0
                audio_buffer.append(chunk)
                if i == 0 or (i > 0 and not has_voice):
                    print("   ✓ Voz detectada, grabando...")
            elif has_voice:
                # Ya empezamos a grabar, seguimos durante silencio breve
                audio_buffer.append(chunk)
                silence_chunks += 1

                if silence_chunks >= max_silence_chunks:
                    print("   ✓ Silencio detectado, finalizando...")
                    break

            # Mostrar indicador de actividad
            energy = np.sqrt(np.mean(chunk**2))
            indicator = "█" * int(energy * 50)
            print(f"   {indicator}", end="\r")

        if not has_voice:
            print("   ✗ No se detectó voz")
            return None

        # Concatenar todos los chunks
        audio_data = np.concatenate(audio_buffer)
        duration = len(audio_data) / self.sample_rate
        print(f"   ✓ Audio grabado: {duration:.1f}s")

        return audio_data


class SpokenAssistant:
    """Asistente de voz tipo Spokenly"""

    def __init__(self):
        self.recorder = AudioRecorder(sample_rate=16000)
        self.asr_model = None
        self.translator = None
        self.tts_pipeline = None

        # Verificar device
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        print(f"🔧 Dispositivo: {self.device}")

    def setup_asr(self):
        """Inicializa Parakeet v3 para STT"""
        print("🔄 Cargando Parakeet v3 (STT)...")

        try:
            import nemo.collections.asr as nemo_asr

            # Cargar modelo Parakeet-TDT-1.1B
            self.asr_model = nemo_asr.models.EncDecRNNTBPEModel.from_pretrained(
                model_name="nvidia/parakeet-tdt-1.1b"
            )
            self.asr_model.eval()
            self.asr_model.to(self.device)

            print("   ✅ Parakeet v3 cargado")
            print("   📊 Modelo: 1.1B parámetros, FastConformer-TDT")

        except Exception as e:
            print(f"   ❌ Error cargando Parakeet: {e}")
            print("   💡 Asegúrate de tener instalado: pip install nemo_toolkit['asr']")
            raise

    def setup_translator(self):
        """Inicializa traductor español → inglés"""
        print("🔄 Cargando traductor (es → en)...")

        try:
            from transformers import MarianMTModel, MarianTokenizer

            # Modelo Marian para español → inglés
            model_name = "Helsinki-NLP/opus-mt-es-en"
            self.translator_tokenizer = MarianTokenizer.from_pretrained(model_name)
            self.translator_model = MarianMTModel.from_pretrained(model_name)
            self.translator_model.to(self.device)
            self.translator_model.eval()

            print("   ✅ Traductor cargado")
            print(f"   📊 Modelo: {model_name}")

        except Exception as e:
            print(f"   ❌ Error cargando traductor: {e}")
            print("   💡 Asegúrate de tener instalado: pip install transformers")
            raise

    def setup_tts(self):
        """Inicializa Kokoro para TTS"""
        print("🔄 Cargando Kokoro (TTS)...")

        try:
            from kokoro import KPipeline

            # Pipeline de Kokoro para inglés americano
            self.tts_pipeline = KPipeline(lang_code="a")

            print("   ✅ Kokoro cargado")
            print("   🎙️  Voz: af_bella (American Female, Grade A)")

        except Exception as e:
            print(f"   ❌ Error cargando Kokoro: {e}")
            print("   💡 Asegúrate de tener instalado: pip install kokoro soundfile")
            raise

    def transcribe(self, audio_path: str) -> str:
        """Transcribe audio español usando Parakeet"""
        print("   📝 Transcribiendo con Parakeet...")

        try:
            # Parakeet espera archivos WAV mono 16kHz
            output = self.asr_model.transcribe([audio_path])
            text = output[0].text
            print(f'   ✓ Texto (ES): "{text}"')
            return text

        except Exception as e:
            print(f"   ❌ Error en transcripción: {e}")
            return ""

    def translate(self, text: str) -> str:
        """Traduce español → inglés"""
        print("   🌐 Traduciendo ES → EN...")

        try:
            # Tokenizar
            inputs = self.translator_tokenizer(
                text, return_tensors="pt", padding=True, truncation=True
            )
            inputs = {k: v.to(self.device) for k, v in inputs.items()}

            # Traducir
            with torch.no_grad():
                translated = self.translator_model.generate(**inputs)

            # Decodificar
            translated_text = self.translator_tokenizer.decode(
                translated[0], skip_special_tokens=True
            )
            print(f'   ✓ Texto (EN): "{translated_text}"')
            return translated_text

        except Exception as e:
            print(f"   ❌ Error en traducción: {e}")
            return text  # Fallback: usar texto original

    def text_to_speech(self, text: str, output_path: str):
        """Genera audio con Kokoro (voz af_bella)"""
        print("   🔊 Generando audio con Kokoro...")

        try:
            generator = self.tts_pipeline(text, voice="af_bella", speed=1.0)

            for i, (gs, ps, audio) in enumerate(generator):
                sf.write(output_path, audio, 24000)
                duration = len(audio) / 24000
                print(f"   ✓ Audio generado: {duration:.1f}s")
                return

        except Exception as e:
            print(f"   ❌ Error generando audio: {e}")
            raise

    def play_audio(self, audio_path: str):
        """Reproduce audio"""
        print("   🔈 Reproduciendo...")

        try:
            data, samplerate = sf.read(audio_path)
            sd.play(data, samplerate)
            sd.wait()
            print("   ✓ Reproducción completada")

        except Exception as e:
            print(f"   ❌ Error reproduciendo: {e}")

    def run(self):
        """Loop principal del asistente"""
        print("\n" + "=" * 70)
        print("🎙️  SPOKEN ASSISTANT - Parakeet v3 + Kokoro")
        print("=" * 70)
        print("\nInstrucciones:")
        print("  1. Habla en español cuando veas '🎙️  Escuchando...'")
        print("  2. El asistente transcribirá, traducirá y responderá en inglés")
        print("  3. Presiona Ctrl+C para salir")
        print("")

        # Inicializar componentes
        print("🔄 Inicializando componentes...")
        self.setup_asr()
        self.setup_translator()
        self.setup_tts()
        print("✅ Todos los componentes listos\n")

        try:
            while True:
                print("-" * 70)

                # 1. Grabar audio
                audio_data = self.recorder.record_until_silence()
                if audio_data is None:
                    continue

                # 2. Guardar temporalmente
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                    temp_path = f.name
                sf.write(temp_path, audio_data, 16000)

                try:
                    # 3. STT (Español)
                    text_es = self.transcribe(temp_path)
                    if not text_es:
                        continue

                    # 4. Traducir (ES → EN)
                    text_en = self.translate(text_es)

                    # 5. TTS (Inglés con Kokoro)
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                        output_path = f.name
                    self.text_to_speech(text_en, output_path)

                    # 6. Reproducir
                    self.play_audio(output_path)

                    # Limpiar archivos temporales
                    os.unlink(temp_path)
                    os.unlink(output_path)

                except Exception as e:
                    print(f"   ❌ Error en procesamiento: {e}")
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)

                print("")

        except KeyboardInterrupt:
            print("\n\n👋 Saliendo...")
            print("✅ Hasta luego!")


def main():
    """Entry point"""
    # Verificar dependencias
    print("🔍 Verificando dependencias...")

    missing = []

    try:
        import numpy
    except ImportError:
        missing.append("numpy")

    try:
        import sounddevice
    except ImportError:
        missing.append("sounddevice")

    try:
        import soundfile
    except ImportError:
        missing.append("soundfile")

    try:
        import torch
    except ImportError:
        missing.append("torch")

    try:
        import transformers
    except ImportError:
        missing.append("transformers")

    try:
        import kokoro
    except ImportError:
        missing.append("kokoro")

    if missing:
        print("❌ Faltan dependencias:")
        print(f"   pip install {' '.join(missing)}")
        print("\n⚠️  Nota: Para NeMo (Parakeet), ejecuta:")
        print("   pip install nemo_toolkit['asr']")
        sys.exit(1)

    print("✅ Todas las dependencias encontradas\n")

    # Iniciar asistente
    assistant = SpokenAssistant()
    assistant.run()


if __name__ == "__main__":
    main()
