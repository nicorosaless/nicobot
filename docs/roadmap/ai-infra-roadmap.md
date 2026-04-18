# NicoBot AI Infra Roadmap

**Estado del documento:** Actualizado  
**Última actualización:** 17 Abril 2026  
**Fase actual:** Fase 1 completada - Usando solo Kokoro (temporal)

---

## Resumen Ejecutivo

La Fase 1 (Infraestructura de Voz) ha sido **completada exitosamente**. 

**Stack actual (simplificado):**
- **Motor único:** Kokoro (voz af_bella, inglés, Grade A)
- **RTF:** ~0.21x (5× más rápido que tiempo real)
- **Nota:** Qwen3-TTS MLX validado pero no activo en el stack actual

**Motivación del stack simplificado:**
- Priorizar velocidad y simplicidad en desarrollo inicial
- Voz femenina premium en inglés (af_bella)
- Una sola dependencia TTS para facilitar desarrollo y debugging

---

## Stack TTS Actual (Fase Actual)

### TTS (✅ ACTIVO - Kokoro único)

**Decisión actual:** Usar únicamente Kokoro para todo el TTS

| Motor | RTF | Uso | Estado |
|-------|-----|-----|--------|
| **Kokoro-82M** `af_bella` | **~0.21x** | Todas las respuestas | ✅ **Activo** |
| Qwen3-TTS MLX | ~0.7-1.2x | Reservado para futuro | ⏳ Standby |

**Detalles de implementación:**
- Modelo: `hexgrad/Kokoro-82M`
- Voz: `af_bella` (American Female, Grade A, HH hours training)
- Idioma: Inglés americano
- Plataforma: PyTorch (CPU/MPS)
- Memoria: ~300MB
- Speed: 1.0 (configurable)

**Por qué Kokoro único (por ahora):**
1. **Simplicidad:** Una sola dependencia TTS
2. **Velocidad:** RTF ~0.21x ultra-rápido
3. **Calidad:** Grade A, voz femenina natural
4. **Facilidad:** Setup trivial, no requiere referencias de audio
5. **Debugging:** Menor complejidad durante desarrollo inicial

**Qwen3-TTS MLX reservado para:**
- Fases posteriores cuando se necesite español nativo
- Narración de progreso con voz clonada (Cristina)
- Cuando la calidad premium justifique el overhead

---

## Plan por pasos actualizado

### Paso 0 - Base de referencia visual ✅ COMPLETADO
- Guardar captura de la UI de referencia (Spokenly) en el repo
- Resultado esperado: archivo de referencia disponible en `docs/references/`
- Estado: ✅ Completado
- Artefacto: `docs/references/spokenly-widget-reference.png`

### Paso 1 - Benchmark TTS y selección de motor ✅ COMPLETADO
- Evaluar múltiples motores TTS locales (12 probados)
- Seleccionar motor óptimo para fase inicial
- **Estado:** ✅ Completado 17 Abril 2026
- **Decisión actual:** Kokoro único para simplicidad

**Motores evaluados:**
1. Kokoro - ✅ **SELECCIONADO** (rápido, calidad A, inglés)
2. MeloTTS - Evaluado
3. Piper - Evaluado
4. Edge TTS - Evaluado
5. XTTS v2 - Evaluado
6. MOSS-TTS-Nano - Evaluado
7. F5-TTS - Evaluado
8. LuxTTS - Evaluado
9. Chatterbox - Evaluado
10. OpenVoice - Evaluado
11. CosyVoice - Evaluado
12. Qwen3-TTS - ✅ Validado, standby

**Stack simplificado:**
- Motor: Kokoro `af_bella`
- RTF: ~0.21x (5× más rápido que tiempo real)
- Idioma: Inglés americano
- Voz: Femenina premium (Grade A)

### Paso 2 - Integración de Kokoro ✅ COMPLETADO
- Kokoro integrado y funcionando
- Scripts de test creados
- Voz af_bella validada
- **Estado:** ✅ Completado

### Paso 3 - Pipeline STT -> Kokoro TTS (CLI) ✅ COMPLETADO
- Pipeline completo en modo consola implementado
- STT (Parakeet) -> Traducción ES->EN -> Kokoro TTS
- Push-to-talk estable con toggle (`F7`, fallback `r`/space)
- Métricas por turno (STT/TTS) visibles en terminal
- **Estado:** ✅ Completado

### Paso 4 - Integración con Hermes Agent ⏳ PENDIENTE
- Añadir Hermes Agent al pipeline
- Decisión dinámica de idioma (EN/ES)
- Validar payloads de streaming
- **Estado:** ⏳ Pendiente

### Paso 5 - UI mínima cuadrada ⏳ PENDIENTE
- Renderizar bloques: STT, Agent, TTS
- Foco en estabilidad
- **Estado:** ⏳ Pendiente

### Paso 6 - Empaquetado app descargable ⏳ NUEVO
- Congelar backend como servicio local empaquetado
- Definir estrategia de distribución macOS (.app/.dmg)
- Definir firma/notarización
- **Estado:** ⏳ Pendiente

### Paso 7 - Re-evaluación de stack TTS ⏳ FUTURO
- Decidir si añadir Qwen3-TTS MLX para español
- Evaluar necesidad de voz clonada (Cristina)
- Decisión basada en feedback de uso
- **Estado:** ⏳ Futuro

---

## Criterios de salida de fases

**Fase 1 (Infraestructura de Voz):** ✅ COMPLETADA
- Benchmark de motores TTS
- Kokoro seleccionado e integrado
- Voz af_bella validada

**Fase 2 (Pipeline STT-TTS):** ⏳ EN PROGRESO
- Pipeline STT → Kokoro TTS funcionando
- CLI funcional end-to-end

**Fase 3 (Integración Agent):** ⏳ PENDIENTE
- Hermes Agent integrado
- Decisión EN/ES implementada

**Fase 4 (UI):** ⏳ PENDIENTE
- UI mínima operativa
- Eventos conectados

**Fase 5 (Stack TTS expandido):** ⏳ FUTURO
- Evaluar adición de Qwen3-TTS MLX
- Decisión basada en necesidades reales

---

## Comandos útiles

### Setup Kokoro (entorno actual)
```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install kokoro soundfile
```

### Test Kokoro
```bash
# Test rápido de voz af_bella
python scripts/test_kokoro_english.py
```

### Benchmark (referencia)
```bash
# Benchmark general (opcional)
python scripts/tts_benchmark.py

# Tests Qwen3-TTS MLX ( standby )
python scripts/test_qwen3_mlx.py
```

---

## Notas técnicas

### Por qué Kokoro único (fase inicial)

**Ventajas:**
1. **Simplicidad:** Setup trivial, una sola dependencia
2. **Velocidad:** RTF ~0.21x, ultra-rápido
3. **Calidad:** Grade A, voz femenina natural
4. **Fiabilidad:** No requiere referencias de audio ni embeddings
5. **Debugging:** Menor complejidad = bugs más fáciles de detectar

**Limitaciones aceptadas:**
- Solo inglés (para fase inicial)
- No voice cloning (no necesario ahora)
- Acento americano (adecuado para asistente AI)

### Cuándo añadir Qwen3-TTS MLX

**Condiciones para expandir el stack:**
1. Necesidad real de español nativo en narración
2. Feedback de usuarios pidiendo voz en español
3. Requerimiento de voice cloning (Cristina)
4. Complejidad justificada por valor añadido

**Hasta entonces:** Kokoro único mantiene el stack simple y rápido.

---

**Mantenido por:** nicorosaless  
**Repositorio:** https://github.com/nicorosaless/nicobot
