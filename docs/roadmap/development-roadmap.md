# Roadmap de desarrollo

## Resumen

El roadmap oficial de NicoBot prioriza una v1 visual por hotkeys. El backend de voz existente sigue disponible como base técnica, pero no marca el orden de implementación del producto.

## Fase 1: refactor de documentación

Entregables:

- índice de `docs/`
- visión de producto
- arquitectura oficial de la v1
- roadmap único
- referencias de Omi
- specs de UI del agente

Criterio de done:

- cualquier colaborador puede entender la v1 sin leer código
- no hay contradicciones entre roadmap, arquitectura y UI

## Fase 2: shell de agente por hotkeys

Entregables:

- apertura del agente mediante hotkey
- cierre consistente del panel
- creación o recuperación de sesión conversacional
- greeting inicial automático

Criterio de done:

- la hotkey abre NicoBot siempre en el estado correcto
- el usuario ve el greeting sin pasos intermedios

## Fase 3: display estilo Omi

Entregables:

- barra flotante compacta
- panel expandido de conversación
- cabecera ligera de estado
- historial scrollable
- input persistente inferior
- tratamiento visual de error

Criterio de done:

- la UI recuerda a Omi en estructura y ritmo
- el contenido prima sobre métricas y logs

## Fase 4: integración Hermes

Entregables:

- ✅ backend conectado al Hermes Agent local mediante API Server OpenAI-compatible
- ✅ contrato SSE principal en `/v1/chat/stream` con eventos `tok`, `sent` y `done`
- ✅ UI de chat conectada a streaming progresivo token/chunk
- ✅ fallback no-streaming cuando Hermes cierra un stream sin texto
- ✅ estado visible Backend/Hermes en la cabecera del chat
- ✅ `run.sh` arranca Hermes API Server, backend Rust y app SwiftUI
- Pendiente: normalizar eventos internos `agent:open`, `agent:submitPrompt`, `agent:state`, `agent:response` si el panel flotante pasa a usar un bus explícito

Criterio de done:

- el usuario puede mantener una conversación completa en el panel
- los errores son recuperables y legibles

Estado actual:

- cumplido para el flujo de chat de escritorio por texto
- el contrato deja `tok` para UI/TTS token a token y `sent` para síntesis por segmentos
- TTS real sigue fuera de esta fase

## Fase 5: contexto visual posterior

Objetivo:

- evaluar incorporación de captura de pantalla y contexto de ventana

Incluye:

- posible helper Swift
- permisos de screen recording
- screenshot on demand o por reglas

Fuera de esta fase temprana:

- no se implementa antes de validar la utilidad de la v1 visual

## Fase 6: voz posterior

Objetivo:

- reincorporar el backend de voz cuando la UI del agente ya esté estabilizada

Incluye:

- STT/TTS como flujo opcional o modo alternativo
- reuso del backend actual cuando encaje

## Separación oficial por versiones

### `v1`

- agente visual
- hotkeys
- greeting inicial
- conversación por texto

### `v1.1` o `v2`

- contexto visual
- captura de pantalla
- permisos macOS asociados

### `v2+`

- voz
- STT/TTS
- automatización más profunda
