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
import termios
import tty
import select
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
import warnings
from transformers import MarianMTModel, MarianTokenizer
from kokoro import KPipeline
import nemo.collections.asr as nemo_asr

# Reducir ruido de logs en terminal
warnings.filterwarnings("ignore")
try:
    from nemo.utils import logging as nemo_logging

    nemo_logging.setLevel(40)  # ERROR
except Exception:
    pass


class PushToTalkRecorder:
    """Grabadora push-to-talk: F7 para grabar, soltar para parar"""

    def __init__(self, sample_rate: int = 16000):
        self.sample_rate = sample_rate
        self.is_recording = False
        self.audio_buffer: List[np.ndarray] = []
        self.recording_thread = None
        self.stream = None
        self.started_at = 0.0
        self.last_status = None

    def start_recording(self):
        """Inicia grabación cuando se pulsa F7"""
        if self.is_recording:
            return

        self.is_recording = True
        self.audio_buffer = []
        self.started_at = time.time()
        self.last_status = None

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
        if self.is_recording:
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
        wall = time.time() - self.started_at

        if wall > 1.0 and duration < 0.2:
            raise RuntimeError(
                "No se capto audio del microfono. Revisa permisos de microfono para Terminal (Settings > Privacy & Security > Microphone)."
            )

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
        self.is_recording_ui = False
        self.models_ready = False
        self.last_toggle_at = 0.0

    def _print_status(self, message: str):
        """Imprime estado visible y consistente en terminal."""
        print(f"\n{message}")

    def ensure_models_loaded(self):
        """Carga modelos (una sola vez)."""
        if self.models_ready:
            return

        print("\n📦 Cargando modelos (solo tarda la primera vez)...")

        print("   📥 Cargando Parakeet v3 0.6B...")
        self.asr_model = nemo_asr.models.EncDecRNNTBPEModel.from_pretrained(
            model_name="nvidia/parakeet-tdt-0.6b-v3"
        )
        self.asr_model.eval()
        self.asr_model.to(self.device)
        print("   ✅ Parakeet v3 listo")

        print("   📥 Cargando traductor ES→EN...")
        model_name = "Helsinki-NLP/opus-mt-es-en"
        self.translator_tokenizer = MarianTokenizer.from_pretrained(model_name)
        self.translator_model = MarianMTModel.from_pretrained(model_name)
        self.translator_model.to(self.device)
        self.translator_model.eval()
        print("   ✅ Traductor listo")

        print("   📥 Cargando Kokoro...")
        self.tts_pipeline = KPipeline(lang_code="a")
        print("   ✅ Kokoro listo")

        self.models_ready = True
        print("✅ Modelos listos\n")

    def transcribe(self, audio_path: str) -> str:
        """Transcribe con Parakeet v3"""
        output = self.asr_model.transcribe([audio_path], verbose=False)
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
            self.ensure_models_loaded()

            # Guardar audio temporal
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                temp_path = f.name
            sf.write(temp_path, audio, 16000)

            # 1. STT
            print("\n📝 Transcribiendo...")
            stt_t0 = time.perf_counter()
            text_es = self.transcribe(temp_path)
            stt_time = time.perf_counter() - stt_t0
            print(f'   ES: "{text_es}"')

            # 2. Traducir
            print("🌐 Traduciendo...")
            text_en = self.translate(text_es)
            print(f'   EN: "{text_en}"')

            # 3. TTS
            print("🔊 Generando voz...")
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                output_path = f.name
            tts_t0 = time.perf_counter()
            self.synthesize(text_en, output_path)
            tts_time = time.perf_counter() - tts_t0

            # 4. Reproducir
            print("🔈 Reproduciendo...")
            data, sr = sf.read(output_path)
            sd.play(data, sr)
            sd.wait()

            # Limpiar
            os.unlink(temp_path)
            os.unlink(output_path)
            print("✅ Completado")
            print(f"   ⏱️  STT: {stt_time:.2f}s")
            print(f"   ⏱️  TTS: {tts_time:.2f}s\n")

        except Exception as e:
            print(f"❌ Error: {e}")
        finally:
            self.is_processing = False

    def toggle_recording(self):
        """Alterna grabacion con cada pulsacion de F7"""
        now = time.time()
        if now - self.last_toggle_at < 0.35:
            return
        self.last_toggle_at = now

        if self.is_processing:
            return

        if not self.recorder.is_recording:
            self.recorder.start_recording()
            self.is_recording_ui = True
            self._print_status("🔴 GRABANDO ACTIVO (pulsa F7 otra vez para parar)")
            return

        self.is_recording_ui = False
        self._print_status("⏹️  Grabacion detenida. Procesando...")
        try:
            audio = self.recorder.stop_recording()
        except RuntimeError as e:
            print(f"❌ {e}")
            return
        if audio is not None:
            duration = len(audio) / 16000
            print(f"   Audio: {duration:.1f}s")
            self.process_audio(audio)
        else:
            print("⚠️  Audio muy corto, ignorado")

    def _read_key_sequence(self):
        """Lee secuencias de teclas en modo raw del terminal."""
        if not select.select([sys.stdin], [], [], 0.05)[0]:
            return None

        ch = sys.stdin.read(1)
        if not ch:
            return None

        if ch != "\x1b":
            return ch

        seq = ch
        while select.select([sys.stdin], [], [], 0.03)[0]:
            seq += sys.stdin.read(1)
        return seq

    def run(self):
        """Loop principal con hotkey listener"""
        os.system("clear")
        print("=" * 60)
        print("🎙️  SPOKEN ASSISTANT - Push to Talk (F7)")
        print("=" * 60)
        print("\nInstrucciones:")
        print("   🔴 Pulsa F7 para EMPEZAR a grabar")
        print("   ⏹️  Pulsa F7 otra vez para PARAR y procesar")
        print("   💡 Fallbacks: tecla r o barra espaciadora")
        print("   ❌ Pulsa q para salir")
        print("   🎤 Si ves audio corto siempre: da permiso de microfono a Terminal")
        print("\n⏳ Cargando modelos antes de permitir grabacion...")
        self.ensure_models_loaded()
        print("✅ Listo! Pulsa F7 para empezar...")
        print("=" * 60)

        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            while True:
                seq = self._read_key_sequence()
                if seq is None:
                    continue

                if seq == "q":
                    break

                if seq == "r":
                    self.toggle_recording()
                    continue

                if seq == " ":
                    self.toggle_recording()
                    continue

                # F7 en terminal ANSI: ESC [ 18 ~
                if seq == "\x1b[18~" or (seq.startswith("\x1b[18") and seq.endswith("~")):
                    self.toggle_recording()
                    continue

                if seq.startswith("\x1b") and seq != "\x1b":
                    print(f"\n🔎 Tecla no mapeada detectada: {seq!r}")

        except KeyboardInterrupt:
            pass
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)

        if self.recorder.is_recording:
            self.recorder.stop_recording()

        print("\n👋 Hasta luego!")


def main():
    assistant = SpokenAssistantPTT()
    assistant.run()


if __name__ == "__main__":
    main()
