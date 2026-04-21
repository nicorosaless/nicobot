# Interfaces locales de la v1

## Objetivo

Definir el contrato mínimo entre la UI y Hermes Agent para implementar la v1 sin depender de voz ni captura de pantalla.

## Contratos UI / bridge local

### `agent:open`

Propósito:

- abrir la barra o panel del agente
- inicializar el estado visual
- solicitar el greeting inicial si la sesión aún no lo tiene

Payload esperado:

- `source`: origen de la apertura, por ejemplo `hotkey`
- `sessionId?`: identificador opcional de sesión actual

### `agent:close`

Propósito:

- cerrar el panel del agente
- dejar el estado en `idle` o conservar contexto mínimo de sesión según convenga

Payload esperado:

- `sessionId?`

### `agent:submitPrompt`

Propósito:

- enviar el prompt del usuario a Hermes

Payload esperado:

- `sessionId`
- `prompt`
- `metadata?`

### `agent:state`

Propósito:

- informar a la UI del estado actual del agente

Estados mínimos soportados:

- `idle`
- `opened`
- `thinking`
- `responding`
- `error`

Payload esperado:

- `sessionId`
- `state`
- `message?`

### `agent:response`

Propósito:

- entregar a la UI el greeting inicial o una respuesta conversacional

Payload esperado:

- `sessionId`
- `kind`: `greeting` o `response`
- `content`
- `timestamp`

## Contrato mínimo de Hermes Agent

### Entrada

- `prompt`
- `sessionId`
- `metadata?`

### Salida

- `greeting` inicial cuando la sesión se abre por primera vez
- `response` renderizable para el historial
- `state` para sincronizar la UI
- `error` legible por el usuario si algo falla

## Decisiones cerradas

- Tras el greeting, el agente espera input de texto.
- No existe modo de escucha, grabación o push-to-talk en la v1.
- No se pasa contexto visual ni screenshot al agente.
- Los logs internos no forman parte del contrato principal de UI.

## Interfaces aplazadas

Estas no forman parte del scope actual y deben documentarse como futuras:

- endpoints/eventos de grabación
- métricas STT/TTS
- screen capture
- active window context
- permisos de micrófono o screen recording
