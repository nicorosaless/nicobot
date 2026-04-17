# NicoBot - Speech-to-Speech AI Agent

Un asistente de voz conversacional en tiempo real que combina speech-to-text de última generación, un agente inteligente con capacidad de ejecutar herramientas, y síntesis de voz streaming.

> **Estado del proyecto:** Stack TTS simplificado - usando solo Kokoro (inglés) para fase inicial. Qwen3-TTS MLX validado pero standby. Listo para pipeline STT → TTS.

---

## Estado Actual del Proyecto (17 Abril 2026)

### ✅ Completado

#### Infraestructura de Voz (TTS)
- **Benchmark exhaustivo** de motores TTS locales (12 probados)
- **Motor seleccionado:** Kokoro `af_bella` (único motor activo)
  - Voz: Femenina americana, Grade A, calidad premium
  - RTF: ~0.21x (5× más rápido que tiempo real)
  - Idioma: Inglés americano
  - Setup trivial, ultra-rápido, calidad excelente
  
- **Motores evaluados y standby:**
  - Qwen3-TTS MLX: Validado para español + voice cloning (reservado)
  - Piper, MeloTTS, XTTS, etc.: Evaluados pero no seleccionados

- **Stack simplificado (fase inicial):**
  - Una sola dependencia TTS: Kokoro
  - Simplicidad máxima para desarrollo rápido
  - Qwen3-TTS MLX standby para expansión futura

### 🔄 En Progreso

- **Pipeline STT → Kokoro TTS:**
  - Integración de Parakeet (STT) con Kokoro (TTS)
  - Pipeline CLI end-to-end
  - Output en audio hablado

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
- [x] Benchmark exhaustivo de motores TTS (12 motores probados)
- [x] Selección de motor único: Kokoro `af_bella` (inglés)
- [x] Stack simplificado: una sola dependencia TTS
- [x] Validación de velocidad y calidad
- [x] Limpieza de repositorio y preparación para git

### Fase 2: Pipeline STT → TTS (Actual)
- [ ] Integración de Parakeet (STT) con Kokoro (TTS)
- [ ] Pipeline CLI end-to-end funcionando
- [ ] Tests de integración

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
**Estado:** Fase 1 completada - Stack simplificado (Kokoro único). Fase 2 en progreso: Pipeline STT → TTS.
