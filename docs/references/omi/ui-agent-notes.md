# Notas de UI del agente inspiradas en Omi

## Patrones observados en Omi

### Entrada compacta y expansión natural

Omi mantiene una presencia mínima cuando el agente no está activo y expande la interfaz solo cuando hay intención clara del usuario.

Aplicación en NicoBot:

- barra flotante pequeña y discreta
- panel expandido solo al invocar con hotkey o continuar conversación

### Cabecera ligera de estado

Omi no sobrecarga la cabecera; usa un estado corto y comprensible.

Aplicación en NicoBot:

- usar copy breve como estado del agente
- evitar toolbars pesadas, métricas o badges de depuración en la parte superior

### Conversación centrada en contenido

La respuesta del agente ocupa el centro de gravedad de la UI.

Aplicación en NicoBot:

- prioridad a greeting, mensaje del usuario y respuesta
- logs técnicos fuera del layout principal

### Follow-up persistente

Omi mantiene el siguiente paso conversacional muy cerca del contenido.

Aplicación en NicoBot:

- input fijo en la parte inferior del panel
- no esconder el punto de continuación tras responder

### Thinking visible pero sobrio

Omi transmite actividad sin convertirla en telemetría.

Aplicación en NicoBot:

- estado `thinking` visible
- sin cascada de eventos crudos en la superficie principal

## Traducción visual a NicoBot

- NicoBot debe parecer una herramienta propia, no un clon.
- El parecido fuerte se buscará en estructura, densidad visual y comportamiento.
- El branding, copy y detalles cromáticos deben consolidar una identidad propia.

## Regla de diseño para implementar

Si un elemento visual no mejora uno de estos tres objetivos, no debe estar en el panel principal:

- claridad del estado del agente
- lectura de la respuesta
- continuidad de la conversación
