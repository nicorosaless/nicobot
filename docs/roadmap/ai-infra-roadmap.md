# NicoBot AI Infra Roadmap

**Estado del documento:** Actualizado  
**Última actualización:** 17 Abril 2026  
**Fase actual:** Fase 1 completada - Preparando Fase 2

---

## Resumen Ejecutivo

La Fase 1 (Infraestructura de Voz) ha sido **completada exitosamente**. Se validó el stack de TTS con voz clonada premium usando Qwen3-TTS MLX, alcanzando RTF < 1.0x (más rápido que tiempo real) para frases largas.

**Stack de TTS seleccionado:**
- **Motor principal:** Qwen3-TTS MLX (voz de Cristina clonada, RTF ~0.7-1.2x)
- **Motor rápido:** Kokoro (pendiente de integración, RTF ~0.1-0.3x)

---

## Objetivo de esta fase

Definir y validar la infraestructura de IA (STT, Agent, TTS, orquestación y observabilidad) antes de decidir el framework de UI final.

Nota: el framework de UI está pendiente de decisión. Por ahora solo se asume una UI mínima en forma de cuadrado con tres bloques:
- Transcripción (STT)
- Ejecución del agente (Hermes)
- Salida hablada (TTS)

---

## Stack técnico validado

### TTS (✅ COMPLETADO)

**Decisión final:** Stack híbrido

| Motor | RTF | Uso | Estado |
|-------|-----|-----|--------|
| Qwen3-TTS MLX 8-bit | ~0.7-1.2x | Narración progresiva, mensajes largos | ✅ Validado |
| Kokoro-82M | ~0.1-0.3x | Respuestas cortas (< 5 palabras) | ⏳ Pendiente |

**Detalles de implementación:**
- Modelo: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- Plataforma: MLX nativo (Apple Silicon)
- Memoria peak: ~6GB
- Voz clonada: Cristina (referencia en inglés, habla español nativo)

**Optimizaciones aplicadas:**
1. Pre-computación de x_vector (embedding de voz)
2. Transcripción manual de referencia (evita Whisper)
3. Modelo 8-bit (balance calidad/velocidad/memoria)

**Comparativa de cuantización probada:**
- 8-bit: RTF ~0.7-1.2x, calidad excelente ✅ Seleccionado
- 6-bit: RTF ~1.0-1.5x, calidad buena
- 4-bit: RTF ~1.5-2.0x, calidad inferior

### Runtime principal
- Python 3.12
- Entorno virtual por proyecto
- Proceso backend único para orquestar STT → Agent → TTS

### STT (Pendiente de integración)
- Modelo principal: NVIDIA Parakeet (local)
- Entrada: audio 16 kHz mono
- Salida:
  - tokens/parciales en streaming
  - transcripción final por turno

### Agent (Pendiente de validación)
- Backend: Hermes Agent (streaming)
- Funciones:
  - recibir texto final de STT
  - generar respuesta en tokens
  - emitir eventos de tools (inicio, progreso, fin)
  - devolver texto para TTS

### Ritmo de inferencia y UX objetivo
- El producto se optimiza para sensación de inmediatez.
- Dos modos de interacción a cubrir:
  - preguntas rápidas (respuesta inmediata)
  - tareas agenticas largas (narración progresiva de estado)
- SLO iniciales:
  - VAD end → primer token de agente: <400-700 ms
  - VAD end → primer audio TTS (TTFA): <800 ms ideal, <1.2 s máximo
  - gap entre chunks de audio: <120 ms
- Requisito de producto: mientras Hermes ejecuta acciones, el usuario debe recibir mensajes de progreso por UI y voz sin esperar al resultado final.

### Riesgo/unknown actual de Hermes
- Aún no hemos validado los payloads reales de streaming de Hermes en este repo.
- Antes de cerrar la política de narración necesitamos capturar y clasificar outputs reales (tokens, eventos de tools, posibles estados intermedios).

### Orquestación y comunicaciones internas
- Bus de eventos interno en Python
- Contrato de eventos recomendado:
  - `stt.partial`
  - `stt.final`
  - `agent.token`
  - `agent.tool.start`
  - `agent.tool.end`
  - `tts.start`
  - `tts.chunk`
  - `tts.end`

### Persistencia (fase inicial)
- Logs estructurados (JSONL)
- Artefactos de benchmark TTS:
  - WAV generados (no versionados)
  - CSV/JSON de métricas

### Observabilidad mínima
- Métricas por turno:
  - latencia STT
  - latencia Agent (primer token y total)
  - latencia TTS (TTFA + total)
  - memoria pico del proceso

---

## Plan por pasos

### Paso 0 - Base de referencia visual ✅ COMPLETADO
- Guardar captura de la UI de referencia (Spokenly) en el repo
- Resultado esperado: archivo de referencia disponible en `docs/references/`
- Estado: ✅ Completado
- Artefacto: `docs/references/spokenly-widget-reference.png`

### Paso 1 - Benchmark TTS y selección de motor ✅ COMPLETADO
- Evaluar múltiples motores TTS locales (11 probados)
- Medir velocidad, RAM y calidad subjetiva
- Seleccionar stack híbrido óptimo
- **Estado:** ✅ Completado 17 Abril 2026

**Motores evaluados:**
1. Kokoro - Rápido pero sin voice cloning premium
2. MeloTTS - Intermedio, acento no ideal
3. Piper - Muy rápido, voces pre-entrenadas limitadas
4. Edge TTS - Cloud, no local
5. XTTS v2 - Lento, acento mezclado
6. MOSS-TTS-Nano - Calidad mixta
7. F5-TTS - Problemas de setup
8. LuxTTS - Sesgo inglés persistente
9. Chatterbox - Acento no español
10. OpenVoice - Funcional pero lento
11. CosyVoice - Lento en PyTorch

**Decisión final:** Qwen3-TTS MLX 8-bit para voz clonada premium

**Implementación:**
- Scripts creados:
  - `scripts/tts_benchmark.py` - Benchmark general
  - `scripts/test_qwen3_mlx.py` - Test MLX
  - `scripts/test_qwen3_mlx_4bit.py` - Comparativa cuantización
  - `scripts/qwen3_service.py` - Servicio reutilizable

**Resultados finales:**
- Modelo seleccionado: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit`
- RTF frases largas: ~0.7x (más rápido que tiempo real) ⭐
- RTF frases cortas: ~1.2-3x
- Memoria: ~6GB peak
- Calidad: Excelente, acento español correcto

### Paso 2 - Integración de Kokoro (MOTOR RÁPIDO) ⏳ PENDIENTE
- Integrar Kokoro para respuestas instantáneas
- Target: RTF < 0.3x para < 5 palabras
- Implementar selector automático por longitud de texto
- **Estado:** ⏳ Pendiente - Siguiente tarea

### Paso 3 - Pipeline STT -> Hermes -> TTS (CLI) ⏳ PENDIENTE
- Implementar pipeline completo en modo consola
- Verificar streaming de eventos entre etapas
- Validar payloads reales de Hermes
- Salida del paso:
  - respuesta hablada end-to-end sin UI final
- **Estado:** ⏳ Pendiente

### Paso 4 - UI mínima cuadrada conectada a eventos ⏳ PENDIENTE
- Renderizar en tiempo real:
  - bloque STT
  - bloque Agent
  - bloque TTS
- Sin decisiones estéticas finales; foco en estabilidad
- **Estado:** ⏳ Pendiente

### Paso 5 - Decisión de framework UI ⏳ PENDIENTE
- Con datos de latencia y estabilidad del backend, decidir framework UI
- Este paso se toma después de validar la infraestructura IA
- **Estado:** ⏳ Pendiente

---

## Criterios de salida de la fase actual

La Fase 1 (Infraestructura de Voz) está **COMPLETADA**:
- ✅ Benchmark reproducible de múltiples motores TTS
- ✅ Stack híbrido definido y validado
- ✅ Voz de Cristina clonada con calidad premium
- ✅ Optimizaciones de velocidad aplicadas
- ✅ Repositorio limpio y preparado para git

**Criterios de salida de Fase 2 (Pipeline Completo):**
- Kokoro integrado y funcionando
- Pipeline STT → Hermes → TTS end-to-end
- Validación de streaming de Hermes
- UI mínima con 3 estados

---

## Comandos útiles

### Benchmark TTS
```bash
# Comparar motores básicos
python scripts/tts_benchmark.py

# Test Qwen3-TTS MLX
python scripts/test_qwen3_mlx.py

# Comparativa 4/6/8-bit
python scripts/test_qwen3_mlx_4bit.py

# Servicio Qwen3-TTS
python scripts/qwen3_service.py
```

### Setup entorno MLX
```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install mlx==0.31.1 mlx-lm==0.31.1 mlx-audio
```

---

## Notas técnicas

### Por qué Qwen3-TTS MLX ganó
1. **Calidad:** Único motor que mantiene acento español correcto con voz clonada
2. **Velocidad:** RTF < 1.0x para frases largas (más rápido que tiempo real)
3. **Eficiencia:** ~6GB RAM, nativo Apple Silicon
4. **Optimizable:** Pre-computación de embeddings elimina delay inicial

### Por qué stack híbrido
- Qwen3-TTS: Calidad premium pero RTF ~3x para frases muy cortas
- Kokoro: RTF ~0.1x ideal para "Hola", "Sí", "Entendido", "Procesando..."
- Combinación óptima: calidad cuando importa, velocidad cuando se necesita

### Lecciones aprendidas
1. PyTorch MPS en Mac es más lento que CPU para TTS
2. MLX nativo es 3-5× más rápido que PyTorch
3. 8-bit es el sweet spot (calidad/velocidad/memoria)
4. Pre-computar x_vector ahorra ~6 segundos por request
5. Transcripción manual de referencia elimina delay de Whisper (~15s)
