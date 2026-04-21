# Spec del display del agente

## Objetivo

Definir la interfaz principal del agente para la v1 de NicoBot. Debe ser una adaptación muy cercana a Omi en estructura e interacción, pero con identidad propia.

## Superficies principales

### Barra flotante compacta

Función:

- indicar presencia del agente
- servir como punto de entrada al panel expandido

Comportamiento:

- visible en estado colapsado
- pequeña y discreta
- se abre con hotkey

### Panel expandido de conversación

Función:

- mostrar greeting
- renderizar historial
- aceptar input de texto
- mostrar respuesta o error

## Estados obligatorios

- `idle`
- `opened`
- `thinking`
- `responding`
- `error`

## Flujo base

1. El usuario pulsa hotkey.
2. La UI se abre.
3. Se muestra el greeting inicial.
4. El usuario escribe una petición.
5. El agente entra en `thinking`.
6. Se renderiza la respuesta.
7. El input sigue disponible abajo para continuar.

## Layout del panel

### Cabecera

Debe incluir:

- nombre o identidad del agente
- estado breve y legible

No debe incluir:

- logs
- métricas
- información técnica irrelevante para la conversación

### Historial

Debe:

- ser scrollable
- mostrar claramente qué dijo el usuario y qué respondió el agente
- soportar respuestas largas

### Greeting inicial

Debe:

- aparecer automáticamente al abrir
- orientar al usuario
- marcar el tono del producto

### Input inferior

Debe:

- permanecer accesible tras cada respuesta
- servir como continuación natural de la conversación

## Reglas de contenido

- El panel principal no muestra logs técnicos por defecto.
- El historial es la unidad principal de lectura.
- Los errores deben aparecer de forma recuperable y clara.
- La respuesta del agente siempre debe tener prioridad visual frente a cualquier metadato.

## Reglas visuales

- abandonar la estética de shell temporal
- consolidar la marca NicoBot
- mantener una densidad visual sobria y elegante
- priorizar legibilidad sobre ornamentación

## Vista secundaria de diagnóstico

Si existe, debe quedar separada del panel del agente y reservarse para:

- logs
- eventos internos
- estado técnico de integración

Nunca debe competir con la conversación principal.
