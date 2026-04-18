# NicoBot - Speech-to-Speech AI Agent

Backend local de asistente de voz para macOS con push-to-talk.

Estado actual: backend funcional y limpio para empezar frontend y empaquetado.

## Current backend

- Entrypoint principal: `spoken_assistant_ptt.py`
- Control de grabación: `F7` (toggle), fallback `r` / barra espaciadora
- Pipeline: `Parakeet v3 STT (es)` -> `traducción es->en` -> `Kokoro af_bella TTS`
- Métricas por turno:
  - tiempo STT
  - tiempo TTS

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python spoken_assistant_ptt.py
```

## Controls

- `F7`: start/stop recording (toggle)
- `r`: fallback start/stop recording
- `space`: fallback start/stop recording
- `q`: quit

## Project structure

```text
nicobot/
├── spoken_assistant_ptt.py      # Backend runtime entrypoint
├── requirements.txt             # Runtime dependencies
├── README.md
├── docs/
│   ├── roadmap/ai-infra-roadmap.md
│   └── backend-packaging-plan.md
├── scripts/                     # Historical/benchmark scripts
└── artifacts/.gitkeep
```

## Notes

- Model warmup happens before first recording so first turn is not delayed by loading.
- For microphone issues, grant terminal microphone access in macOS Privacy settings.
- Packaging and frontend handoff plan: `docs/backend-packaging-plan.md`.

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

### Stack de TTS (✅ ACTIVO - Simplificado)

| Motor | Idioma | Voz | RTF | Latencia | Uso |
|-------|--------|-----|-----|----------|-----|
| **Kokoro** | 🇬🇧 Inglés | `af_bella` (femenina, Grade A) | **~0.21x** | ~200-400ms | **Todas las respuestas** |

**Stack simplificado (fase inicial):**
- **Un único motor TTS:** Kokoro `af_bella`
- **Ventajas:** Simplicidad, velocidad, calidad premium, setup trivial
- **Limitación aceptada:** Solo inglés (para fase inicial de desarrollo)

**Motor standby (para expansión futura):**
- **Qwen3-TTS MLX:** Validado para español + voice cloning (Cristina)
- **Cuándo añadirlo:** Cuando se requiera español nativo o voz clonada
- **Trigger:** Feedback de usuarios o requerimientos de negocio

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
├── README.md                      # Este archivo
├── .gitignore                     # Exclusiones de git
├── spoken_assistant_ptt.py        # 🎙️ RECOMMENDED: Push-to-talk con F7
├── spoken_assistant.py            # Legacy: VAD automático
├── setup.sh                        # Script de instalación
├── docs/
│   ├── references/                 # Referencias visuales (UI)
│   └── roadmap/                    # Documentación de roadmap
├── exemple/                        # Archivos de referencia
│   └── voice_preview_cristina.mp3 # Voz de referencia
├── scripts/                        # Scripts de utilidad
│   ├── tts_benchmark.py            # Benchmark comparativo
│   ├── test_kokoro_english.py      # Test voz Kokoro EN
│   └── ...                         # Otros tests
└── artifacts/                      # Artefactos generados (no en git)
    └── kokoro-en-test/             # Archivos de audio
```

## 🎙️ Spoken Assistant - Push to Talk (F7) ⭐ RECOMMENDED

La versión **`spoken_assistant_ptt.py`** es la versión recomendada con push-to-talk:

### Flujo
1. **Escucha** audio del micrófono con VAD (Voice Activity Detection)
2. **STT** usando Parakeet v3 (transcripción español)
3. **Traducción** español → inglés (MarianMT)
4. **TTS** usando Kokoro voz `af_bella` (síntesis voz femenina en inglés)
5. **Reproducción** del audio generado

### Uso rápido (Push-to-Talk con F7)
```bash
# Setup (solo una vez)
source artifacts/kokoro-venv/bin/activate
pip install pynput  # Para hotkey F7

# Ejecutar versión push-to-talk (RECOMMENDED)
python spoken_assistant_ptt.py

# Instrucciones:
#   🔴 Mantén F7 pulsado para GRABAR
#   ⏹️  Suelta F7 para PROCESAR y hablar
#   ❌ ESC para salir
```

### Ejemplo de interacción (Push-to-Talk)
```
🎙️  SPOKEN ASSISTANT - Push to Talk (F7)
============================================================
✅ Listo! Pulsa F7 para empezar...
============================================================

🔴 GRABANDO... (suelta F7 para procesar)
⏹️  Procesando...
   Audio: 2.3s
📝 Transcribiendo...
   ES: "hola cómo estás"
🌐 Traduciendo...
   EN: "hello how are you"
🔊 Generando voz...
🔈 Reproduciendo...
✅ Completado

🔴 GRABANDO... (suelta F7 para procesar)
...
```

### Versión Legacy (VAD automático)
```bash
# Versión con detección automática de voz (menos recomendada)
python spoken_assistant.py
```

## Scripts Disponibles

### Pipeline Principal (Push-to-Talk) ⭐
```bash
# Asistente push-to-talk con F7 (RECOMMENDED)
python spoken_assistant_ptt.py
```

### Pipeline Legacy (VAD automático)
```bash
# Asistente con detección automática de voz
python spoken_assistant.py

# Setup de dependencias
./setup.sh
```

### Benchmark TTS (Desarrollo)
```bash
# Comparar motores TTS
python scripts/tts_benchmark.py

# Test de Kokoro en inglés
python scripts/test_kokoro_english.py

# Test de Qwen3-TTS MLX (standby)
python scripts/test_qwen3_mlx.py
```

## 🚀 Instalación Rápida

### Opción 1: Script automático
```bash
# Clonar repositorio
git clone https://github.com/nicorosaless/nicobot.git
cd nicobot

# Setup automático (crea .venv e instala todo)
./setup.sh

# Ejecutar asistente
source .venv/bin/activate
python spoken_assistant.py
```

### Opción 2: Manual
```bash
# Clonar repositorio
git clone https://github.com/nicorosaless/nicobot.git
cd nicobot

# Crear entorno virtual
python3.12 -m venv .venv
source .venv/bin/activate

# Instalar dependencias
pip install kokoro soundfile torch transformers sounddevice numpy

# Instalar NeMo para Parakeet (tarda unos minutos)
pip install nemo_toolkit['asr']

# Ejecutar
python spoken_assistant.py
```

### Requisitos

- Python 3.10+
- macOS con Apple Silicon (M1/M2/M3) o CPU
- Micrófono funcional
- 8GB+ RAM recomendado
- ~2GB libres para modelos (Kokoro + Parakeet)

## Roadmap

### Fase 1: Infraestructura de Voz ✅
- [x] Benchmark exhaustivo de motores TTS (12 motores probados)
- [x] Selección de motor único: Kokoro `af_bella` (inglés)
- [x] Stack simplificado: una sola dependencia TTS
- [x] Validación de velocidad y calidad
- [x] Limpieza de repositorio y preparación para git

### Fase 2: Pipeline STT → TTS ✅
- [x] Implementar `spoken_assistant.py` con pipeline completo
- [x] Parakeet v3 (STT español) integrado
- [x] Traductor ES→EN (MarianMT) funcionando
- [x] Kokoro TTS (af_bella inglés) integrado
- [x] VAD (Voice Activity Detection) para detección de voz
- [x] Audio grabado → transcrito → traducido → hablado

### Fase 3: Integración Hermes Agent ⏳
- [ ] Añadir Hermes Agent al pipeline
- [ ] Validar payloads de streaming

### Fase 4: Expansión de Stack TTS (Futuro) ⏳
- [ ] Evaluar adición de Qwen3-TTS MLX (español)
- [ ] Decisión basada en feedback y necesidades
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

### Selección de TTS - Fase Simplificada

**Stack actual (Kokoro único):**

Tras probar 12 motores, seleccionamos **Kokoro único** para fase inicial:

**Ventajas del stack simplificado:**
1. **Simplicidad:** Una sola dependencia TTS
2. **Velocidad:** RTF ~0.21x, ultra-rápido
3. **Calidad:** Grade A, voz femenina natural en inglés
4. **Setup trivial:** `pip install kokoro`
5. **Debugging:** Menor complejidad = desarrollo más rápido

**Motor seleccionado:**
- **Kokoro** `af_bella`: American Female, Grade A, calidad premium
- RTF ~0.21x (5× más rápido que tiempo real)
- Idioma: Inglés americano

**Expansión futura (cuándo añadir más motores):**
- **Qwen3-TTS MLX:** Reservado para cuando se necesite español nativo
- Condición de activación: Feedback de usuarios o requerimiento de español
- Ventaja de esperar: Stack simple = desarrollo más ágil

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
**Estado:** Pipeline STT → TTS implementado y funcionando. `spoken_assistant.py` listo para usar.
