#!/usr/bin/env python3
"""
Spoken Assistant - Push to Talk (F7)

Sistema push-to-talk como Spokenly:
- Mantén pulsado F7 para grabar
- Suelta F7 para procesar (STT → Translate → TTS)

Usage:
    source artifacts/kokoro-venv/bin/activate
    python spoken_assistant_ptt.py
"""

import sys
import time
import tempfile
import os
import threading
from pathlib import Path
from typing import Optional, List


# Verificar dependencias
def check_deps():
    missing = []

    for pkg in [
        "numpy",
        "sounddevice",
        "soundfile",
        "torch",
        "transformers",
        "kokoro",
        "pynput",
    ]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)

    try:
        import nemo.collections.asr
    except ImportError:
        missing.append("nemo_toolkit[asr]")

    if missing:
        print("❌ Faltan dependencias:")
        for m in missing:
            print(f"   pip install {m}")
        sys.exit(1)


check_deps()

import numpy as np
import sounddevice as sd
import soundfile as sf
import torch
from transformers import MarianMTModel, MarianTokenizer
from kokoro import KPipeline
import nemo.collections.asr as nemo_asr
from pynput import keyboard


class PushToTalkRecorder:
    """Grabadora push-to-talk: F7 para grabar, soltar para parar"""

    def __init__(self, sample_rate: int = 16000):
        self.sample_rate = sample_rate
        self.is_recording = False
        self.audio_buffer: List[np.ndarray] = []
        self.recording_thread = None
        self.stream = None

    def start_recording(self):
        """Inicia grabación cuando se pulsa F7"""
        if self.is_recording:
            return

        self.is_recording = True
        self.audio_buffer = []

        # Configurar stream de audio
        self.stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype=np.float32,
            callback=self._audio_callback,
        )
        self.stream.start()

    def _audio_callback(self, indata, frames, time_info, status):
        """Callback que recibe audio del micrófono"""
        if self.is_recording and status is None:
            self.audio_buffer.append(indata.copy().flatten())

    def stop_recording(self) -> Optional[np.ndarray]:
        """Detiene grabación y devuelve audio cuando se suelta F7"""
        if not self.is_recording:
            return None

        self.is_recording = False

        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None

        if not self.audio_buffer:
            return None

        # Concatenar todos los chunks
        audio = np.concatenate(self.audio_buffer)
        duration = len(audio) / self.sample_rate

        if duration < 0.5:  # Muy corto, probablemente ruido
            return None

        return audio


class SpokenAssistantPTT:
    """Asistente con push-to-talk F7"""

    def __init__(self):
        self.recorder = PushToTalkRecorder()
        self.asr_model = None
        self.translator_tokenizer = None
        self.translator_model = None
        self.tts_pipeline = None
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"

        # Estado
        self.is_processing = False

    def setup(self):
        """Inicializa todos los componentes"""
        print("🔄 Inicializando...")

        # Parakeet v3
        print("   📥 Cargando Parakeet v3 (~2GB primera vez)...")
        self.asr_model = nemo_asr.models.EncDecRNNTBPEModel.from_pretrained(
            model_name="nvidia/parakeet-tdt-1.1b"
        )
        self.asr_model.eval()
        self.asr_model.to(self.device)
        print("   ✅ Parakeet v3 listo")

        # Traductor
        print("   📥 Cargando traductor ES→EN...")
        model_name = "Helsinki-NLP/opus-mt-es-en"
        self.translator_tokenizer = MarianTokenizer.from_pretrained(model_name)
        self.translator_model = MarianMTModel.from_pretrained(model_name)
        self.translator_model.to(self.device)
        self.translator_model.eval()
        print("   ✅ Traductor listo")

        # Kokoro
        print("   📥 Cargando Kokoro...")
        self.tts_pipeline = KPipeline(lang_code="a")
        print("   ✅ Kokoro listo")
        print("\n" + "=" * 60)

    def transcribe(self, audio_path: str) -> str:
        """Transcribe con Parakeet v3"""
        output = self.asr_model.transcribe([audio_path])
        return output[0].text

    def translate(self, text: str) -> str:
        """Traduce ES→EN"""
        inputs = self.translator_tokenizer(text, return_tensors="pt", padding=True)
        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        with torch.no_grad():
            translated = self.translator_model.generate(**inputs)

        return self.translator_tokenizer.decode(translated[0], skip_special_tokens=True)

    def synthesize(self, text: str, output_path: str):
        """Sintetiza voz con Kokoro"""
        generator = self.tts_pipeline(text, voice="af_bella", speed=1.0)
        for _, _, audio in generator:
            sf.write(output_path, audio, 24000)
            return

    def process_audio(self, audio: np.ndarray):
        """Procesa audio: STT → Translate → TTS → Play"""
        if self.is_processing or audio is None:
            return

        self.is_processing = True

        try:
            # Guardar audio temporal
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                temp_path = f.name
            sf.write(temp_path, audio, 16000)

            # 1. STT
            print("\n📝 Transcribiendo...")
            text_es = self.transcribe(temp_path)
            print(f'   ES: "{text_es}"')

            # 2. Traducir
            print("🌐 Traduciendo...")
            text_en = self.translate(text_es)
            print(f'   EN: "{text_en}"')

            # 3. TTS
            print("🔊 Generando voz...")
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                output_path = f.name
            self.synthesize(text_en, output_path)

            # 4. Reproducir
            print("🔈 Reproduciendo...")
            data, sr = sf.read(output_path)
            sd.play(data, sr)
            sd.wait()

            # Limpiar
            os.unlink(temp_path)
            os.unlink(output_path)
            print("✅ Completado\n")

        except Exception as e:
            print(f"❌ Error: {e}")
        finally:
            self.is_processing = False

    def on_key_press(self, key):
        """Callback cuando se pulsa una tecla"""
        try:
            if (
                key == keyboard.Key.f7
                and not self.recorder.is_recording
                and not self.is_processing
            ):
                print("🔴 GRABANDO... (suelta F7 para procesar)", end="\r")
                self.recorder.start_recording()
        except:
            pass

    def on_key_release(self, key):
        """Callback cuando se suelta una tecla"""
        try:
            if key == keyboard.Key.f7 and self.recorder.is_recording:
                print("⏹️  Procesando...                              ")
                audio = self.recorder.stop_recording()
                if audio is not None:
                    duration = len(audio) / 16000
                    print(f"   Audio: {duration:.1f}s")
                    self.process_audio(audio)
                else:
                    print("⚠️  Audio muy corto, ignorado")
        except:
            pass

    def run(self):
        """Loop principal con hotkey listener"""
        print("=" * 60)
        print("🎙️  SPOKEN ASSISTANT - Push to Talk (F7)")
        print("=" * 60)
        print("\nInstrucciones:")
        print("   🔴 Mantén F7 pulsado para GRABAR")
        print("   ⏹️  Suelta F7 para PROCESAR y hablar")
        print("   ❌ ESC para salir")
        print("\n🔄 Inicializando modelos (puede tardar la primera vez)...")

        self.setup()

        print("✅ Listo! Pulsa F7 para empezar...")
        print("=" * 60)

        # Configurar listener de teclado
        with keyboard.Listener(
            on_press=self.on_key_press, on_release=self.on_key_release
        ) as listener:
            try:
                listener.join()
            except KeyboardInterrupt:
                pass

        print("\n👋 Hasta luego!")


def main():
    assistant = SpokenAssistantPTT()
    assistant.run()


if __name__ == "__main__":
    main()
