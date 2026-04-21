#!/usr/bin/env python3
"""
Qwen3-TTS Optimizado para NicoBot
- Pre-computa x_vector de Cristina
- Minimiza latencia en generación
"""

import torch
import soundfile as sf
import time
from pathlib import Path
from typing import Optional, Tuple
from qwen_tts import Qwen3TTSModel


class Qwen3TTSService:
    """Servicio TTS con voz de Cristina optimizado para baja latencia."""

    def __init__(self, model_size: str = "0.6B"):
        """
        Inicializa el servicio TTS.

        Args:
            model_size: "0.6B" (más rápido) o "1.7B" (mejor calidad)
        """
        self.model_size = model_size
        self.model = None
        self.voice_prompt = None
        self.sample_rate = 24000

    def initialize(self, ref_audio_path: str, device: str = "cpu") -> float:
        """
        Carga el modelo y pre-computa el x_vector.

        Args:
            ref_audio_path: Path al audio de referencia (Cristina)
            device: "cpu", "cuda:0", o "mps"

        Returns:
            Tiempo total de inicialización en segundos
        """
        t0 = time.time()

        # Cargar modelo
        print(f"🔄 Cargando Qwen3-TTS-{self.model_size}-Base...")
        dtype = torch.float32 if device == "cpu" else torch.float16

        self.model = Qwen3TTSModel.from_pretrained(
            f"Qwen/Qwen3-TTS-12Hz-{self.model_size}-Base",
            device_map=device,
            dtype=dtype,
        )

        # Pre-computar x_vector (esto ahorra ~6s por generación)
        print("🎯 Pre-computando embedding de voz (x_vector)...")
        self.voice_prompt = self.model.create_voice_clone_prompt(
            ref_audio=ref_audio_path,
            ref_text="",  # No necesario para x_vector_only
            x_vector_only_mode=True,
        )

        init_time = time.time() - t0
        print(f"✅ Inicializado en {init_time:.2f}s")
        return init_time

    def generate(
        self,
        text: str,
        output_path: Optional[str] = None,
        max_tokens: int = 512,
    ) -> Tuple[str, float, float]:
        """
        Genera audio con la voz de Cristina.

        Args:
            text: Texto a sintetizar
            output_path: Path para guardar el WAV (opcional)
            max_tokens: Límite de tokens (afecta velocidad)

        Returns:
            Tuple de (output_path, generation_time, rtf)
        """
        if self.model is None or self.voice_prompt is None:
            raise RuntimeError("Service not initialized. Call initialize() first.")

        # Generar
        t0 = time.time()
        wavs, sr = self.model.generate_voice_clone(
            text=text,
            language="Spanish",
            voice_clone_prompt=self.voice_prompt,  # Usar embedding pre-computado
            x_vector_only_mode=True,
            max_new_tokens=max_tokens,
            do_sample=False,  # Greedy = más rápido
        )
        gen_time = time.time() - t0

        # Calcular métricas
        audio_duration = len(wavs[0]) / sr
        rtf = gen_time / audio_duration

        # Guardar si se especificó path
        if output_path:
            Path(output_path).parent.mkdir(parents=True, exist_ok=True)
            sf.write(output_path, wavs[0], sr)

        return output_path or "", gen_time, rtf

    def generate_streaming(self, text: str, chunk_callback=None):
        """
        Genera audio en modo streaming (para baja latencia).

        Nota: Qwen3-TTS soporta streaming nativo, pero requiere
        implementación con generadores. Esto es un placeholder.
        """
        # TODO: Implementar streaming con generate_voice_clone(..., stream=True)
        # cuando esté disponible en la API de qwen-tts
        pass


# Demo / Test
if __name__ == "__main__":
    REF_AUDIO = "/Users/testnico/Documents/GitHub/nicobot/exemple/voice_preview_cristina - empathetic customer support.mp3"
    OUTPUT_DIR = Path(
        "/Users/testnico/Documents/GitHub/nicobot/artifacts/qwen3-optimized"
    )
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Qwen3-TTS Optimizado para NicoBot")
    print("=" * 60)

    # Inicializar servicio
    tts = Qwen3TTSService(model_size="0.6B")
    tts.initialize(ref_audio_path=REF_AUDIO, device="cpu")

    # Test frases típicas de asistente
    test_phrases = [
        ("Hola Nico, soy tu asistente.", "greeting"),
        ("He encontrado 3 archivos.", "status_short"),
        (
            "Estoy buscando en tu sistema de archivos, esto puede tomar unos segundos.",
            "status_long",
        ),
        ("La operación se ha completado con éxito.", "success"),
    ]

    print("\n" + "=" * 60)
    print("Generando frases de ejemplo...")
    print("=" * 60)

    for text, label in test_phrases:
        output_file = OUTPUT_DIR / f"{label}.wav"
        path, gen_time, rtf = tts.generate(
            text=text,
            output_path=str(output_file),
            max_tokens=512,
        )
        print(f"\n{label}:")
        print(f"  Texto: {text[:50]}...")
        print(f"  Tiempo: {gen_time:.2f}s | RTF: {rtf:.2f}x")
        print(f"  Guardado: {path}")

    print("\n" + "=" * 60)
    print("✅ Demo completado")
    print("=" * 60)
    print("\nNOTA: Para uso en NicoBot:")
    print("  1. Inicializar una vez al arrancar la app")
    print("  2. Reusar el mismo servicio para todas las generaciones")
    print("  3. Para texto largo (>20 palabras), RTF será ~5x")
    print("  4. Considerar usar Kokoro para respuestas < 5 palabras")
