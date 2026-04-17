# NicoBot - Speech-to-Speech AI Agent

Un asistente de voz conversacional en tiempo real que combina speech-to-text de última generación, un agente inteligente con capacidad de ejecutar herramientas, y síntesis de voz streaming.

> **Estado del proyecto:** Fase de selección de TTS completada. Stack de voz clonada (Qwen3-TTS MLX) validado y listo. Próximo paso: integración de Kokoro para respuestas ultra-rápidas.

---

## Estado Actual del Proyecto (17 Abril 2026)

### ✅ Completado

#### Infraestructura de Voz (TTS)
- **Benchmark exhaustivo** de motores TTS locales:
  - Kokoro, MeloTTS, Piper, Edge TTS, XTTS v2, MOSS-TTS-Nano, F5-TTS, LuxTTS, Chatterbox, OpenVoice, CosyVoice
  - **Ganador para voz clonada:** Qwen3-TTS en MLX (Apple Silicon)
  
- **Voz de Cristina clonada** con calidad premium:
  - Modelo: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
  - RTF: ~0.7-1.2x (más rápido que tiempo real para frases >10 palabras)
  - Memoria: ~6GB peak
  - Calidad: Excelente, sin acento americano

- **Optimizaciones implementadas:**
  - Pre-computación de embedding de voz (x_vector)
  - Transcripción manual de referencia (evita delay de Whisper)
  - Comparativa 8-bit vs 6-bit vs 4-bit completada

### 🔄 En Progreso

- **Stack híbrido de TTS validado:**
  - Qwen3-TTS MLX: para narración de progreso y mensajes largos
  - Kokoro: para respuestas instantáneas (< 5 palabras)

### ⏳ Pendiente

- Pipeline STT → Hermes → TTS completo
- Pipeline STT → Hermes → TTS completo
- UI mínima cuadrada con 3 estados
- Validación de payloads de streaming de Hermes Agent

---

## Visión

NicoBot es un asistente personal de voz que permite interactuar con sistemas complejos mediante comandos de voz naturales. La experiencia está diseñada para ser fluida: hablas, el agente piensa y actúa comunicándote en cada paso lo que está haciendo mediante voz sintetizada en tiempo real.

## Ritmo de interacción y objetivos de latencia

Para este producto, la latencia no es un detalle técnico: define la experiencia. El asistente debe sentirse inmediato en preguntas rápidas y, sobre todo, transparente en tareas agenticas largas donde Hermes ejecuta múltiples pasos.

### Tipos de interacción objetivo

- **Preguntas rápidas**: respuestas cortas, priorizar `time-to-first-audio` mínimo.
- **Tareas agenticas**: ejecución de herramientas, priorizar comunicación progresiva de estado mientras el trabajo sigue en curso.

### Presupuesto de latencia (SLO inicial)

| Métrica | Objetivo |
|---------|----------|
| Hotkey → captura activa | **<100 ms** |
| Fin de habla (VAD) → primer token del agente | **<400-700 ms** |
| Fin de habla (VAD) → primer audio TTS (TTFA) | **<800 ms ideal, <1.2 s máximo** |
| Gaps entre chunks de audio durante streaming | **<120 ms** |

### Stack de TTS Seleccionado (✅ Validado)

| Escenario | Motor | RTF | Latencia | Voz |
|-----------|-------|-----|----------|-----|
| Respuestas cortas (< 5 palabras) | **Kokoro** `ef_dora` | **~0.2x** | ~200-400ms | Femenina español |
| Narración de progreso | **Qwen3-TTS MLX** | ~0.7-1.2x | ~2-4s | Cristina (clonada) |
| Mensajes largos (> 15 palabras) | **Qwen3-TTS MLX** | ~0.7x | tiempo real | Cristina (clonada) |

**Nota:** Kokoro usa voces pre-entrenadas (no clonables). Qwen3-TTS usa voz de Cristina clonada con calidad premium.

### Implicaciones para flujo agentico

En operaciones largas no debemos esperar al resultado final para hablar. El sistema debe narrar progreso en tiempo real, por ejemplo:

- "Entendido, voy a revisarlo ahora"
- "Estoy abriendo tu calendario"
- "He encontrado 3 opciones, te resumo"

## Arquitectura

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Parakeet v3   │────▶│   HERMES Agent   │────▶│   TTS Híbrido   │
│    (STT)        │     │  (Nous Research) │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
   [Sound Waves]          [Thinking Animation]      [Speaking Wave]
   Recording UI            Tool execution status    Progress narration
```

### Componentes

#### 1. Speech-to-Text: Parakeet v3
Utilizamos **Parakeet TDT 1.1B** de NVIDIA NeMo, un modelo FastConformer con arquitectura Token-and-Duration Transducer que ofrece:

- **1.1B parámetros** con downsampling eficiente (8× depthwise-separable convolutions)
- **WER extremadamente bajo**: 1.39% en LibriSpeech clean
- **Velocidad de inferencia optimizada**: salta frames en blanco automáticamente
- **Streaming capable**: compatible con reconocimiento en tiempo real

**Requisitos:**
- Audio: 16kHz mono WAV
- Dependencia: `nemo_toolkit['asr']`

#### 2. Agent Core: HERMES (Nous Research)
El cerebro del sistema. HERMES es un agente conversacional que:

- Procesa el texto transcrito de Parakeet
- Decide qué herramientas ejecutar basándose en la intención del usuario
- Gestiona el estado de las tareas
- **Streaming de tokens**: envía fragmentos de respuesta tan pronto como están disponibles

**Características clave:**
- Tool calling nativo (funciones definidas por el usuario)
- Contexto conversacional persistente
- Capacidad de razonamiento paso a paso
- Streaming de respuestas para TTS interactivo

#### 3. Text-to-Speech: Stack Híbrido

##### Motor Principal: Qwen3-TTS MLX
- **Modelo:** `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- **Plataforma:** MLX (Apple Silicon nativo)
- **RTF:** ~0.7-1.2x (más rápido que tiempo real para frases largas)
- **Memoria:** ~6GB peak
- **Uso:** Narración de progreso, mensajes largos
- **Voz:** Cristina (clonada desde referencia en inglés, habla español nativo)

##### Motor Rápido: Kokoro (Pendiente)
- **RTF:** ~0.1-0.3x (10× más rápido que tiempo real)
- **Uso:** Respuestas cortas, confirmaciones, saludos
- **Ventaja:** Latencia mínima para interacción fluida

## Estructura del Proyecto

```
nicobot/
├── README.md                 # Este archivo
├── .gitignore               # Exclusiones de git
├── docs/
│   ├── references/          # Referencias visuales (UI)
│   └── roadmap/             # Documentación de roadmap
├── exemple/                 # Archivos de referencia
│   └── voice_preview_cristina.mp3  # Voz de referencia
├── scripts/                 # Scripts de utilidad
│   ├── tts_benchmark.py     # Benchmark comparativo
│   ├── qwen3_service.py   # Servicio Qwen3-TTS
│   ├── test_qwen3_mlx.py  # Tests MLX
│   └── test_qwen3_mlx_4bit.py  # Comparativa 4/6/8-bit
└── artifacts/               # Artefactos generados (no en git)
    └── qwen3-mlx-venv/      # Entorno MLX (no en git)
```

## Scripts Disponibles

### Benchmark TTS
```bash
# Comparar motores TTS
python scripts/tts_benchmark.py

# Test de Qwen3-TTS MLX
python scripts/test_qwen3_mlx.py

# Comparativa 4-bit vs 6-bit vs 8-bit
python scripts/test_qwen3_mlx_4bit.py
```

## Instalación

```bash
# Clonar repositorio
git clone https://github.com/tuusuario/nicobot.git
cd nicobot

# Crear entorno virtual (Python 3.12 recomendado)
python3.12 -m venv .venv
source .venv/bin/activate

# Instalar dependencias MLX (para Qwen3-TTS)
pip install mlx==0.31.1 mlx-lm==0.31.1 mlx-audio

# Otras dependencias
pip install soundfile librosa transformers
```

### Requisitos

- Python 3.10+
- macOS con Apple Silicon (M1/M2/M3) - para MLX
- 8GB+ RAM para ejecución local óptima
- ~6GB libres para modelo Qwen3-TTS

## Roadmap

### Fase 1: Infraestructura de Voz ✅
- [x] Benchmark exhaustivo de motores TTS
- [x] Selección de stack híbrido (Qwen3-TTS MLX + Kokoro)
- [x] Clonado de voz de Cristina con calidad premium
- [x] Optimización de velocidad (RTF < 1.0x para frases largas)
- [x] Limpieza de repositorio y preparación para git

### Fase 2: Pipeline Completo (Actual)
- [ ] Integración de Kokoro para respuestas rápidas
- [ ] Pipeline STT → Hermes → TTS end-to-end
- [ ] Validación de streaming de Hermes Agent
- [ ] UI mínima cuadrada con 3 estados

### Fase 3: Optimización
- [ ] Interrupciones por voz (barge-in)
- [ ] Historial de conversaciones
- [ ] Tool system extensible
- [ ] Wake word detection

### Fase 4: Producción
- [ ] Procesamiento local completo
- [ ] Integración con sistema operativo nativo
- [ ] Soporte para múltiples voces

## Hallazgos Técnicos Clave

### Selección de TTS
Tras probar 11 motores diferentes, el stack óptimo para Mac es:

1. **Qwen3-TTS MLX** para calidad premium:
   - Único motor que clona voz de referencia manteniendo acento español correcto
   - RTF ~0.7-1.2x (más rápido que tiempo real en frases largas)
   - Memoria manejable (~6GB)

2. **Kokoro** para velocidad (próximo):
   - RTF ~0.1-0.3x (10× más rápido)
   - Ideal para "Hola", "Entendido", "Procesando..."

### Optimizaciones Aplicadas
- **Pre-computar x_vector:** Ahorra ~6 segundos por request
- **Transcripción manual:** Evita delay de Whisper (~10-15s)
- **MLX nativo:** 3-5× más rápido que PyTorch MPS
- **8-bit cuantizado:** Balance óptimo calidad/velocidad/memoria

## Contribuir

Las contribuciones son bienvenidas. Por favor, abre un issue primero para discutir cambios mayores.

## Licencia

MIT License - ver [LICENSE](LICENSE) para detalles.

## Agradecimientos

- [NVIDIA NeMo](https://github.com/NVIDIA/NeMo) por el modelo Parakeet
- [Nous Research](https://github.com/nickvdh) por HERMES Agent
- [MLX Community](https://huggingface.co/mlx-community) por Qwen3-TTS optimizado
- Inspirado por Spokenly y la visión de interfaces de voz naturales

---

**Última actualización:** 17 Abril 2026  
**Estado:** Fase 1 completada - Listo para integración de Kokoro y pipeline end-to-end
